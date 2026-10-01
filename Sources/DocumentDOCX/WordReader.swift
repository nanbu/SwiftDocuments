import Foundation
import DocumentCore

/// The read-only OPC / WordprocessingML codec for DOCX or DOCM.
public struct DOCXCodec: DocumentCodec {
    /// The format identifier or source numbering format, according to this type.
    public let format: DocumentFormat
    public init(macroEnabled: Bool = false) { format = macroEnabled ? .docm : .docx }
    public func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult {
        var blocks: [Block] = []
        var result = try scan(data, options: options) { blocks.append($0) }
        result.document.blocks = blocks
        return ReadResult(document: result.document)
    }
    public func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary {
        let package = try OPCPackage(data, limits: limits)
        guard package.format == format else { throw DocumentError.corruptedPackage("codec / MIME mismatch") }
        return DocumentSummary(format: format, metadata: try metadata(in: package), parts: package.parts)
    }
    public func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        let package = try OPCPackage(data, limits: options.limits)
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
        let styles = try loadStyles(path("styles"), package: package, properties: props, warnings: warnings)
        let references = StoryReferences()
        var document = Document()
        document.sourceFormat = format; document.metadata = try metadata(in: package)
        document.packageParts = package.parts; document.styles = styles.styles
        document.numbering = try loadNumbering(path("numbering"), package: package, properties: props)
        document.attach(package.archive)
        if let settings = try path("settings") {
            let root = try XMLTree.parse(package.archive.read(settings), part: settings, limits: options.limits)
            guard root.isWord, root.name == "settings" else { throw DocumentError.invalidXML(part: settings, detail: "expected settings root") }
            for child in root.children { document.settings[child.name] = child.xml }
        }
        let reader = StoryReader(package: package, part: package.mainPart, relationships: relationships, styles: styles, properties: props, options: options, warnings: warnings, numbering: document.numbering, references: references)
        var blocksRead = 0
        try withoutActuallyEscaping(onBlock) { callback in
            let root = try XMLTree.parse(package.archive.read(package.mainPart), part: package.mainPart, limits: options.limits) { node in
                if node.isWord && node.name == "sectPr" { reader.sections.append(try reader.section(node)); return }
                for block in try reader.blocks([node]) { try callback(block); blocksRead += 1 }
            }
            guard root.isWord, root.name == "document", root.wordChildren("body").count == 1 else { throw DocumentError.invalidXML(part: package.mainPart, detail: "expected document / body") }
        }
        document.sections = reader.sections
        // The header / footer references omitted in a later section inherit the previous section's reference.
        for i in document.sections.indices.dropFirst() {
            document.sections[i].headers.merge(document.sections[i - 1].headers) { current, _ in current }
            document.sections[i].footers.merge(document.sections[i - 1].footers) { current, _ in current }
        }
        let kinds: [String: StoryKind] = ["header": .header, "footer": .footer, "footnotes": .footnote, "endnotes": .endnote, "comments": .comment]
        for r in relationships.values.sorted(by: { $0.id < $1.id }) {
            guard let kind = kinds[r.type], let part = r.path else { continue }
            if !options.includeRelatedStories {
                warnings.add(.storiesOmitted, part: part, element: kind.rawValue, message: "ReadOptions により付随本文を省略しました。")
                continue
            }
            let storyReader = StoryReader(package: package, part: part, relationships: try package.relationships(from: part), styles: styles, properties: props, options: options, warnings: warnings, numbering: document.numbering, references: references)
            let root = try XMLTree.parse(package.archive.read(part), part: part, limits: options.limits)
            let expected = [StoryKind.header: "hdr", .footer: "ftr", .footnote: "footnotes", .endnote: "endnotes", .comment: "comments"][kind]!
            guard root.isWord, root.name == expected else { throw DocumentError.invalidXML(part: part, detail: "invalid story root") }
            if kind == .header || kind == .footer {
                if !document.stories.contains(where: { $0.sourcePart == part && $0.kind == kind }) {
                    document.stories.append(Story(id: part, kind: kind, sourcePart: part, blocks: try storyReader.blocks(root.children)))
                }
            } else {
                for n in root.children {
                    guard n.isWord, n.name == kind.rawValue, let id = n.attr("id") else { throw DocumentError.invalidXML(part: part, detail: "invalid story ID") }
                    guard !document.stories.contains(where: { $0.kind == kind && $0.id == id }) else { throw DocumentError.corruptedPackage("duplicate story ID") }
                    document.stories.append(Story(id: id, kind: kind, sourcePart: part, blocks: try storyReader.blocks(n.children), author: n.attr("author"), date: n.attr("date"), type: n.attr("type")))
                }
            }
        }
        let knownTypes: Set<String> = ["officeDocument", "core-properties", "extended-properties", "custom-properties", "styles", "numbering", "settings", "header", "footer", "footnotes", "endnotes", "comments", "image", "hyperlink"]
        var allRelationships = Array(relationships.values) + Array(try package.relationships(from: "").values)
        for part in Set(document.stories.map(\.sourcePart)).sorted() { allRelationships += Array(try package.relationships(from: part).values) }
        var handled: Set<String> = [package.mainPart, "[Content_Types].xml"]
        for r in allRelationships {
            if let path = r.path { handled.insert(path) }
            if !knownTypes.contains(r.type) {
                warnings.add(.unsupportedPart, part: r.path ?? package.mainPart, element: r.type, message: "このパーツは解釈していません。パッケージ目録と asset(at:) で確認できます。")
            }
        }
        for part in package.parts where !handled.contains(part.path) && !part.path.hasSuffix(".rels") {
            warnings.add(.unsupportedPart, part: part.path, element: part.contentType ?? "unknown", message: "未参照パーツを目録に保持しました。")
        }
        if options.includeRelatedStories {
            let available = Set(document.stories.map { StoryReferences.Key(kind: $0.kind, id: $0.id) })
            for (key, locations) in references.locations.sorted(by: { ($0.key.kind.rawValue, $0.key.id) < ($1.key.kind.rawValue, $1.key.id) }) where !available.contains(key) {
                for (location, count) in locations.sorted(by: { $0.key < $1.key }) {
                    warnings.add(.invalidReference, part: location, element: key.kind.rawValue + "Reference", message: "参照先の脚注 / コメント ID がありません。", count: count)
                }
            }
        }
        document.readWarnings = warnings.result
        return ScanResult(document: document, blocksRead: blocksRead)
    }
}

