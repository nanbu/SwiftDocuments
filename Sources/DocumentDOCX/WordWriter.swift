import Foundation
import DocumentCore

extension DOCXCodec {
    /// Generate a new Word package from the documented basic subset.
    public func write(_ document: Document, options: WriteOptions = .init()) throws -> WriteResult {
        let writer = WordWriter(format: format)
        return try writer.write(document, options: options)
    }
}
private final class WordWriter {
    let format: DocumentFormat
    let context = BasicWriting()
    let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    let packageR = "http://schemas.openxmlformats.org/package/2006/relationships"
    var links: [(String, String)] = []
    var numbers: [String: Int] = [:]
    var styles: [String] = []
    var model = Document()
    init(format: DocumentFormat) { self.format = format }
    func xml(_ text: String) throws -> String { try BasicWriting.xml(text) }
    func write(_ source: Document, options: WriteOptions) throws -> WriteResult {
        model = try context.project(source)
        for (index, id) in model.numbering.keys.sorted().enumerated() { numbers[id] = index + 1 }
        let body = try blocks(model.blocks)
        let numbering = try numberingXML()
        let mainType = format == .docm ? "application/vnd.ms-word.document.macroEnabled.main+xml" : "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
        let metadata = try metadataXML(model.metadata)
        var types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"\(mainType)\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        var rels = "<Relationships xmlns=\"\(packageR)\">"
        for (id, target) in links { rels += "<Relationship Id=\"\(id)\" Type=\"\(r)/hyperlink\" Target=\"\(try xml(target))\" TargetMode=\"External\"/>" }
        if !numbering.isEmpty {
            types += "<Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>"
            rels += "<Relationship Id=\"numbering\" Type=\"\(r)/numbering\" Target=\"numbering.xml\"/>"
        }
        if !styles.isEmpty {
            types += "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
            rels += "<Relationship Id=\"styles\" Type=\"\(r)/styles\" Target=\"styles.xml\"/>"
        }
        types += "</Types>"; rels += "</Relationships>"
        var parts: [String: String] = [
            "[Content_Types].xml": types,
            "_rels/.rels": "<Relationships xmlns=\"\(packageR)\"><Relationship Id=\"main\" Type=\"\(r)/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"core\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/></Relationships>",
            "word/document.xml": "<w:document xmlns:w=\"\(w)\" xmlns:r=\"\(r)\"><w:body>\(body)<w:sectPr/></w:body></w:document>",
            "word/_rels/document.xml.rels": rels,
            "docProps/core.xml": metadata
        ]
        if !numbering.isEmpty { parts["word/numbering.xml"] = numbering }
        if !styles.isEmpty { parts["word/styles.xml"] = "<w:styles xmlns:w=\"\(w)\">\(styles.joined())</w:styles>" }
        return try context.finish(ZIPWriter.write(parts.mapValues { Data($0.utf8) }, compress: options.compress), options: options)
    }
    func textProperties(_ f: TextFormatting) throws -> String {
        var value = ""
        for (name, flag) in [("b", f.bold), ("i", f.italic), ("strike", f.strike)] { if let flag { value += "<w:\(name) w:val=\"\(flag ? 1 : 0)\"/>" } }
        if let name = f.fontName { value += "<w:rFonts w:ascii=\"\(try xml(name))\" w:hAnsi=\"\(try xml(name))\"/>" }
        if let size = f.fontSize { value += "<w:sz w:val=\"\(Int(size * 2))\"/>" }
        if let color = f.color { value += "<w:color w:val=\"\(color)\"/>" }
        if let underline = f.underline { value += "<w:u w:val=\"\(underline)\"/>" }
        return value
    }
    func inlines(_ values: [Inline], base: TextFormatting) throws -> String {
        var result = ""
        for value in values {
            try Task.checkCancellation()
            switch value {
            case .text(let run):
                var f = base; f.merge(run.formatting)
                let properties = try textProperties(f)
                let text = run.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                var content = "", pending = ""
                func flush() throws { if !pending.isEmpty { content += "<w:t xml:space=\"preserve\">\(try xml(pending))</w:t>"; pending = "" } }
                for c in text {
                    if c == "\t" || c == "\n" { try flush(); content += c == "\t" ? "<w:tab/>" : "<w:br/>" }
                    else { pending.append(c) }
                }
                try flush(); result += "<w:r><w:rPr>\(properties)</w:rPr>\(content)</w:r>"
            case .tab: result += "<w:r><w:tab/></w:r>"
            case .lineBreak(let kind): result += "<w:r><w:br w:type=\"\(kind == .line ? "textWrapping" : kind.rawValue)\"/></w:r>"
            case .hyperlink(let link):
                var attributes = ""
                if let target = link.target {
                    guard !target.isEmpty else { throw DocumentError.invalidModel("empty hyperlink target") }
                    let id = "link\(links.count + 1)"; links.append((id, target)); attributes += " r:id=\"\(id)\""
                }
                if let anchor = link.anchor { attributes += " w:anchor=\"\(try xml(anchor))\"" }
                if let tooltip = link.tooltip { attributes += " w:tooltip=\"\(try xml(tooltip))\"" }
                result += "<w:hyperlink\(attributes)>\(try inlines(link.inlines, base: base))</w:hyperlink>"
            default: break // The shared projection has diagnosed and flattened unsupported inlines.
            }
        }
        return result
    }
    func blocks(_ values: [Block]) throws -> String {
        var output = ""
        for value in values {
            try Task.checkCancellation()
            switch value {
            case .paragraph(let p):
                var props = ""
                if p.defaultTextFormatting != TextFormatting() {
                    let name = "Generated\(styles.count + 1)"
                    styles.append("<w:style w:type=\"paragraph\" w:styleId=\"\(name)\"><w:name w:val=\"\(name)\"/><w:rPr>\(try textProperties(p.defaultTextFormatting))</w:rPr></w:style>")
                    props += "<w:pStyle w:val=\"\(name)\"/>"
                }
                if let alignment = p.formatting.alignment { props += "<w:jc w:val=\"\(alignment == .justified ? "both" : alignment.rawValue)\"/>" }
                if let level = p.formatting.outlineLevel { props += "<w:outlineLvl w:val=\"\(level)\"/>" }
                if let list = p.list, let id = numbers[list.id] { props += "<w:numPr><w:ilvl w:val=\"\(list.level)\"/><w:numId w:val=\"\(id)\"/></w:numPr>" }
                output += "<w:p><w:pPr>\(props)</w:pPr>\(try inlines(p.inlines, base: p.defaultTextFormatting))</w:p>"
            case .table(let table):
                let count = table.rows.map { $0.cells.count }.max() ?? 1
                output += "<w:tbl><w:tblPr/><w:tblGrid>" + String(repeating: "<w:gridCol w:w=\"2400\"/>", count: count) + "</w:tblGrid>"
                for row in table.rows {
                    output += "<w:tr>" + (row.isHeader ? "<w:trPr><w:tblHeader/></w:trPr>" : "")
                    for cell in row.cells {
                        let content = try blocks(cell.blocks)
                        let ending: String
                        if case .paragraph? = cell.blocks.last { ending = "" } else {
                            ending = "<w:p/>"
                            if !cell.blocks.isEmpty { context.warn(.flattenedContent, "cellTerminator", "A final empty paragraph is added after nested cell content, as required by Word.") }
                        }
                        output += "<w:tc><w:tcPr/>\(content)\(ending)</w:tc>"
                    }
                    output += "</w:tr>"
                }
                output += "</w:tbl>"
            default: break
            }
        }
        return output
    }
    func numberingXML() throws -> String {
        guard !numbers.isEmpty else { return "" }
        var result = "<w:numbering xmlns:w=\"\(w)\">"
        for id in numbers.keys.sorted() {
            let number = numbers[id]!, definition = model.numbering[id]!
            result += "<w:abstractNum w:abstractNumId=\"\(number)\">"
            for key in definition.levels.keys.sorted() {
                let level = definition.levels[key]!
                guard (0...8).contains(key), level.level == key, level.start >= 0, level.start <= Int(Int32.max) else { throw DocumentError.invalidModel("invalid numbering level/start") }
                let supported: Set<String> = ["decimal", "bullet", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman", "none"]
                let format = supported.contains(level.format) ? level.format : "decimal"
                if format != level.format || level.picture != nil || !level.rawProperties.isEmpty || level.formatting != TextFormatting() || level.paragraph != ParagraphFormatting() || level.restartAfterLevel != nil || level.isLegal || !["tab", "space", "nothing"].contains(level.suffix) { context.warn(.unsupportedFormatting, "numbering", "Advanced numbering properties are omitted or substituted.") }
                result += "<w:lvl w:ilvl=\"\(key)\"><w:start w:val=\"\(level.start)\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(try xml(level.text))\"/><w:suff w:val=\"\(["tab", "space", "nothing"].contains(level.suffix) ? level.suffix : "tab")\"/></w:lvl>"
            }
            result += "</w:abstractNum>"
        }
        for id in numbers.keys.sorted() { let n = numbers[id]!; result += "<w:num w:numId=\"\(n)\"><w:abstractNumId w:val=\"\(n)\"/></w:num>" }
        return result + "</w:numbering>"
    }
    func metadataXML(_ metadata: DocumentMetadata) throws -> String {
        var result = "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
        for (key, value) in [("dc:title", metadata.title), ("dc:subject", metadata.subject), ("dc:creator", metadata.creator), ("dc:description", metadata.description), ("cp:keywords", metadata.keywords)] { if let value { result += "<\(key)>\(try xml(value))</\(key)>" } }
        return result + "</cp:coreProperties>"
    }
}
