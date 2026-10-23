import Foundation
import DocumentCore

/// The OPC / WordprocessingML reading and basic writing codec for DOCX or DOCM.
public struct DOCXCodec: DocumentCodec {
    /// The selected Word package format: DOCX or macro-enabled DOCM.
    public let format: DocumentFormat
    public init(macroEnabled: Bool = false) { format = macroEnabled ? .docm : .docx }
    public func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult {
        try read(OPCPackage(data, limits: options.limits), options: options)
    }
    public func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try inspect(OPCPackage(data, limits: limits))
    }
    public func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try scan(OPCPackage(data, limits: options.limits), options: options, onBlock: onBlock)
    }
}

extension DOCXCodec: PreparedDocumentCodec {
    package func read(_ package: OPCPackage, options: ReadOptions) throws -> ReadResult {
        try Task.checkCancellation()
        var blocks: [Block] = []
        var result = try scan(package, options: options) { blocks.append($0) }
        result.document.blocks = blocks
        return ReadResult(document: result.document)
    }
    package func inspect(_ package: OPCPackage) throws -> DocumentSummary {
        try Task.checkCancellation()
        guard package.format == format else { throw DocumentError.corruptedPackage("codec / MIME mismatch") }
        return DocumentSummary(format: format, metadata: try metadata(in: package), parts: package.parts)
    }
    package func scan(_ package: OPCPackage, options: ReadOptions, onBlock: (Block) throws -> Void) throws -> ScanResult {
        try Task.checkCancellation()
        guard package.format == format else { throw DocumentError.corruptedPackage("codec / MIME mismatch") }
        let warnings = WarningCollector()
        // All parsing stages share one collector, including style resolution and related stories.
        let props = Properties(warnings)
        let relationships = try package.relationships(from: package.mainPart)
        func path(_ type: String) throws -> String? {
            let matches = relationships.values.filter { $0.type == type }
            guard matches.count <= 1 else { throw DocumentError.corruptedPackage("duplicate \(type) relationships") }
            guard let match = matches.first else { return nil }
            guard let path = match.path else { throw DocumentError.invalidRelationship(part: package.mainPart, detail: "external \(type) part") }
            return path
        }
        let stylePart = try path("styles"), numberingPart = try path("numbering"), fontPart = try path("fontTable")
        let themePart = try path("theme"), settingsPart = try path("settings")
        props.theme = try loadTheme(themePart, package: package, warnings: warnings)
        if let settingsPart {
            let settings = try XMLTree.parse(package.archive.read(settingsPart), part: settingsPart, limits: options.limits)
            if let mapping = settings.child("clrSchemeMapping") {
                let keys: Set<String> = ["bg1", "t1", "bg2", "t2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hyperlink", "followedHyperlink"]
                let values: Set<String> = ["light1", "dark1", "light2", "dark2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hyperlink", "followedHyperlink"]
                for key in keys {
                    if let value = mapping.attr(key) {
                        if values.contains(value) { props.themeColorMapping[key] = value }
                        else { props.unparsed(mapping, part: settingsPart) }
                    }
                }
                if props.hasExtraAttributes(mapping, allowed: keys) || !mapping.children.isEmpty { props.unparsed(mapping, part: settingsPart) }
            }
            if let language = settings.child("themeFontLang") {
                props.themeLanguages = ["latin": language.attr("val"), "ea": language.attr("eastAsia"), "cs": language.attr("bidi")].compactMapValues { $0 }
            }
        }
        let styles = try loadStyles(stylePart, package: package, properties: props, warnings: warnings)
        let references = StoryReferences()
        var document = Document()
        document.sourceFormat = format; document.metadata = try metadata(in: package, warnings: warnings)
        document.packageParts = package.parts; document.styles = styles.styles
        document.numbering = try loadNumbering(numberingPart, package: package, properties: props)
        document.fonts = try loadFontTable(fontPart, package: package, warnings: warnings)
        document.theme = props.theme
        document.attach(package.archive, limits: options.limits)
        if let settings = settingsPart {
            let root = try XMLTree.parse(package.archive.read(settings), part: settings, limits: options.limits)
            guard root.isWord, root.name == "settings" else { throw DocumentError.invalidXML(part: settings, detail: "expected settings root") }
            for child in root.children { document.settings[child.name] = child.xml }
        }
        let reader = StoryReader(package: package, part: package.mainPart, relationships: relationships, styles: styles, properties: props, options: options, warnings: warnings, numbering: document.numbering, references: references)
        try reader.prepareCharts()
        var blocksRead = 0
        try withoutActuallyEscaping(onBlock) { callback in
            let joiner = ParagraphJoiner(view: options.revisions, warnings: warnings, part: package.mainPart)
            func emit(_ block: Block) throws {
                try Task.checkCancellation(); try callback(block); try Task.checkCancellation(); blocksRead += 1
            }
            let root = try XMLTree.parse(package.archive.read(package.mainPart), part: package.mainPart, limits: options.limits) { node in
                try Task.checkCancellation()
                if node.isWord && node.name == "sectPr" { reader.sections.append(try reader.section(node)); return }
                for block in try reader.blocks([node]) {
                    for output in joiner.offer(block) { try emit(output) }
                }
            }
            guard root.isWord, root.name == "document", root.wordChildren("body").count == 1 else { throw DocumentError.invalidXML(part: package.mainPart, detail: "expected document / body") }
            reader.finishFields()
            for output in joiner.finish() { try emit(output) }
            for child in root.children where !(child.isWord && child.name == "body") {
                document.uninterpretedContent.append(reader.unsupported(child))
            }
        }
        document.sections = reader.sections
        // The header / footer references omitted in a later section inherit the previous section's reference.
        for i in document.sections.indices.dropFirst() {
            document.sections[i].headers.merge(document.sections[i - 1].headers) { current, _ in current }
            document.sections[i].footers.merge(document.sections[i - 1].footers) { current, _ in current }
        }
        let kinds: [String: StoryKind] = ["header": .header, "footer": .footer, "footnotes": .footnote, "endnotes": .endnote, "comments": .comment]
        for r in relationships.values.sorted(by: { $0.id < $1.id }) {
            try Task.checkCancellation()
            guard let kind = kinds[r.type], let part = r.path else { continue }
            if !options.includeRelatedStories {
                warnings.add(.storiesOmitted, part: part, element: kind.rawValue, message: "Related stories were omitted by ReadOptions.")
                continue
            }
            let storyReader = StoryReader(package: package, part: part, relationships: try package.relationships(from: part), styles: styles, properties: props, options: options, warnings: warnings, numbering: document.numbering, references: references)
            try storyReader.prepareCharts()
            let root = try XMLTree.parse(package.archive.read(part), part: part, limits: options.limits)
            let expected = [StoryKind.header: "hdr", .footer: "ftr", .footnote: "footnotes", .endnote: "endnotes", .comment: "comments"][kind]!
            guard root.isWord, root.name == expected else { throw DocumentError.invalidXML(part: part, detail: "invalid story root") }
            if kind == .header || kind == .footer {
                if !document.stories.contains(where: { $0.sourcePart == part && $0.kind == kind }) {
                    document.stories.append(Story(id: part, kind: kind, sourcePart: part, blocks: try storyReader.independentStoryBlocks(root.children)))
                }
            } else {
                for n in root.children {
                    try Task.checkCancellation()
                    guard n.isWord, n.name == kind.rawValue, let id = n.attr("id") else { throw DocumentError.invalidXML(part: part, detail: "invalid story ID") }
                    guard !document.stories.contains(where: { $0.kind == kind && $0.id == id }) else { throw DocumentError.corruptedPackage("duplicate story ID") }
                    document.stories.append(Story(id: id, kind: kind, sourcePart: part, blocks: try storyReader.independentStoryBlocks(n.children), author: n.attr("author"), date: n.attr("date"), type: n.attr("type")))
                }
            }
        }
        let knownTypes: Set<String> = ["officeDocument", "core-properties", "extended-properties", "custom-properties", "styles", "numbering", "settings", "fontTable", "font", "theme", "header", "footer", "footnotes", "endnotes", "comments", "image", "hyperlink", "chart"]
        var allRelationships = Array(relationships.values) + Array(try package.relationships(from: "").values)
        let supportingParts = [stylePart, numberingPart, fontPart, themePart, settingsPart].compactMap { $0 }
        for part in Set(document.stories.map(\.sourcePart) + supportingParts).sorted() { allRelationships += Array(try package.relationships(from: part).values) }
        var handled: Set<String> = [package.mainPart, "[Content_Types].xml"]
        for r in allRelationships {
            if let path = r.path { handled.insert(path) }
            if !knownTypes.contains(r.type) {
                warnings.add(.unsupportedPart, part: r.path ?? package.mainPart, element: r.type, message: "Uninterpreted part retained in the package inventory and through asset(at:).")
            }
        }
        for part in package.parts where !handled.contains(part.path) && !part.path.hasSuffix(".rels") {
            warnings.add(.unsupportedPart, part: part.path, element: part.contentType ?? "unknown", message: "Unreferenced part retained in the package inventory.")
        }
        if options.includeRelatedStories {
            let available = Set(document.stories.map { StoryReferences.Key(kind: $0.kind, id: $0.id) })
            for (key, locations) in references.locations.sorted(by: { ($0.key.kind.rawValue, $0.key.id) < ($1.key.kind.rawValue, $1.key.id) }) where !available.contains(key) {
                for (location, count) in locations.sorted(by: { $0.key < $1.key }) {
                    warnings.add(.invalidReference, part: location, element: key.kind.rawValue + "Reference", message: "The referenced note or comment ID is missing.", count: count)
                }
            }
        }
        document.fieldDefinitions = references.fields.definitions
        document.readWarnings = warnings.result
        try Task.checkCancellation()
        return ScanResult(document: document, blocksRead: blocksRead)
    }
}

