import Foundation
import DocumentCore

extension ODTCodec {
    /// Generate an ODF 1.3 text package from the basic model subset.
    public func write(_ document: Document, options: WriteOptions = .init()) throws -> WriteResult {
        try ODTWriter().write(document, options: options)
    }
}
private final class ODTWriter {
    let context = BasicWriting()
    var styles: [String] = []
    var model = Document()
    var nextID = 0
    let namespaces = "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\""
    func xml(_ value: String) throws -> String { try BasicWriting.xml(value) }
    func id() -> String { nextID += 1; return "s\(nextID)" }
    func write(_ source: Document, options: WriteOptions) throws -> WriteResult {
        model = try context.project(source)
        let body = try blocks(model.blocks)
        let content = "<office:document-content \(namespaces) office:version=\"1.3\"><office:automatic-styles>\(styles.joined())</office:automatic-styles><office:body><office:text>\(body)</office:text></office:body></office:document-content>"
        let metadata = model.metadata
        var meta = "<office:document-meta xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\" office:version=\"1.3\"><office:meta>"
        for (key, value) in [("dc:title", metadata.title), ("dc:subject", metadata.subject), ("meta:initial-creator", metadata.creator), ("dc:description", metadata.description), ("meta:keyword", metadata.keywords)] { if let value { meta += "<\(key)>\(try xml(value))</\(key)>" } }
        meta += "</office:meta></office:document-meta>"
        let mime = "application/vnd.oasis.opendocument.text"
        let manifest = "<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\"><manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.3\" manifest:media-type=\"\(mime)\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"meta.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>"
        return try context.finish(ZIPWriter.write(["mimetype": Data(mime.utf8), "content.xml": Data(content.utf8), "meta.xml": Data(meta.utf8), "META-INF/manifest.xml": Data(manifest.utf8)], compress: options.compress, firstStored: "mimetype"), options: options)
    }
    func textProperties(_ f: TextFormatting) throws -> String {
        var attributes = ""
        if let v = f.bold { attributes += " fo:font-weight=\"\(v ? "bold" : "normal")\"" }
        if let v = f.italic { attributes += " fo:font-style=\"\(v ? "italic" : "normal")\"" }
        if let v = f.strike { attributes += " style:text-line-through-style=\"\(v ? "solid" : "none")\"" }
        if let v = f.fontName { attributes += " fo:font-family=\"\(try xml(v))\"" }
        if let v = f.fontSize { attributes += " fo:font-size=\"\(v)pt\"" }
        if let v = f.color { attributes += " fo:color=\"#\(v)\"" }
        if let v = f.underline { attributes += " style:text-underline-style=\"\(v == "none" ? "none" : "solid")\" style:text-underline-type=\"\(v == "double" ? "double" : "single")\"" }
        return "<style:text-properties\(attributes)/>"
    }
    func text(_ value: String) throws -> String {
        var result = "", pending = ""
        func flush() throws { result += try xml(pending); pending = "" }
        for c in value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") {
            switch c {
            case " ": try flush(); result += "<text:s/>"
            case "\t": try flush(); result += "<text:tab/>"
            case "\n": try flush(); result += "<text:line-break/>"
            default: pending.append(c)
            }
        }
        try flush(); return result
    }
    func inlines(_ values: [Inline]) throws -> String {
        var result = ""
        for value in values {
            try Task.checkCancellation()
            switch value {
            case .text(let run):
                let name = id(); styles.append("<style:style style:name=\"\(name)\" style:family=\"text\">\(try textProperties(run.formatting))</style:style>")
                result += "<text:span text:style-name=\"\(name)\">\(try text(run.text))</text:span>"
            case .tab: result += "<text:tab/>"
            case .lineBreak(let kind):
                if kind == .line { result += "<text:line-break/>" }
                else {
                    // ODF expresses page/column breaks as paragraph properties; avoid inventing paragraph boundaries.
                    context.warn(.flattenedContent, "break", "Inline page/column break is written as a line break."); result += "<text:line-break/>"
                }
            case .hyperlink(let link):
                let target = (link.target ?? "") + (link.anchor.map { "#" + $0 } ?? "")
                guard !target.isEmpty else { throw DocumentError.invalidModel("empty hyperlink target") }
                if link.tooltip != nil { context.warn(.unsupportedFormatting, "hyperlinkTooltip", "Hyperlink tooltip is omitted.") }
                result += "<text:a xlink:type=\"simple\" xlink:href=\"\(try xml(target))\">\(try inlines(link.inlines))</text:a>"
            default: break
            }
        }
        return result
    }
    func blocks(_ values: [Block]) throws -> String {
        var result = "", activeList: String?
        for value in values {
            try Task.checkCancellation()
            if case .paragraph(let p) = value, let list = p.list, list.level == 0 {
                if activeList != list.id {
                    if activeList != nil { result += "</text:list>" }
                    let style = try listStyle(list)
                    result += "<text:list text:style-name=\"\(style)\">"; activeList = list.id
                }
                result += "<text:list-item>\(try paragraph(p))</text:list-item>"; continue
            }
            if activeList != nil { result += "</text:list>"; activeList = nil }
            switch value {
            case .paragraph(let p):
                if p.list != nil { context.warn(.flattenedContent, "listLevel", "Nested list level is projected to an ordinary paragraph.") }
                result += try paragraph(p)
            case .table(let table):
                let tableID = id()
                result += "<table:table table:name=\"Table\(tableID)\"><table:table-column table:number-columns-repeated=\"\(table.rows.map { $0.cells.count }.max() ?? 1)\"/>"
                for row in table.rows {
                    if row.isHeader { context.warn(.unsupportedFormatting, "tableHeader", "Repeated table header flag is omitted.") }
                    result += "<table:table-row>"
                    for cell in row.cells { result += "<table:table-cell office:value-type=\"string\">\(try blocks(cell.blocks))</table:table-cell>" }
                    result += "</table:table-row>"
                }
                result += "</table:table>"
            default: break
            }
        }
        if activeList != nil { result += "</text:list>" }
        return result
    }
    func paragraph(_ p: Paragraph) throws -> String {
        let name = id()
        var properties = ""
        if let v = p.formatting.alignment {
            if [.left, .right, .center, .start, .end, .justified].contains(v) { properties += " fo:text-align=\"\(v == .justified ? "justify" : v.rawValue)\"" }
            else { context.warn(.unsupportedFormatting, "alignment", "This paragraph alignment has no basic ODF mapping and is omitted.") }
        }
        styles.append("<style:style style:name=\"\(name)\" style:family=\"paragraph\"><style:paragraph-properties\(properties)/>\(try textProperties(p.defaultTextFormatting))</style:style>")
        let tag = p.formatting.outlineLevel == nil ? "text:p" : "text:h"
        let level = p.formatting.outlineLevel.map { " text:outline-level=\"\($0 + 1)\"" } ?? ""
        return "<\(tag) text:style-name=\"\(name)\"\(level)>\(try inlines(p.inlines))</\(tag)>"
    }
    func listStyle(_ list: ListReference) throws -> String {
        guard let level = model.numbering[list.id]?.levels[0] else { throw DocumentError.invalidModel("missing list level") }
        guard level.level == 0, level.start >= 0, level.start <= Int(Int32.max) else { throw DocumentError.invalidModel("invalid list start/level") }
        if level.start == 0 { context.warn(.unsupportedFormatting, "listStart", "ODF numbering requires a positive start; zero is written as one.") }
        if level.picture != nil || !level.rawProperties.isEmpty || level.formatting != TextFormatting() || level.paragraph != ParagraphFormatting() || level.restartAfterLevel != nil || level.isLegal || level.suffix != "tab" { context.warn(.unsupportedFormatting, "numbering", "Advanced numbering properties are omitted.") }
        let name = id(), declaration: String
        if level.format == "bullet" {
            let bullet = level.text.isEmpty ? "•" : String(level.text.prefix(1))
            declaration = "<text:list-level-style-bullet text:level=\"1\" text:bullet-char=\"\(try xml(bullet))\"/>"
        } else {
            let formats = ["decimal": "1", "lowerLetter": "a", "upperLetter": "A", "lowerRoman": "i", "upperRoman": "I"]
            let format = formats[level.format] ?? "1"
            if formats[level.format] == nil || level.text != "%1." { context.warn(.unsupportedFormatting, "numberingPattern", "Numbering pattern is written using a standard decimal/alphabetic/Roman marker and period.") }
            declaration = "<text:list-level-style-number text:level=\"1\" style:num-format=\"\(format)\" style:num-suffix=\".\" text:start-value=\"\(max(1, level.start))\"/>"
        }
        styles.append("<text:list-style style:name=\"\(name)\">\(declaration)</text:list-style>"); return name
    }
}