extension Codec {
    public static let docx = Codec(DOCXCodec())
    public static let docm = Codec(DOCXCodec(macroEnabled: true))
}

private enum InlineToken {
    case inline(Inline)
    case begin(Bool)
    case instruction(String)
    case separate
    case end
}
private struct OpenField {
    var instruction = ""
    var result: [Inline] = []
    var separated = false
    var locked = false
}
private final class StoryReferences {
    struct Key: Hashable { let kind: StoryKind; let id: String }
    var locations: [Key: [String: Int]] = [:]
    func add(_ kind: StoryKind, id: String, part: String) { locations[Key(kind: kind, id: id), default: [:]][part, default: 0] += 1 }
}

private final class StoryReader {
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
    init(package: OPCPackage, part: String, relationships: [String: Relationship], styles: StyleResolver, properties: Properties, options: ReadOptions, warnings: WarningCollector, numbering: [String: NumberingDefinition], references: StoryReferences) {
        self.package = package; self.part = part; self.relationships = relationships; self.styles = styles
        self.properties = properties; self.options = options; self.warnings = warnings; self.numbering = numbering; self.references = references
    }
    func unsupported(_ n: MarkupNode) -> UnsupportedContent {
        warnings.add(.unsupportedContent, part: part, element: "{\(n.namespace)}\(n.name)", message: "未対応要素を記録しました。rawXML または元パーツで確認できます。")
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
            if n.isWord {
                switch n.name {
                case "p": result.append(.paragraph(try paragraph(n)))
                case "tbl": result.append(.table(try table(n)))
                case "sdt":
                    _ = unsupported(n)
                    result += try blocks(n.child("sdtContent")?.children ?? [])
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
            } else { result.append(.unsupported(unsupported(n))) }
        }
        return result
    }
    func alternate(_ n: MarkupNode) -> [MarkupNode] {
        // A fallback is guaranteed to be expressed in the base vocabulary; never duplicate Choice and Fallback.
        if let fallback = n.children.first(where: { $0.name == "Fallback" }) { return fallback.children }
        warnings.add(.unsupportedContent, part: part, element: "AlternateContent", message: "Fallback がないため最初の Choice の内容を読みました。")
        return n.children.first(where: { $0.name == "Choice" })?.children ?? []
    }
    func paragraph(_ n: MarkupNode) throws -> Paragraph {
        let props = n.child("pPr"), styleID = props?.child("pStyle")?.value
        let base = try styles.paragraph(styleID)
        var p = Paragraph(); p.styleID = styleID; p.formatting = base.paragraph
        p.formatting.merge(properties.paragraph(props, part: part))
        p.list = properties.list(props, inheriting: base.list)
        if p.list?.id == "0" { p.list = nil }
        if let list = p.list, numbering[list.id]?.levels[list.level] == nil {
            warnings.add(.invalidReference, part: part, element: "numPr", message: "番号付けの定義またはレベルがありません。")
        }
        p.inlines = try resolve(tokens(n.children.filter { !($0.isWord && $0.name == "pPr") }, base: base.text, revision: nil))
        if let s = props?.child("sectPr") { p.sectionBreak = try section(s); sections.append(p.sectionBreak!) }
        return p
    }
    func tokens(_ nodes: [MarkupNode], base: TextFormatting, revision: Revision?) throws -> [InlineToken] {
        var result: [InlineToken] = []
        for n in nodes {
            if n.isWord {
                switch n.name {
                case "r":
                    let props = n.child("rPr"), style = props?.child("rStyle")?.value
                    let formatting = try styles.text(style, base: base, direct: properties.text(props, part: part))
                    for child in n.children where !(child.isWord && child.name == "rPr") {
                        if child.isWord && ["t", "delText"].contains(child.name) {
                            result.append(.inline(.text(TextRun(child.text, formatting: formatting, styleID: style, revision: revision))))
                        } else { result += try tokens([child], base: formatting, revision: revision) }
                    }
                case "t", "delText": result.append(.inline(.text(TextRun(n.text, formatting: base, revision: revision))))
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
                    let inlines = try resolve(tokens(n.children, base: base, revision: revision))
                    result.append(.inline(.hyperlink(Hyperlink(target: target, anchor: n.attr("anchor"), tooltip: n.attr("tooltip"), inlines: inlines))))
                case "fldSimple":
                    result.append(.inline(.field(Field(instruction: n.attr("instr") ?? "", result: try resolve(tokens(n.children, base: base, revision: revision)), isLocked: n.attr("fldLock").map { ["1", "true", "on"].contains($0) } ?? false))))
                case "fldChar":
                    switch n.attr("fldCharType") {
                    case "begin": result.append(.begin(n.attr("fldLock").map { ["1", "true", "on"].contains($0) } ?? false))
                    case "separate": result.append(.separate)
                    case "end": result.append(.end)
                    default: result.append(.inline(.unsupported(unsupported(n))))
                    }
                case "instrText", "delInstrText": result.append(.instruction(n.text))
                case "drawing", "pict": result += try images(n)
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
                    let change = Revision(id: n.attr("id") ?? "", kind: kind, author: n.attr("author"), date: n.attr("date"))
                    result += try tokens(n.children, base: base, revision: change)
                case "sdt": _ = unsupported(n); result += try tokens(n.child("sdtContent")?.children ?? [], base: base, revision: revision)
                case "customXml", "smartTag": _ = unsupported(n); result += try tokens(n.children, base: base, revision: revision)
                case "proofErr", "lastRenderedPageBreak", "footnoteRef", "endnoteRef", "annotationRef", "permStart", "permEnd", "separator", "continuationSeparator": break
                case "moveFromRangeStart", "moveFromRangeEnd", "moveToRangeStart", "moveToRangeEnd": _ = unsupported(n)
                default: result.append(.inline(.unsupported(unsupported(n))))
                }
            } else if n.name == "AlternateContent", n.namespace == "http://schemas.openxmlformats.org/markup-compatibility/2006" {
                result += try tokens(alternate(n), base: base, revision: revision)
            } else { result.append(.inline(.unsupported(unsupported(n)))) }
        }
        return result
    }
    func resolve(_ tokens: [InlineToken]) throws -> [Inline] {
        var output: [Inline] = [], fields: [OpenField] = []
        func append(_ inline: Inline) {
            if !fields.isEmpty { fields[fields.count - 1].result.append(inline) } else { output.append(inline) }
        }
        for token in tokens {
            switch token {
            case .inline(let inline): append(inline)
            case .begin(let locked): fields.append(OpenField(locked: locked))
            case .instruction(let s):
                if !fields.isEmpty { fields[fields.count - 1].instruction += s }
                else { warnings.add(.incompleteField, part: part, element: "instrText", message: "field 開始マーカーのない命令を検出しました。") }
            case .separate:
                if !fields.isEmpty { fields[fields.count - 1].separated = true }
                else { warnings.add(.incompleteField, part: part, element: "fldChar", message: "対応する field 開始がありません。") }
            case .end:
                if let field = fields.popLast() { append(.field(Field(instruction: field.instruction, result: field.result, isLocked: field.locked))) }
                else { warnings.add(.incompleteField, part: part, element: "fldChar", message: "対応する field 開始がありません。") }
            }
        }
        while let field = fields.popLast() {
            warnings.add(.incompleteField, part: part, element: "fldChar", message: "段落をまたぐ field または終端のない field を段落単位で保持しました。")
            append(.field(Field(instruction: field.instruction, result: field.result, isLocked: field.locked)))
        }
        return output
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
            warnings.add(.unsupportedContent, part: part, element: "drawingLayout", message: "浮動配置 / VML / テキストボックスの詳細は rawXML に保持しました。")
        }
        for chart in n.descendants("chart") { _ = unsupported(chart) }
        return result
    }
    func table(_ n: MarkupNode) throws -> Table {
        var t = Table()
        let props = n.child("tblPr")
        t.styleID = props?.child("tblStyle")?.value
        t.properties = props?.children.map(\.xml) ?? []
        t.columnWidths = n.child("tblGrid")?.wordChildren("gridCol").compactMap { points($0.attr("w")) } ?? []
        func rows(_ nodes: [MarkupNode]) throws -> [TableRow] {
            var result: [TableRow] = []
            for rowNode in nodes {
                if rowNode.isWord && rowNode.name == "tr" {
                    var row = TableRow(); let rp = rowNode.child("trPr")
                    if let deletion = rp?.child("del"), !visible(deletion.name) { continue }
                    if let insertion = rp?.child("ins"), !visible(insertion.name) { continue }
                    row.isHeader = rp?.child("tblHeader")?.on ?? false
                    row.height = points(rp?.child("trHeight")?.attr("val")); row.properties = rp?.children.map(\.xml) ?? []
                    func cells(_ nodes: [MarkupNode]) throws -> [TableCell] {
                        var result: [TableCell] = []
                        for cn in nodes {
                            if cn.isWord && cn.name == "tc" {
                                var cell = TableCell(); let cp = cn.child("tcPr")
                                cell.columnSpan = max(1, integer(cp?.child("gridSpan")?.value) ?? 1)
                                if let merge = cp?.child("vMerge") { cell.verticalMerge = merge.value == "restart" ? .restart : .continuation }
                                let width = cp?.child("tcW"); cell.widthUnit = width?.attr("type") ?? "dxa"
                                cell.width = width?.attr("w").flatMap(Double.init).map { cell.widthUnit == "dxa" ? $0 / 20 : $0 }
                                cell.verticalAlignment = cp?.child("vAlign")?.value; cell.shading = cp?.child("shd")?.attr("fill")
                                cell.properties = cp?.children.map(\.xml) ?? []
                                cell.blocks = try blocks(cn.children.filter { !($0.isWord && $0.name == "tcPr") }); result.append(cell)
                            } else if cn.isWord && cn.name == "sdt" { _ = unsupported(cn); result += try cells(cn.child("sdtContent")?.children ?? []) }
                            else if cn.isWord && ["ins", "del"].contains(cn.name) { if visible(cn.name) { result += try cells(cn.children) } }
                            else if cn.name != "trPr" { _ = unsupported(cn) }
                        }
                        return result
                    }
                    row.cells = try cells(rowNode.children); result.append(row)
                } else if rowNode.isWord && rowNode.name == "sdt" { _ = unsupported(rowNode); result += try rows(rowNode.child("sdtContent")?.children ?? []) }
                else if rowNode.isWord && ["ins", "del"].contains(rowNode.name) { if visible(rowNode.name) { result += try rows(rowNode.children) } }
                else if !["tblPr", "tblGrid"].contains(rowNode.name) { _ = unsupported(rowNode) }
            }
            return result
        }
        t.rows = try rows(n.children)
        if let props {
            for child in props.children where !["tblStyle", "tblW", "jc", "tblBorders", "shd", "tblCellMar", "tblLayout", "tblLook", "tblInd", "tblCaption", "tblDescription"].contains(child.name) { properties.unparsed(child, part: part) }
        }
        return t
    }
    func section(_ n: MarkupNode) throws -> Section {
        var s = Section(); s.rawProperties = n.children.map(\.xml)
        s.pageWidth = points(n.child("pgSz")?.attr("w")); s.pageHeight = points(n.child("pgSz")?.attr("h")); s.orientation = n.child("pgSz")?.attr("orient").flatMap(PageOrientation.init(rawValue:))
        if let margins = n.child("pgMar") {
            for key in ["top", "right", "bottom", "left", "header", "footer", "gutter"] { if let value = points(margins.attr(key)) { s.margins[key] = value } }
        }
        s.columnCount = integer(n.child("cols")?.attr("num")) ?? 1
        s.breakKind = n.child("type")?.value; s.hasDifferentFirstPage = n.child("titlePg")?.on ?? false
        for child in n.children {
            if child.isWord && ["headerReference", "footerReference"].contains(child.name), let id = child.rel("id") {
                let header = child.name == "headerReference", r = try relationship(id, expected: header ? "header" : "footer")
                guard let path = r.path else { throw DocumentError.invalidRelationship(part: part, detail: "external header / footer") }
                if header { s.headers[child.attr("type") ?? "default"] = path } else { s.footers[child.attr("type") ?? "default"] = path }
            } else if !["pgSz", "pgMar", "cols", "type", "titlePg"].contains(child.name) { properties.unparsed(child, part: part) }
        }
        return s
    }
}
