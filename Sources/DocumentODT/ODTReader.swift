import Foundation
import DocumentCore

/// Reads the documented ODF text subset without launching a producer application.
public struct ODTCodec: DocumentCodec {
    public let format = DocumentFormat.odt
    public init() {}
    public func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult {
        var blocks: [Block] = []
        var result = try scan(data, options: options) { blocks.append($0) }
        result.document.blocks = blocks
        return ReadResult(document: result.document)
    }
    public func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary {
        let reader = try ODFReader(data, options: ReadOptions(limits: limits))
        return DocumentSummary(format: .odt, metadata: try reader.metadata(), parts: reader.parts)
    }
    public func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        let reader = try ODFReader(data, options: options)
        return try reader.scan(onBlock)
    }
}
extension Codec { public static let odt = Codec(ODTCodec()) }

private enum ODF {
    static let office = "urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    static let text = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
    static let style = "urn:oasis:names:tc:opendocument:xmlns:style:1.0"
    static let table = "urn:oasis:names:tc:opendocument:xmlns:table:1.0"
    static let draw = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
    static let fo = "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
    static let svg = "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
    static let manifest = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
    static let meta = "urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
    static let link = "http://www.w3.org/1999/xlink"
}
private extension MarkupNode {
    func odf(_ namespace: String, _ name: String) -> MarkupNode? { children.first { $0.namespace == namespace && $0.name == name } }
    func attribute(_ namespace: String, _ name: String) -> String? { attributes[namespace + "|" + name] }
}
private struct ODFStyle {
    var value: DocumentStyle
    var cell = TableCellFormatting()
    var table = TableFormatting()
    var row = TableRowFormatting()
    var column = TableColumn()
    var rubyAlignment: String?
    var rubyPosition: String?
}
private final class ODFReader {
    let archive: PackageArchive
    let options: ReadOptions
    let warnings = WarningCollector()
    var mediaTypes: [String: String] = [:]
    var styles: [String: ODFStyle] = [:]
    var styleParts: [String: String] = [:]
    var defaults: [String: ODFStyle] = [:]
    var resolved: [String: ODFStyle] = [:]
    var declarationCache: [String: ODFStyle] = [:]
    var cellContext: ODFStyle?
    var stories: [Story] = []
    var nonBody: [UnsupportedContent] = []
    var numbering: [String: NumberingDefinition] = [:]
    var remaining: Int
    var fonts: [String: String] = [:]
    // Keep source nodes alive so repeated model expansion counts each source diagnostic once.
    var warnedNodes: [ObjectIdentifier: MarkupNode] = [:]
    init(_ data: Data, options: ReadOptions) throws {
        self.options = options; remaining = options.limits.maxXMLNodes
        archive = try PackageArchive(data, limits: options.limits)
        guard String(data: try archive.read("mimetype"), encoding: .utf8) == "application/vnd.oasis.opendocument.text" else { throw DocumentError.corruptedPackage("codec / MIME mismatch") }
        if archive.entries["META-INF/manifest.xml"] != nil {
            let root = try xml("META-INF/manifest.xml")
            guard root.namespace == ODF.manifest, root.name == "manifest" else { throw DocumentError.invalidXML(part: "META-INF/manifest.xml", detail: "invalid ODF manifest") }
            extensions(root, part: "META-INF/manifest.xml", attributes: [(ODF.manifest, ["version"])])
            for node in root.children {
                guard node.namespace == ODF.manifest, node.name == "file-entry" else { warn(node, part: "META-INF/manifest.xml"); continue }
                if node.odf(ODF.manifest, "encryption-data") != nil { throw DocumentError.unsupportedContainer("encrypted ODF") }
                extensions(node, part: "META-INF/manifest.xml", attributes: [(ODF.manifest, ["full-path", "media-type", "version"])], children: [])
                if let path = node.attribute(ODF.manifest, "full-path"), let type = node.attribute(ODF.manifest, "media-type") {
                    guard mediaTypes[path] == nil else { throw DocumentError.corruptedPackage("duplicate ODF manifest entry") }
                    mediaTypes[path] = type
                }
            }
        }
    }
    var parts: [PackagePart] {
        archive.paths.filter { !$0.hasSuffix("/") }.map {
            let entry = archive.entries[$0]!
            return PackagePart(path: $0, contentType: mediaTypes[$0], compressedSize: entry.compressedSize, expandedSize: entry.expandedSize)
        }
    }
    func xml(_ part: String) throws -> MarkupNode { try XMLTree.parse(archive.read(part), part: part, limits: options.limits) }
    func charge(_ amount: Int = 1) throws {
        try Task.checkCancellation()
        guard amount >= 0, amount <= remaining else { throw DocumentError.limitExceeded("ODF expanded model nodes") }; remaining -= amount
    }
    func count(_ node: MarkupNode, namespace: String, name: String) throws -> Int {
        guard let raw = node.attribute(namespace, name) else { return 1 }
        guard let n = Int(raw), n > 0, n <= options.limits.maxXMLNodes else { throw DocumentError.invalidXML(part: "content.xml", detail: "invalid ODF repetition / span") }
        return n
    }
    func diagnose(_ node: MarkupNode, part: String, formatting: Bool = false) {
        if warnedNodes.updateValue(node, forKey: ObjectIdentifier(node)) == nil {
            warnings.add(formatting ? .uninterpretedFormatting : .unsupportedContent, part: part, element: "{\(node.namespace)}\(node.name)", message: "Uninterpreted ODF data retained in source XML and original parts.")
        }
    }
    @discardableResult func warn(_ node: MarkupNode, part: String, formatting: Bool = false) -> UnsupportedContent {
        diagnose(node, part: part, formatting: formatting)
        return UnsupportedContent(name: "{\(node.namespace)}\(node.name)", sourcePart: part, rawXML: node.xml)
    }
    func extensions(_ node: MarkupNode, part: String, attributes: [(String, [String])] = [], children: [(String, [String])]? = nil, text: Bool = false, formatting: Bool = false) {
        let allowed = Set(attributes.flatMap { namespace, names in names.map { namespace + "|" + $0 } })
        let hasText = node.content.contains { if case .text(let value) = $0 { return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; return false }
        if node.attributes.keys.contains(where: { !allowed.contains($0) }) || (!text && hasText) { diagnose(node, part: part, formatting: formatting) }
        if let children {
            let allowedChildren = Set(children.flatMap { namespace, names in names.map { namespace + "|" + $0 } })
            for child in node.children where !allowedChildren.contains(child.namespace + "|" + child.name) { diagnose(child, part: part, formatting: formatting) }
        }
    }
    func metadata() throws -> DocumentMetadata {
        var result = DocumentMetadata()
        guard archive.entries["meta.xml"] != nil else { return result }
        let root = try xml("meta.xml")
        guard root.namespace == ODF.office, root.name == "document-meta", let meta = root.odf(ODF.office, "meta") else { throw DocumentError.invalidXML(part: "meta.xml", detail: "invalid ODF metadata") }
        extensions(root, part: "meta.xml", attributes: [(ODF.office, ["version"])], children: [(ODF.office, ["meta"])])
        extensions(meta, part: "meta.xml")
        for node in meta.children {
            let attributes: [(String, [String])]
            if node.namespace == ODF.meta, node.name == "user-defined" { attributes = [(ODF.meta, ["name"])] }
            else if node.namespace == ODF.meta, node.name == "document-statistic" { attributes = [(ODF.meta, ["page-count", "word-count"])] }
            else { attributes = [] }
            extensions(node, part: "meta.xml", attributes: attributes, children: [], text: true)
            switch (node.namespace, node.name) {
            case ("http://purl.org/dc/elements/1.1/", "title"): result.title = node.text
            case ("http://purl.org/dc/elements/1.1/", "subject"): result.subject = node.text
            case ("http://purl.org/dc/elements/1.1/", "creator"): result.creator = node.text
            case ("http://purl.org/dc/elements/1.1/", "description"): result.description = node.text
            case ("http://purl.org/dc/elements/1.1/", "date"): result.modified = node.text
            case (ODF.meta, "initial-creator"): result.creator = result.creator ?? node.text
            case (ODF.meta, "creation-date"): result.created = node.text
            case (ODF.meta, "generator"): result.application = node.text
            case (ODF.meta, "keyword"): result.keywords = [result.keywords, node.text].compactMap { $0 }.joined(separator: ", ")
            case (ODF.meta, "user-defined"): if let name = node.attribute(ODF.meta, "name") { result.custom[name] = node.text }
            case (ODF.meta, "document-statistic"):
                result.declaredPages = node.attribute(ODF.meta, "page-count").flatMap(Int.init)
                result.declaredWords = node.attribute(ODF.meta, "word-count").flatMap(Int.init)
                for name in ["page-count", "word-count"] {
                    if let raw = node.attribute(ODF.meta, name), Int(raw).map({ $0 >= 0 }) != true { diagnose(node, part: "meta.xml") }
                }
                if result.declaredPages.map({ $0 < 0 }) == true { result.declaredPages = nil }
                if result.declaredWords.map({ $0 < 0 }) == true { result.declaredWords = nil }
            default: warn(node, part: "meta.xml")
            }
        }
        return result
    }
    func length(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let factors = ["pt": 1.0, "in": 72.0, "cm": 72 / 2.54, "mm": 72 / 25.4, "pc": 12.0]
        for (suffix, factor) in factors where raw.hasSuffix(suffix) {
            if let value = Double(raw.dropLast(suffix.count)), value.isFinite, (value * factor).isFinite { return value * factor }
        }
        return nil
    }
    func border(_ raw: String) -> TableBorder? {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let styles: Set<String> = ["none", "hidden", "solid", "dotted", "dashed", "double", "groove", "ridge", "inset", "outset"]
        guard let style = tokens.first(where: { styles.contains($0) }) else { return nil }
        var result = TableBorder(style: style), seenStyle = false
        for token in tokens {
            if styles.contains(token) { if seenStyle { return nil }; seenStyle = true }
            else if token.hasPrefix("#"), token.count == 7, UInt32(token.dropFirst(), radix: 16) != nil {
                guard result.color == nil else { return nil }; result.color = String(token.dropFirst()).uppercased()
            } else if let width = length(token), width >= 0 {
                guard result.width == nil else { return nil }; result.width = width; result.sourceWidth = token
            } else { return nil }
        }
        return result
    }
    func readStyle(_ node: MarkupNode, part: String, family: String, id: String) -> ODFStyle {
        var result = ODFStyle(value: DocumentStyle(id: id, name: node.attribute(ODF.style, "display-name") ?? id, kind: family, basedOn: node.attribute(ODF.style, "parent-style-name")))
        for props in node.children {
            var known: Set<String> = [], invalid = false
            func get(_ ns: String, _ name: String) -> String? { known.insert(ns + "|" + name); return props.attribute(ns, name) }
            func measure(_ ns: String, _ name: String) -> Double? {
                guard let raw = get(ns, name) else { return nil }
                let value = length(raw)
                if value == nil { invalid = true }
                return value
            }
            if props.namespace == ODF.style && props.name == "text-properties" {
                var f = TextFormatting()
                if let weight = get(ODF.fo, "font-weight") {
                    if ["normal", "bold"].contains(weight) || Int(weight).map({ (100...900).contains($0) }) == true { f.bold = weight == "bold" || (Int(weight) ?? 0) >= 600 }
                    else { invalid = true }
                }
                if let value = get(ODF.fo, "font-style") {
                    if ["normal", "italic", "oblique"].contains(value) { f.italic = value != "normal" } else { invalid = true }
                }
                let family = get(ODF.fo, "font-family"), sourceFont = get(ODF.style, "font-name")
                f.fontName = family?.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) ?? sourceFont.map { fonts[$0] ?? $0 }
                f.fontNameEastAsia = get(ODF.style, "font-name-asian").map { fonts[$0] ?? $0 }; f.fontNameComplexScript = get(ODF.style, "font-name-complex").map { fonts[$0] ?? $0 }
                f.fontSize = measure(ODF.fo, "font-size"); f.fontSizeComplexScript = measure(ODF.style, "font-size-complex")
                f.color = get(ODF.fo, "color")?.replacingOccurrences(of: "#", with: "")
                f.language = get(ODF.fo, "language"); f.languageEastAsia = get(ODF.style, "language-asian")
                if let value = get(ODF.style, "text-underline-style") {
                    if ["none", "solid"].contains(value) { f.underline = value == "none" ? "none" : "single" } else { invalid = true }
                }
                if let value = get(ODF.style, "text-line-through-style") {
                    if ["none", "solid"].contains(value) { f.strike = value != "none" } else { invalid = true }
                }
                f.characterSpacing = measure(ODF.fo, "letter-spacing")
                result.value.text = f
            } else if props.namespace == ODF.style && props.name == "paragraph-properties" {
                var f = ParagraphFormatting()
                if let value = get(ODF.fo, "text-align") {
                    f.alignment = ["start": .start, "end": .end, "left": .left, "right": .right, "center": .center, "justify": .justified][value]
                    if f.alignment == nil { invalid = true }
                }
                f.spacingBefore = measure(ODF.fo, "margin-top"); f.spacingAfter = measure(ODF.fo, "margin-bottom")
                f.indentLeft = measure(ODF.fo, "margin-left"); f.indentRight = measure(ODF.fo, "margin-right"); f.firstLineIndent = measure(ODF.fo, "text-indent")
                if let value = get(ODF.fo, "break-before") {
                    if ["auto", "page"].contains(value) { f.pageBreakBefore = value == "page" } else { invalid = true }
                }
                if let value = get(ODF.fo, "keep-with-next") {
                    if ["auto", "always"].contains(value) { f.keepWithNext = value == "always" } else { invalid = true }
                }
                if let value = get(ODF.fo, "line-height") {
                    if value.hasSuffix("%"), let number = Double(value.dropLast()), number.isFinite { f.lineSpacing = number / 100; f.lineSpacingRule = .multiple }
                    else if let amount = length(value) { f.lineSpacing = amount; f.lineSpacingRule = .exact }
                    else { invalid = true }
                }
                if let tabs = props.odf(ODF.style, "tab-stops") {
                    f.tabs = []; f.rawProperties.append(tabs.xml)
                    extensions(tabs, part: part, formatting: true)
                    for tab in tabs.children {
                        guard tab.namespace == ODF.style, tab.name == "tab-stop" else { diagnose(tab, part: part, formatting: true); continue }
                        extensions(tab, part: part, attributes: [(ODF.style, ["position", "type", "char", "leader-text", "leader-type", "leader-style"])], children: [], formatting: true)
                        let type = tab.attribute(ODF.style, "type") ?? "left"
                        let alignment = ["left": "left", "center": "center", "right": "right", "char": "decimal"][type]
                        guard let position = length(tab.attribute(ODF.style, "position")), let alignment else { diagnose(tab, part: part, formatting: true); continue }
                        f.tabs?.append(TabStop(position: position, alignment: alignment, leader: tab.attribute(ODF.style, "leader-text")))
                        // Custom decimal characters and patterned leaders need a layout policy.
                        if tab.attribute(ODF.style, "char") != nil || tab.attribute(ODF.style, "leader-style") != nil || tab.attribute(ODF.style, "leader-type") != nil { diagnose(tab, part: part, formatting: true) }
                    }
                }
                result.value.paragraph = f
            } else if props.namespace == ODF.style && props.name == "ruby-properties" {
                if let alignment = get(ODF.style, "ruby-align") {
                    if ["left", "center", "right", "distribute-letter", "distribute-space"].contains(alignment) { result.rubyAlignment = alignment } else { invalid = true }
                }
                if let position = get(ODF.style, "ruby-position") {
                    if ["above", "below", "inter-character"].contains(position) { result.rubyPosition = position } else { invalid = true }
                }
            } else if props.namespace == ODF.style && props.name == "table-cell-properties" {
                result.cell.shading = get(ODF.fo, "background-color")?.replacingOccurrences(of: "#", with: "")
                if let value = get(ODF.style, "vertical-align") {
                    if ["top", "middle", "bottom", "automatic"].contains(value) { result.cell.verticalAlignment = value } else { invalid = true }
                }
                if let raw = get(ODF.fo, "border") {
                    if let value = border(raw) { for edge: TableBorderEdge in [.top, .bottom, .left, .right] { result.cell.borders[edge] = value } }
                    else { invalid = true }
                }
                if let padding = measure(ODF.fo, "padding") {
                    if padding >= 0 { for edge: TableCellEdge in [.top, .bottom, .left, .right] { result.cell.margins[edge] = TableWidth(value: padding, sourceValue: props.attribute(ODF.fo, "padding")) } }
                    else { invalid = true }
                }
                for edge: TableCellEdge in [.top, .bottom, .left, .right] {
                    if let padding = measure(ODF.fo, "padding-" + edge.rawValue) {
                        if padding >= 0 { result.cell.margins[edge] = TableWidth(value: padding, sourceValue: props.attribute(ODF.fo, "padding-" + edge.rawValue)) }
                        else { invalid = true }
                    }
                    if let raw = get(ODF.fo, "border-" + edge.rawValue) {
                        if let value = border(raw) { result.cell.borders[TableBorderEdge(rawValue: edge.rawValue)!] = value } else { invalid = true }
                    }
                }
                if let raw = get(ODF.fo, "wrap-option") {
                    if ["wrap", "no-wrap"].contains(raw) { result.cell.noWrap = raw == "no-wrap" } else { invalid = true }
                }
            } else if props.namespace == ODF.style && props.name == "table-properties" {
                if let width = measure(ODF.style, "width") {
                    if width >= 0 { result.table.preferredWidth = TableWidth(value: width, unit: .points, sourceValue: props.attribute(ODF.style, "width")) } else { invalid = true }
                }
                if let raw = get(ODF.style, "rel-width") {
                    if raw.hasSuffix("%"), let width = Double(raw.dropLast()), width.isFinite, width >= 0 { result.table.preferredWidth = TableWidth(value: width, unit: .percent, sourceValue: raw) }
                    else { invalid = true }
                }
                if let raw = get(ODF.table, "align") {
                    result.table.alignment = TableAlignment(rawValue: raw)
                    if result.table.alignment == nil { invalid = true }
                }
                result.table.shading = get(ODF.fo, "background-color")?.replacingOccurrences(of: "#", with: "")
            } else if props.namespace == ODF.style && props.name == "table-column-properties" {
                if let width = measure(ODF.style, "column-width") {
                    if width >= 0 { result.column.width = width; result.column.sourceWidth = props.attribute(ODF.style, "column-width") } else { invalid = true }
                }
            } else if props.namespace == ODF.style && props.name == "table-row-properties" {
                if let height = measure(ODF.style, "min-row-height") {
                    if height >= 0 { result.row.height = height; result.row.heightRule = .minimum } else { invalid = true }
                }
                if let height = measure(ODF.style, "row-height") {
                    if height >= 0 { result.row.height = height; result.row.heightRule = .exact } else { invalid = true }
                }
                if let raw = get(ODF.fo, "keep-together") {
                    if ["auto", "always"].contains(raw) { result.row.preventSplit = raw == "always" } else { invalid = true }
                }
            } else { warn(props, part: part, formatting: true); continue }
            let hasText = props.content.contains { if case .text(let value) = $0 { return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; return false }
            let extraChildren = props.children.contains { !(props.namespace == ODF.style && props.name == "paragraph-properties" && $0.namespace == ODF.style && $0.name == "tab-stops") }
            if invalid || props.attributes.keys.contains(where: { !known.contains($0) }) || extraChildren || hasText {
                warn(props, part: part, formatting: true)
                result.value.text.rawProperties.append(props.xml); result.value.paragraph.rawProperties.append(props.xml)
                result.cell.rawProperties.append(props.xml); result.table.rawProperties.append(props.xml)
                result.row.rawProperties.append(props.xml); result.column.rawProperties.append(props.xml)
            }
        }
        let allowed = Set(["name", "display-name", "family", "parent-style-name"].map { ODF.style + "|" + $0 })
        if node.attributes.keys.contains(where: { !allowed.contains($0) }) { warn(node, part: part, formatting: true) }
        extensions(node, part: part, attributes: [(ODF.style, ["name", "display-name", "family", "parent-style-name"])], formatting: true)
        if ["table", "table-cell", "table-row"].contains(family) {
            var rule = TableStyleRule(region: .wholeTable)
            rule.cell = result.cell; rule.row = result.row; rule.table = result.table
            result.value.tableRules = [rule]
        }
        return result
    }
    func loadStyles(_ root: MarkupNode, part: String) throws {
        if let declarations = root.odf(ODF.office, "font-face-decls") {
            extensions(declarations, part: part, formatting: true)
            for face in declarations.children {
                if face.namespace == ODF.style, face.name == "font-face", let name = face.attribute(ODF.style, "name"), let family = face.attribute(ODF.svg, "font-family") {
                    fonts[name] = family.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    extensions(face, part: part, attributes: [(ODF.style, ["name"]), (ODF.svg, ["font-family"])], children: [], formatting: true)
                    if !face.children.isEmpty { warn(face, part: part, formatting: true) }
                } else { warn(face, part: part, formatting: true) }
            }
        }
        for container in root.children where container.namespace == ODF.office && ["styles", "automatic-styles"].contains(container.name) {
            extensions(container, part: part, formatting: true)
            for node in container.children {
                try charge()
                if node.namespace == ODF.style && ["style", "default-style"].contains(node.name), let family = node.attribute(ODF.style, "family") {
                    let name = node.attribute(ODF.style, "name") ?? ""
                    let key = family + ":" + (container.name == "automatic-styles" ? part + ":" : "") + name
                    let value = readStyle(node, part: part, family: family, id: key)
                    if node.name == "default-style" { defaults[family] = value }
                    else {
                        guard !name.isEmpty, styles[key] == nil else { throw DocumentError.invalidXML(part: part, detail: "missing / duplicate ODF style") }
                        styles[key] = value
                        styleParts[key] = part
                    }
                } else if node.namespace == ODF.text && node.name == "list-style", let id = node.attribute(ODF.style, "name") {
                    extensions(node, part: part, attributes: [(ODF.style, ["name"])], formatting: true)
                    var levels: [Int: NumberingLevel] = [:]
                    for level in node.children {
                        guard level.namespace == ODF.text, ["list-level-style-number", "list-level-style-bullet"].contains(level.name) else { warn(level, part: part); continue }
                        guard let raw = level.attribute(ODF.text, "level"), let index = Int(raw), index > 0, levels[index - 1] == nil else { throw DocumentError.invalidXML(part: part, detail: "invalid / duplicate ODF list level") }
                        guard index <= options.limits.maxXMLDepth else { throw DocumentError.limitExceeded("ODF list level depth") }
                        let start: Int
                        if let raw = level.attribute(ODF.text, "start-value") {
                            guard let value = Int(raw), value > 0 else { throw DocumentError.invalidXML(part: part, detail: "invalid ODF list start") }
                            start = value
                        } else { start = 1 }
                        let format = level.attribute(ODF.style, "num-format") ?? "bullet"
                        let marker = level.attribute(ODF.text, "bullet-char") ?? "%\(index)."
                        levels[index - 1] = NumberingLevel(level: index - 1, start: start, format: format, text: marker)
                        extensions(level, part: part, attributes: [(ODF.text, ["level", "start-value", "bullet-char"]), (ODF.style, ["num-format"])], children: [], formatting: true)
                        if !level.children.isEmpty { warn(level, part: part, formatting: true) }
                    }
                    numbering[id] = NumberingDefinition(id: id, abstractID: id, levels: levels)
                } else { warn(node, part: part, formatting: true) }
            }
        }
    }
    func style(_ name: String?, family: String, part: String) throws -> ODFStyle {
        guard let name else { return defaults[family] ?? ODFStyle(value: DocumentStyle(id: "", name: "", kind: family)) }
        let scoped = family + ":" + part + ":" + name
        return try resolveStyle(styles[scoped] != nil ? scoped : family + ":" + name, family: family, part: part)
    }
    func resolveStyle(_ key: String, family: String, part: String, seen: Set<String> = []) throws -> ODFStyle {
        if let cached = resolved[key] { return cached }
        try Task.checkCancellation()
        guard seen.count < 128 else { throw DocumentError.limitExceeded("ODF style depth") }
        guard !seen.contains(key) else { throw DocumentError.corruptedPackage("ODF style inheritance cycle") }
        var result = defaults[family] ?? ODFStyle(value: DocumentStyle(id: "", name: "", kind: family))
        guard let value = styles[key] else {
            warnings.add(.invalidReference, part: part, element: "style-name", message: "Missing ODF style reference retained.")
            result.value.id = key
            return result
        }
        if let parent = value.value.basedOn { result = try resolveStyle(family + ":" + parent, family: family, part: styleParts[key] ?? part, seen: seen.union([key])) }
        result.value.text.merge(value.value.text); result.value.paragraph.merge(value.value.paragraph)
        result.value.id = value.value.id; result.value.name = value.value.name
        result.cell.mergeAppearance(value.cell); result.table.merge(value.table)
        result.cell.rawProperties += value.cell.rawProperties; result.table.rawProperties += value.table.rawProperties
        if let height = value.row.height { result.row.height = height; result.row.heightRule = value.row.heightRule }
        result.row.preventSplit = value.row.preventSplit ?? result.row.preventSplit
        result.row.rawProperties += value.row.rawProperties
        if value.column.width != nil { result.column.width = value.column.width; result.column.sourceWidth = value.column.sourceWidth }
        result.column.rawProperties += value.column.rawProperties
        result.rubyAlignment = value.rubyAlignment ?? result.rubyAlignment; result.rubyPosition = value.rubyPosition ?? result.rubyPosition
        resolved[key] = result
        return result
    }
    // Resolve only explicit declarations here. Family defaults sit below column,
    // row and cell styles and must not overwrite a nearer fallback implicitly.
    func styleDeclarations(_ name: String?, family: String, part: String) throws -> ODFStyle {
        guard let name else { return ODFStyle(value: DocumentStyle(id: "", name: "", kind: family)) }
        let resolved = try style(name, family: family, part: part)
        let scoped = family + ":" + part + ":" + name
        let key = styles[scoped] != nil ? scoped : family + ":" + name
        if let cached = declarationCache[key] { return cached }
        var chain: [ODFStyle] = [], cursor: String? = key
        while let key = cursor, let value = styles[key] {
            try Task.checkCancellation()
            chain.append(value); cursor = value.value.basedOn.map { family + ":" + $0 }
        }
        var result = ODFStyle(value: DocumentStyle(id: resolved.value.id, name: resolved.value.name, kind: family))
        for declaration in chain.reversed() {
            result.cell.mergeAppearance(declaration.cell); result.cell.rawProperties += declaration.cell.rawProperties
            result.value.text.merge(declaration.value.text); result.value.paragraph.merge(declaration.value.paragraph)
        }
        if styles[key] != nil { declarationCache[key] = result }; return result
    }
    func scan(_ callback: (Block) throws -> Void) throws -> ScanResult {
        var document = Document(); document.sourceFormat = .odt; document.packageParts = parts
        document.metadata = try metadata(); document.attach(archive, limits: options.limits)
        var styleRoot: MarkupNode?
        if archive.entries["styles.xml"] != nil {
            let root = try xml("styles.xml")
            guard root.namespace == ODF.office, root.name == "document-styles" else { throw DocumentError.invalidXML(part: "styles.xml", detail: "invalid ODF styles root") }
            styleRoot = root; try loadStyles(root, part: "styles.xml")
            extensions(root, part: "styles.xml", attributes: [(ODF.office, ["version"])])
        }
        if let styleRoot {
            for child in styleRoot.children where child.namespace != ODF.office || !["styles", "automatic-styles", "font-face-decls", "master-styles"].contains(child.name) { document.uninterpretedContent.append(warn(child, part: "styles.xml")) }
        }
        let root = try xml("content.xml")
        guard root.namespace == ODF.office, root.name == "document-content", root.children.filter({ $0.namespace == ODF.office && $0.name == "body" }).count == 1, let body = root.odf(ODF.office, "body"), body.children.filter({ $0.namespace == ODF.office && $0.name == "text" }).count == 1, let text = body.odf(ODF.office, "text") else { throw DocumentError.invalidXML(part: "content.xml", detail: "expected ODF text body") }
        try loadStyles(root, part: "content.xml")
        extensions(root, part: "content.xml", attributes: [(ODF.office, ["version"])])
        extensions(body, part: "content.xml", children: [(ODF.office, ["text"])])
        extensions(text, part: "content.xml")
        for key in styles.keys.sorted() { _ = try resolveStyle(key, family: styles[key]!.value.kind, part: styleParts[key]!) }
        var count = 0
        for node in text.children {
            for block in try blocks([node], part: "content.xml") {
                try Task.checkCancellation(); try callback(block); try Task.checkCancellation(); count += 1
            }
        }
        if let master = styleRoot?.odf(ODF.office, "master-styles") {
            extensions(master, part: "styles.xml")
            for page in master.children {
                guard page.namespace == ODF.style, page.name == "master-page" else { diagnose(page, part: "styles.xml"); continue }
                extensions(page, part: "styles.xml", attributes: [(ODF.style, ["name"])])
                for node in page.children {
                    if node.namespace == ODF.style && ["header", "footer", "header-left", "footer-left", "header-first", "footer-first"].contains(node.name) {
                        extensions(node, part: "styles.xml")
                        let kind: StoryKind = node.name.hasPrefix("header") ? .header : .footer
                        if options.includeRelatedStories { stories.append(Story(id: (page.attribute(ODF.style, "name") ?? "") + ":" + node.name, kind: kind, sourcePart: "styles.xml", blocks: try blocks(node.children, part: "styles.xml"))) }
                        else { warnings.add(.storiesOmitted, part: "styles.xml", element: node.name, message: "Related stories omitted by ReadOptions.") }
                    } else { warn(node, part: "styles.xml") }
                }
            }
        }
        for node in root.children where node.namespace != ODF.office || !["body", "automatic-styles", "font-face-decls"].contains(node.name) { document.uninterpretedContent.append(warn(node, part: "content.xml")) }
        document.uninterpretedContent += nonBody
        document.fonts = Array(Set(fonts.values)).sorted().map { DocumentFont(name: $0) }; document.styles = styles.mapValues(\.value); document.numbering = numbering; document.stories = stories; document.readWarnings = warnings.result
        return ScanResult(document: document, blocksRead: count)
    }
    func blocks(_ nodes: [MarkupNode], part: String, list: ListReference? = nil) throws -> [Block] {
        var result: [Block] = []
        for node in nodes {
            try charge()
            if node.namespace == ODF.text && ["p", "h"].contains(node.name) {
                extensions(node, part: part, attributes: [(ODF.text, node.name == "h" ? ["style-name", "outline-level"] : ["style-name"])], text: true)
                let name = node.attribute(ODF.text, "style-name")
                var value: ODFStyle
                if let cellContext {
                    value = defaults["paragraph"] ?? ODFStyle(value: DocumentStyle(id: "", name: "", kind: "paragraph"))
                    value.value.text.merge(cellContext.value.text); value.value.paragraph.merge(cellContext.value.paragraph)
                    let declared = try styleDeclarations(name, family: "paragraph", part: part)
                    value.value.id = declared.value.id
                    value.value.text.merge(declared.value.text); value.value.paragraph.merge(declared.value.paragraph)
                } else { value = try style(name, family: "paragraph", part: part) }
                var paragraph = Paragraph(); paragraph.styleID = name.map { _ in value.value.id }; paragraph.list = list
                paragraph.formatting = value.value.paragraph; paragraph.defaultTextFormatting = value.value.text
                if node.name == "h", let raw = node.attribute(ODF.text, "outline-level") {
                    guard let level = Int(raw), level > 0 else { throw DocumentError.invalidXML(part: part, detail: "invalid ODF outline level") }
                    paragraph.formatting.outlineLevel = level - 1
                }
                paragraph.inlines = try inlines(node, base: value.value.text, part: part); result.append(.paragraph(paragraph))
            } else if node.namespace == ODF.table && node.name == "table" { result.append(.table(try table(node, part: part))) }
            else if node.namespace == ODF.text && ["section", "list-item", "list-header"].contains(node.name) {
                extensions(node, part: part)
                result += try blocks(node.children, part: part, list: list)
            }
            else if node.namespace == ODF.text && node.name == "list" {
                extensions(node, part: part, attributes: [(ODF.text, ["style-name"])])
                let name = node.attribute(ODF.text, "style-name") ?? list?.id
                let ref = name.map { ListReference(id: $0, level: list.map { $0.level + 1 } ?? 0) }
                result += try blocks(node.children, part: part, list: ref)
            } else if node.namespace == ODF.text && ["sequence-decls", "variable-decls", "user-field-decls"].contains(node.name) { if !node.children.isEmpty { nonBody.append(warn(node, part: part)) } }
            else { result.append(.unsupported(warn(node, part: part))) }
        }
        return result
    }
    func independentBlocks(_ nodes: [MarkupNode], part: String) throws -> [Block] {
        let enclosing = cellContext; cellContext = nil
        defer { cellContext = enclosing }
        return try blocks(nodes, part: part)
    }
    func inlines(_ node: MarkupNode, base: TextFormatting, part: String) throws -> [Inline] {
        var result: [Inline] = []
        for item in node.content {
            try charge()
            switch item {
            case .text(let text): if !text.isEmpty { result.append(.text(TextRun(text, formatting: base))) }
            case .node(let child):
                if child.namespace == ODF.text {
                    switch child.name {
                    case "span":
                        extensions(child, part: part, attributes: [(ODF.text, ["style-name"])], text: true)
                        var f = base; f.merge(try style(child.attribute(ODF.text, "style-name"), family: "text", part: part).value.text)
                        result += try inlines(child, base: f, part: part)
                    case "s":
                        extensions(child, part: part, attributes: [(ODF.text, ["c"])], children: [])
                        let n = try count(child, namespace: ODF.text, name: "c"); try charge(n)
                        result.append(.text(TextRun(String(repeating: " ", count: n), formatting: base)))
                    case "tab":
                        extensions(child, part: part, children: []); result.append(.tab)
                    case "line-break":
                        extensions(child, part: part, children: []); result.append(.lineBreak(.line))
                    case "ruby":
                        extensions(child, part: part, attributes: [(ODF.text, ["style-name"])], children: [(ODF.text, ["ruby-base", "ruby-text"])])
                        let bases = child.children.filter { $0.namespace == ODF.text && $0.name == "ruby-base" }
                        let annotations = child.children.filter { $0.namespace == ODF.text && $0.name == "ruby-text" }
                        guard bases.count == 1 && annotations.count == 1 else { throw DocumentError.invalidXML(part: part, detail: "expected one ODF ruby base and annotation") }
                        extensions(bases[0], part: part, text: true)
                        extensions(annotations[0], part: part, attributes: [(ODF.text, ["style-name"])], text: true)
                        let rubyStyle = try style(child.attribute(ODF.text, "style-name"), family: "ruby", part: part)
                        var annotationFormatting = base
                        annotationFormatting.merge(try style(annotations[0].attribute(ODF.text, "style-name"), family: "text", part: part).value.text)
                        var ruby = RubyText(base: try inlines(bases[0], base: base, part: part), annotation: try inlines(annotations[0], base: annotationFormatting, part: part))
                        ruby.alignment = rubyStyle.rubyAlignment; ruby.position = rubyStyle.rubyPosition
                        ruby.annotationSize = annotationFormatting.fontSize; ruby.baseSize = base.fontSize; ruby.language = annotationFormatting.language
                        ruby.rawProperties = [child.xml]; result.append(.ruby(ruby))
                    case "a":
                        extensions(child, part: part, attributes: [(ODF.link, ["href"])], text: true)
                        result.append(.hyperlink(Hyperlink(target: child.attribute(ODF.link, "href"), inlines: try inlines(child, base: base, part: part))))
                    case "bookmark", "bookmark-start", "bookmark-end":
                        extensions(child, part: part, attributes: [(ODF.text, ["name"])], children: [])
                        let id = child.attribute(ODF.text, "name") ?? ""
                        result.append(.bookmark(Bookmark(id: id, name: id, isStart: child.name != "bookmark-end")))
                    case "note":
                        extensions(child, part: part, attributes: [(ODF.text, ["id", "note-class"])], children: [(ODF.text, ["note-body"])])
                        let bodies = child.children.filter { $0.namespace == ODF.text && $0.name == "note-body" }
                        guard bodies.count == 1 else { throw DocumentError.invalidXML(part: part, detail: "expected one ODF note body") }
                        extensions(bodies[0], part: part)
                        let id = child.attribute(ODF.text, "id") ?? "note-\(stories.count)", kind: StoryKind = child.attribute(ODF.text, "note-class") == "endnote" ? .endnote : .footnote
                        if let value = child.attribute(ODF.text, "note-class"), !["footnote", "endnote"].contains(value) { throw DocumentError.invalidXML(part: part, detail: "invalid ODF note class") }
                        if options.includeRelatedStories { stories.append(Story(id: id, kind: kind, sourcePart: part, blocks: try independentBlocks(bodies[0].children, part: part))) }
                        else { warnings.add(.storiesOmitted, part: part, element: "note", message: "Related stories omitted by ReadOptions.") }
                        result.append(.noteReference(NoteReference(id: id, kind: kind)))
                    default:
                        result.append(.unsupported(warn(child, part: part))); result += try inlines(child, base: base, part: part)
                    }
                } else if child.namespace == ODF.draw && child.name == "frame" {
                    let anchor = child.attribute(ODF.text, "anchor-type")
                    if anchor == "as-char", let image = child.odf(ODF.draw, "image"), let href = image.attribute(ODF.link, "href") {
                        extensions(child, part: part, attributes: [(ODF.text, ["anchor-type"]), (ODF.svg, ["width", "height"])], children: [(ODF.draw, ["image"]), (ODF.svg, ["title", "desc"])])
                        extensions(image, part: part, attributes: [(ODF.link, ["href"])], children: [])
                        for label in child.children where label.namespace == ODF.svg && ["title", "desc"].contains(label.name) { extensions(label, part: part, children: [], text: true) }
                        for measure in ["width", "height"] {
                            if let raw = child.attribute(ODF.svg, measure), length(raw) == nil { diagnose(child, part: part, formatting: true) }
                        }
                        let url = URL(string: href)
                        var value = DocumentImage(alternativeText: child.odf(ODF.svg, "desc")?.text, width: length(child.attribute(ODF.svg, "width")), height: length(child.attribute(ODF.svg, "height")))
                        if url?.scheme != nil || href.hasPrefix("//") { value.externalURL = href }
                        else {
                            let path = try OPCPackage.resolve(href, from: part)
                            guard archive.entries[path] != nil else { throw DocumentError.missingPart(path) }
                            value.assetPath = path; value.contentType = mediaTypes[path]
                        }
                        result.append(.image(value))
                        for extra in child.children where extra !== image && !(extra.namespace == ODF.svg && ["title", "desc"].contains(extra.name)) { warn(extra, part: part) }
                    } else { result.append(.unsupported(warn(child, part: part))) }
                } else if child.namespace == ODF.office && child.name == "annotation" {
                    extensions(child, part: part, attributes: [(ODF.office, ["name"])])
                    let id = child.attribute(ODF.office, "name") ?? "comment-\(stories.count)"
                    if options.includeRelatedStories {
                        let dc = "http://purl.org/dc/elements/1.1/"
                        let content = child.children.filter { $0.namespace != dc || !["creator", "date"].contains($0.name) }
                        for metadata in child.children where metadata.namespace == dc && ["creator", "date"].contains(metadata.name) { extensions(metadata, part: part, children: [], text: true) }
                        stories.append(Story(id: id, kind: .comment, sourcePart: part, blocks: try independentBlocks(content, part: part), author: child.odf(dc, "creator")?.text, date: child.odf(dc, "date")?.text))
                    } else { warnings.add(.storiesOmitted, part: part, element: "annotation", message: "Related stories omitted by ReadOptions.") }
                    result.append(.commentReference(CommentReference(id: id, boundary: .reference)))
                } else if child.namespace == ODF.office && child.name == "annotation-end" {
                    extensions(child, part: part, attributes: [(ODF.office, ["name"])], children: [])
                    guard let id = child.attribute(ODF.office, "name"), !id.isEmpty else { throw DocumentError.invalidXML(part: part, detail: "missing ODF annotation-end name") }
                    result.append(.commentReference(CommentReference(id: id, boundary: .end)))
                } else { result.append(.unsupported(warn(child, part: part))) }
            }
        }
        return result
    }
    func table(_ node: MarkupNode, part: String) throws -> Table {
        let enclosing = cellContext; cellContext = nil
        defer { cellContext = enclosing }
        extensions(node, part: part, attributes: [(ODF.table, ["style-name", "name"])])
        var table = Table(); let name = node.attribute(ODF.table, "style-name")
        let tableStyle = try style(name, family: "table", part: part)
        table.formatting = tableStyle.table; table.styleID = name.map { _ in tableStyle.value.id }
        var columnDefaults: [String?] = []
        let columnContainers = ["table-columns", "table-header-columns", "table-column-group"]
        func columns(_ nodes: [MarkupNode]) throws {
            for node in nodes where node.namespace == ODF.table {
                if columnContainers.contains(node.name) {
                    try charge(); extensions(node, part: part); try columns(node.children)
                } else if node.name == "table-column" {
                    extensions(node, part: part, attributes: [(ODF.table, ["number-columns-repeated", "style-name", "default-cell-style-name"])], children: [])
                    let repeats = try count(node, namespace: ODF.table, name: "number-columns-repeated"); try charge(repeats)
                    let value = try style(node.attribute(ODF.table, "style-name"), family: "table-column", part: part)
                    for _ in 0..<repeats {
                        table.columns.append(value.column); columnDefaults.append(node.attribute(ODF.table, "default-cell-style-name"))
                    }
                }
            }
        }
        try columns(node.children)
        func rows(_ nodes: [MarkupNode], header: Bool = false) throws {
            for row in nodes {
                try charge()
                if row.namespace == ODF.table && (row.name == "table-column" || columnContainers.contains(row.name)) { continue }
                if row.namespace == ODF.table && ["table-header-rows", "table-rows", "table-row-group"].contains(row.name) {
                    extensions(row, part: part)
                    try rows(row.children, header: header || row.name == "table-header-rows"); continue
                }
                guard row.namespace == ODF.table && row.name == "table-row" else { warn(row, part: part); continue }
                extensions(row, part: part, attributes: [(ODF.table, ["number-rows-repeated", "style-name", "default-cell-style-name"])])
                let repeats = try count(row, namespace: ODF.table, name: "number-rows-repeated")
                let rowStyle = try style(row.attribute(ODF.table, "style-name"), family: "table-row", part: part)
                for _ in 0..<repeats {
                    try charge(); var value = TableRow(); value.formatting = rowStyle.row; value.isHeader = header
                    var columnIndex = 0
                    for cell in row.children {
                        guard cell.namespace == ODF.table && ["table-cell", "covered-table-cell"].contains(cell.name) else { warn(cell, part: part); continue }
                        extensions(cell, part: part, attributes: [(ODF.table, ["number-columns-repeated", "number-columns-spanned", "number-rows-spanned", "style-name"])])
                        let copies = try count(cell, namespace: ODF.table, name: "number-columns-repeated")
                        for _ in 0..<copies {
                            try charge()
                            var context = defaults["table-cell"] ?? ODFStyle(value: DocumentStyle(id: "", name: "", kind: "table-cell"))
                            let columnDefault = columnDefaults.indices.contains(columnIndex) ? columnDefaults[columnIndex] : nil
                            for styleName in [columnDefault, row.attribute(ODF.table, "default-cell-style-name"), cell.attribute(ODF.table, "style-name")] {
                                let declaration = try styleDeclarations(styleName, family: "table-cell", part: part)
                                context.cell.mergeAppearance(declaration.cell); context.cell.rawProperties += declaration.cell.rawProperties
                                context.value.text.merge(declaration.value.text); context.value.paragraph.merge(declaration.value.paragraph)
                            }
                            var c = TableCell(); c.formatting = context.cell
                            c.isCovered = cell.name == "covered-table-cell"
                            c.columnSpan = try count(cell, namespace: ODF.table, name: "number-columns-spanned")
                            c.rowSpan = try count(cell, namespace: ODF.table, name: "number-rows-spanned")
                            if c.rowSpan > 1 { c.verticalMerge = .restart }
                            cellContext = context; c.blocks = try blocks(cell.children, part: part)
                            value.cells.append(c); columnIndex += 1
                        }
                    }
                    table.rows.append(value)
                }
            }
        }
        try rows(node.children)
        return table
    }
}