extension Codec {
    public static let docx = Codec(DOCXCodec())
    public static let docm = Codec(DOCXCodec(macroEnabled: true))
}

enum InlineToken {
    case inline(Inline)
    case begin(MarkupNode)
    case instruction(TextRun)
    case hyperlink(Hyperlink, [InlineToken])
    case control(ContentControlDescriptor, [InlineToken])
    case simple(MarkupNode, [InlineToken])
    case ruby(RubyText, [InlineToken], [InlineToken])
    case drawing(MarkupNode, legacy: Bool, revision: Revision?)
    case separate
    case end
}
final class StoryReferences {
    struct Key: Hashable { let kind: StoryKind; let id: String }
    var locations: [Key: [String: Int]] = [:]
    var charts: [String: Chart] = [:]
    let fields = FieldRegistry()
    func add(_ kind: StoryKind, id: String, part: String) { locations[Key(kind: kind, id: id), default: [:]][part, default: 0] += 1 }
}

final class StoryReader {
    let package: OPCPackage
    let part: String
    let relationships: [String: Relationship]
    let styles: StyleResolver
    let properties: Properties
    let options: ReadOptions
    let warnings: WarningCollector
    let numbering: [String: NumberingDefinition]
    let references: StoryReferences
    var sections: [Section] = []
    var fieldReader = FieldReader()
    var tableContext: ResolvedStyle?
    init(package: OPCPackage, part: String, relationships: [String: Relationship], styles: StyleResolver, properties: Properties, options: ReadOptions, warnings: WarningCollector, numbering: [String: NumberingDefinition], references: StoryReferences) {
        self.package = package; self.part = part; self.relationships = relationships; self.styles = styles
        self.properties = properties; self.options = options; self.warnings = warnings; self.numbering = numbering; self.references = references
    }
    func unsupported(_ n: MarkupNode) -> UnsupportedContent {
        warnings.add(.unsupportedContent, part: part, element: "{\(n.namespace)}\(n.name)", message: "Unsupported content is retained in rawXML or the original part.")
        let leaves = n.descendants("t") + n.descendants("delText")
        return UnsupportedContent(name: n.name, sourcePart: part, rawXML: n.xml, text: leaves.map(\.text).joined())
    }
    func visible(_ name: String) -> Bool {
        switch options.revisions {
        case .all: true
        case .final: name != "del" && name != "moveFrom"
        case .original: name != "ins" && name != "moveTo"
        }
    }
    func blocks(_ nodes: [MarkupNode]) throws -> [Block] {
        var result: [Block] = []
        for n in nodes {
            try Task.checkCancellation()
            if n.isWord {
                switch n.name {
                case "p": result.append(.paragraph(try paragraph(n)))
                case "tbl": result.append(.table(try table(n)))
                case "sdt":
                    result.append(.contentControl(try blockControl(n)))
                case "customXml": _ = unsupported(n); result += try blocks(n.children)
                case "ins", "del", "moveFrom", "moveTo": if visible(n.name) { result += try blocks(n.children) }
                case "sectPr": sections.append(try section(n))
                case "bookmarkStart", "bookmarkEnd", "commentRangeStart", "commentRangeEnd":
                    // Markers outside paragraphs remain visible in the model through an empty paragraph.
                    var p = Paragraph(); p.inlines = try resolve(tokens([n], base: .init(), revision: nil)); result.append(.paragraph(p))
                case "proofErr", "permStart", "permEnd": break
                default: result.append(.unsupported(unsupported(n)))
                }
            } else if n.name == "AlternateContent", n.namespace == "http://schemas.openxmlformats.org/markup-compatibility/2006" {
                result += try blocks(alternate(n))
            } else if isEquation(n) {
                var paragraph = Paragraph()
                paragraph.inlines = [.equation(try equation(n))]
                result.append(.paragraph(paragraph))
            } else { result.append(.unsupported(unsupported(n))) }
        }
        return result
    }
    func alternate(_ n: MarkupNode) -> [MarkupNode] {
        let compatibility = "http://schemas.openxmlformats.org/markup-compatibility/2006"
        for choice in n.children where choice.namespace == compatibility && choice.name == "Choice" {
            let requirements = (choice.attr("Requires") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
            if !requirements.isEmpty && requirements.allSatisfy({ choice.namespaceBindings[$0].map(supportedCompatibilityNamespace) ?? false }) { return choice.children }
        }
        if let fallback = n.children.first(where: { $0.name == "Fallback" && $0.namespace == compatibility }) { return fallback.children }
        warnings.add(.unsupportedContent, part: part, element: "AlternateContent", message: "No compatible fallback is available; the first Choice content was retained.")
        return n.children.first(where: { $0.name == "Choice" && $0.namespace == compatibility })?.children ?? []
    }
    func paragraph(_ n: MarkupNode) throws -> Paragraph {
        let current = n.child("pPr"), history = try formerProperties(current, change: "pPrChange", properties: "pPr"), former = history?.1
        let props = options.revisions == .original ? former ?? current : current
        let styleID = props?.child("pStyle")?.value
        if let styleID, styles.styles[styleID] == nil {
            warnings.add(.invalidReference, part: part, element: "pStyle", message: "The paragraph style is missing; the source ID and content are retained.")
        }
        let base = try styles.paragraph(styleID, table: tableContext)
        var p = Paragraph(); p.styleID = styleID; p.formatting = base.paragraph
        p.defaultTextFormatting = try styles.text(nil, base: base.text, direct: .init())
        if let former, let change = history?.0 {
            var previous = try styles.paragraph(former.child("pStyle")?.value).paragraph
            previous.merge(properties.paragraph(former, part: part))
            p.formattingChange = try ParagraphFormattingChange(revision: readRevision(change, kind: .formatting), previous: previous, source: SourceXMLNode(change))
        }
        if options.revisions == .original, let change = p.formattingChange { p.formatting = change.previous }
        else { p.formatting.merge(properties.paragraph(props, part: part)) }
        try paragraphMark(current?.child("rPr"), base: base.text, paragraph: &p)
        p.list = try properties.list(props, part: part, inheriting: base.list)
        if p.list?.id == "0" { p.list = nil }
        if let list = p.list, numbering[list.id]?.levels[list.level] == nil {
            warnings.add(.invalidReference, part: part, element: "numPr", message: "The numbering definition or level is missing.")
        }
        p.inlines = try resolve(tokens(n.children.filter { !($0.isWord && $0.name == "pPr") }, base: base.text, revision: nil))
        if let s = props?.child("sectPr") { p.sectionBreak = try section(s); sections.append(p.sectionBreak!) }
        return p
    }
    func tokens(_ nodes: [MarkupNode], base: TextFormatting, revision: Revision?) throws -> [InlineToken] {
        var result: [InlineToken] = []
        for n in nodes {
            try Task.checkCancellation()
            if n.isWord {
                switch n.name {
                case "r":
                    let (formatting, change, style) = try textFormatting(n.child("rPr"), base: base)
                    for child in n.children where !(child.isWord && child.name == "rPr") {
                        if child.isWord && ["t", "delText"].contains(child.name) {
                            result.append(.inline(.text(makeRun(child.text, formatting: formatting, styleID: style, revision: revision, change: change))))
                        } else { result += try tokens([child], base: formatting, revision: revision) }
                    }
                case "t", "delText": result.append(.inline(.text(makeRun(n.text, formatting: base, revision: revision))))
                case "sym":
                    guard let font = n.attr("font"), let code = n.attr("char").flatMap({ UInt32($0, radix: 16) }), let scalar = Unicode.Scalar(code) else {
                        throw DocumentError.invalidXML(part: part, detail: "invalid symbol font/character")
                    }
                    var run = TextRun(String(scalar), formatting: base, revision: revision)
                    run.symbol = SymbolCharacter(fontName: font, characterCode: code)
                    result.append(.inline(.text(run)))
                case "ruby":
                    var ruby = RubyText(base: [], annotation: [])
                    let props = n.child("rubyPr")
                    ruby.alignment = props?.child("rubyAlign")?.value
                    ruby.annotationSize = halfPoints(props?.child("hps")?.value)
                    ruby.baseSize = halfPoints(props?.child("hpsBaseText")?.value)
                    ruby.language = props?.child("lid")?.value
                    ruby.rawProperties = props?.children.map(\.xml) ?? []
                    result.append(.ruby(ruby, try tokens(n.child("rubyBase")?.children ?? [], base: base, revision: revision),
                                        try tokens(n.child("rt")?.children ?? [], base: base, revision: revision)))
                case "tab", "ptab":
                    if n.name == "ptab" { _ = unsupported(n) }
                    result.append(.inline(.tab))
                case "br": result.append(.inline(.lineBreak(BreakKind(rawValue: n.attr("type") ?? "line") ?? .line)))
                case "cr": result.append(.inline(.lineBreak(.line)))
                case "noBreakHyphen": result.append(.inline(.text(TextRun("\u{2011}", formatting: base, revision: revision))))
                case "softHyphen": result.append(.inline(.text(TextRun("\u{00AD}", formatting: base, revision: revision))))
                case "hyperlink":
                    var target: String?
                    if let id = n.rel("id") { let r = try relationship(id, expected: "hyperlink"); target = r.isExternal ? r.target : r.path }
                    result.append(.hyperlink(Hyperlink(target: target, anchor: n.attr("anchor"), tooltip: n.attr("tooltip"), inlines: []),
                                             try tokens(n.children, base: base, revision: revision)))
                case "fldSimple":
                    result.append(.simple(n, try tokens(n.children, base: base, revision: revision)))
                case "fldChar":
                    fieldProperties(n)
                    switch n.attr("fldCharType") {
                    case "begin": result.append(.begin(n))
                    case "separate": result.append(.separate)
                    case "end": result.append(.end)
                    default: result.append(.inline(.unsupported(unsupported(n))))
                    }
                case "instrText", "delInstrText": result.append(.instruction(makeRun(n.text, formatting: base, revision: revision)))
                case "drawing": result.append(.drawing(n, legacy: false, revision: revision))
                case "pict": result.append(.drawing(n, legacy: true, revision: revision))
                case "footnoteReference", "endnoteReference":
                    let id = n.attr("id") ?? "", kind: StoryKind = n.name == "footnoteReference" ? .footnote : .endnote
                    references.add(kind, id: id, part: part)
                    result.append(.inline(.noteReference(NoteReference(id: id, kind: kind))))
                case "bookmarkStart", "bookmarkEnd": result.append(.inline(.bookmark(Bookmark(id: n.attr("id") ?? "", name: n.attr("name"), isStart: n.name == "bookmarkStart"))))
                case "commentRangeStart", "commentRangeEnd", "commentReference":
                    let boundary: CommentReference.Boundary = n.name == "commentRangeStart" ? .start : n.name == "commentRangeEnd" ? .end : .reference
                    if boundary == .reference { references.add(.comment, id: n.attr("id") ?? "", part: part) }
                    result.append(.inline(.commentReference(CommentReference(id: n.attr("id") ?? "", boundary: boundary))))
                case "ins", "del", "moveFrom", "moveTo":
                    guard visible(n.name) else { continue }
                    let kind: Revision.Kind = n.name == "ins" ? .insertion : n.name == "del" ? .deletion : n.name == "moveFrom" ? .moveFrom : .moveTo
                    let change = readRevision(n, kind: kind)
                    result += try tokens(n.children, base: base, revision: change)
                case "sdt": result.append(.control(try controlDescriptor(n), try tokens(controlChildren(n), base: base, revision: revision)))
                case "customXml", "smartTag": _ = unsupported(n); result += try tokens(n.children, base: base, revision: revision)
                case "proofErr", "lastRenderedPageBreak", "footnoteRef", "endnoteRef", "annotationRef", "permStart", "permEnd", "separator", "continuationSeparator": break
                case "moveFromRangeStart", "moveFromRangeEnd", "moveToRangeStart", "moveToRangeEnd": _ = unsupported(n)
                default: result.append(.inline(.unsupported(unsupported(n))))
                }
            } else if n.name == "AlternateContent", n.namespace == "http://schemas.openxmlformats.org/markup-compatibility/2006" {
                result += try tokens(alternate(n), base: base, revision: revision)
            } else if isEquation(n) {
                result.append(.inline(.equation(try equation(n))))
            } else { result.append(.inline(.unsupported(unsupported(n)))) }
        }
        return result
    }
    func resolve(_ tokens: [InlineToken]) throws -> [Inline] {
        try fieldReader.resolve(tokens, reader: self)
    }
    func relationship(_ id: String, expected: String) throws -> Relationship {
        guard let r = relationships[id], r.type == expected else { throw DocumentError.invalidRelationship(part: part, detail: "missing / wrong-type \(expected) relationship \(id)") }
        return r
    }
    func images(_ n: MarkupNode) throws -> [InlineToken] {
        let blips = n.descendants("blip", namespaceSuffix: "/drawingml/2006/main") + n.descendants("blip", namespaceSuffix: "/drawingml/main")
        let vml = n.descendants("imagedata", namespaceSuffix: "vml")
        if blips.isEmpty && vml.isEmpty { return [.inline(.unsupported(unsupported(n)))] }
        var result: [InlineToken] = []
        for blip in blips + vml {
            let id = blip.rel("embed") ?? blip.rel("link") ?? blip.rel("id")
            guard let id else { result.append(.inline(.unsupported(unsupported(n)))); continue }
            let r = try relationship(id, expected: "image")
            let extent = n.descendants("extent").first, props = n.descendants("docPr").first
            let image = DocumentImage(assetPath: r.path, externalURL: r.isExternal ? r.target : nil,
                name: props?.attr("name"), alternativeText: props?.attr("descr") ?? props?.attr("title"),
                width: extent?.attr("cx").flatMap(Double.init).map { $0 / 12700 }, height: extent?.attr("cy").flatMap(Double.init).map { $0 / 12700 },
                isFloating: !n.descendants("anchor").isEmpty || !vml.isEmpty, rawXML: n.xml)
            result.append(.inline(.image(image)))
        }
        if !vml.isEmpty || !n.descendants("anchor").isEmpty || !n.descendants("txbxContent").isEmpty {
            warnings.add(.unsupportedContent, part: part, element: "drawingLayout", message: "Floating placement, VML and text-box details are retained in rawXML.")
        }
        for chart in n.descendants("chart") { _ = unsupported(chart) }
        return result
    }
    func table(_ n: MarkupNode) throws -> Table {
        var t = Table()
        (t.formatting, t.formattingChange) = try changedProperties(n.child("tblPr"), change: "tblPrChange", properties: "tblPr") { try properties.tableFormatting($0, part: part) }
        (t.columns, t.columnChange) = try changedProperties(n.child("tblGrid"), change: "tblGridChange", properties: "tblGrid") { try properties.tableColumns($0, part: part) }
        let savedContext = tableContext
        defer { tableContext = savedContext }
        tableContext = nil
        let selectedTableProperties = options.revisions == .original ? n.child("tblPr")?.child("tblPrChange")?.child("tblPr") ?? n.child("tblPr") : n.child("tblPr")
        let tableStyle = try TableStyleContext(node: n, tableProperties: selectedTableProperties, columnCount: t.columns.count, styleID: t.styleID, styles: styles, properties: properties, part: part, options: options)
        var tableFormatting = tableStyle.formatting
        tableFormatting.merge(t.formatting); tableFormatting.rawProperties = t.properties
        t.formatting = tableFormatting
        var rowControls: [ContentControlRange] = []
        func rows(_ nodes: [MarkupNode], baseIndex: Int = 0, inheritedRevisions: [Revision] = []) throws -> [TableRow] {
            var result: [TableRow] = []
            for rowNode in nodes {
                try Task.checkCancellation()
                if rowNode.isWord && rowNode.name == "tr" {
                    var row = TableRow(); let rp = rowNode.child("trPr")
                    if let deletion = rp?.child("del"), !visible(deletion.name) { continue }
                    if let insertion = rp?.child("ins"), !visible(insertion.name) { continue }
                    row.revisions = inheritedRevisions + (rp?.children.filter { $0.isWord && ["ins", "del"].contains($0.name) }.map { readRevision($0, kind: $0.name == "ins" ? .insertion : .deletion) } ?? [])
                    (row.formatting, row.formattingChange) = try changedProperties(rp, change: "trPrChange", properties: "trPr") { try properties.rowFormatting($0, part: part) }
                    if let exceptions = rowNode.child("tblPrEx") {
                        (row.tableOverrides, row.tableOverridesChange) = try changedProperties(exceptions, change: "tblPrExChange", properties: "tblPrEx") { try properties.tableFormatting($0, part: part) }
                    }
                    let rowIndex = baseIndex + result.count
                    var columnIndex = row.omittedLeadingColumns
                    var cellControls: [ContentControlRange] = []
                    func cells(_ nodes: [MarkupNode], baseIndex: Int = 0, inheritedRevisions: [Revision] = []) throws -> [TableCell] {
                        var result: [TableCell] = []
                        for cn in nodes {
                            try Task.checkCancellation()
                            if cn.isWord && cn.name == "tc" {
                                var cell = TableCell(); let cp = cn.child("tcPr")
                                if cp?.child("cellDel") != nil && options.revisions == .final { continue }
                                if cp?.child("cellIns") != nil && options.revisions == .original { continue }
                                cell.revisions = inheritedRevisions + (cp?.children.filter { $0.isWord && ["cellIns", "cellDel"].contains($0.name) }.map { readRevision($0, kind: $0.name == "cellIns" ? .insertion : .deletion) } ?? [])
                                (cell.formatting, cell.formattingChange) = try changedProperties(cp, change: "tcPrChange", properties: "tcPr") { try properties.cellFormatting($0, part: part) }
                                cell.mergeChange = try cellMergeChange(cp?.child("cellMerge"))
                                if let change = cell.mergeChange {
                                    let merged = options.revisions == .original ? change.wasMergedWithPrevious : change.isMergedWithPrevious
                                    if merged { cell.verticalMerge = .continuation }
                                    else if cell.verticalMerge == .continuation { cell.verticalMerge = nil }
                                }
                                let conditional = tableStyle.resolve(row: rowIndex, column: columnIndex, span: cell.columnSpan)
                                var appearance = conditional.cell
                                appearance.mergeAppearance(cell.formatting)
                                var effective = cell.formatting
                                effective.shading = appearance.shading; effective.verticalAlignment = appearance.verticalAlignment
                                effective.preferredWidth = appearance.preferredWidth; effective.borders = appearance.borders; effective.margins = appearance.margins
                                effective.textDirection = appearance.textDirection; effective.noWrap = appearance.noWrap; effective.fitText = appearance.fitText
                                cell.formatting = effective
                                tableContext = conditional.text
                                let (nextColumn, overflow) = columnIndex.addingReportingOverflow(cell.columnSpan)
                                guard !overflow else { throw DocumentError.invalidXML(part: part, detail: "table grid overflow") }; columnIndex = nextColumn
                                cell.blocks = try storyBlocks(cn.children.filter { !($0.isWord && $0.name == "tcPr") }); result.append(cell)
                            } else if cn.isWord && cn.name == "sdt" {
                                let start = baseIndex + result.count, index = cellControls.count
                                cellControls.append(ContentControlRange(range: start..<start, descriptor: try controlDescriptor(cn)))
                                let content = try cells(controlChildren(cn), baseIndex: start, inheritedRevisions: inheritedRevisions)
                                cellControls[index].range = start..<(start + content.count)
                                result += content
                            }
                            else if cn.isWord && ["ins", "del"].contains(cn.name) { if visible(cn.name) { result += try cells(cn.children, baseIndex: baseIndex + result.count, inheritedRevisions: inheritedRevisions + [readRevision(cn, kind: cn.name == "ins" ? .insertion : .deletion)]) } }
                            else if !(cn.isWord && ["trPr", "tblPrEx"].contains(cn.name)) { _ = unsupported(cn) }
                        }
                        return result
                    }
                    row.cells = try cells(rowNode.children); row.cellControls = cellControls; result.append(row)
                } else if rowNode.isWord && rowNode.name == "sdt" {
                    let start = baseIndex + result.count, index = rowControls.count
                    rowControls.append(ContentControlRange(range: start..<start, descriptor: try controlDescriptor(rowNode)))
                    let content = try rows(controlChildren(rowNode), baseIndex: start, inheritedRevisions: inheritedRevisions)
                    rowControls[index].range = start..<(start + content.count)
                    result += content
                }
                else if rowNode.isWord && ["ins", "del"].contains(rowNode.name) { if visible(rowNode.name) { result += try rows(rowNode.children, baseIndex: baseIndex + result.count, inheritedRevisions: inheritedRevisions + [readRevision(rowNode, kind: rowNode.name == "ins" ? .insertion : .deletion)]) } }
                else if !(rowNode.isWord && ["tblPr", "tblGrid"].contains(rowNode.name)) { _ = unsupported(rowNode) }
            }
            return result
        }
        t.rows = try rows(n.children); t.rowControls = rowControls
        return t
    }
}
