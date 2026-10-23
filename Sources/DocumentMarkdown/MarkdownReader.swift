import Foundation
import DocumentCore

/// A UTF-8 Markdown subset reader. Bytes require explicit format selection.
public struct MarkdownCodec: DocumentCodec {
    public let format = DocumentFormat.markdown
    public init() {}
    public func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult {
        var blocks: [Block] = []
        var result = try scan(data, options: options) { blocks.append($0) }
        result.document.blocks = blocks
        return ReadResult(document: result.document)
    }
    public func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary {
        _ = try markdownText(data, limits: limits)
        return DocumentSummary(format: .markdown, metadata: .init(), parts: [])
    }
    public func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try MarkdownParser(markdownText(data, limits: options.limits), limits: options.limits).scan(onBlock)
    }
}
extension Codec { public static let markdown = Codec(MarkdownCodec()) }

private func markdownText(_ data: Data, limits: PackageLimits) throws -> String {
    try Task.checkCancellation()
    guard data.count <= limits.maxPartBytes, data.count <= limits.maxExpandedBytes, limits.maxXMLNodes > 0, limits.maxXMLDepth > 0 else { throw DocumentError.limitExceeded("Markdown input") }
    guard let value = String(data: data, encoding: .utf8), !value.contains("\0") else { throw DocumentError.invalidText("Markdown requires UTF-8 without NUL") }
    let text = value.hasPrefix("\u{FEFF}") ? String(value.dropFirst()) : value
    try Task.checkCancellation()
    return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
}
private final class MarkdownParser {
    let lines: [String]
    let limits: PackageLimits
    let warnings = WarningCollector()
    var remaining: Int
    var document = Document()
    var activeList: (kind: String, id: String)?
    var listCount = 0
    init(_ text: String, limits: PackageLimits) {
        lines = text.components(separatedBy: "\n"); self.limits = limits; remaining = limits.maxXMLNodes
        document.sourceFormat = .markdown
    }
    func charge(_ amount: Int = 1) throws {
        try Task.checkCancellation()
        guard amount >= 0, amount <= remaining else { throw DocumentError.limitExceeded("Markdown parser work") }; remaining -= amount
    }
    func warn(_ element: String) { warnings.add(.unsupportedContent, part: "Markdown", element: element, message: "Markdown construct outside the supported subset is retained as literal source.") }
    func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }
    func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { i in Range(match.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }
    func fence(_ text: String) -> (character: Character, count: Int, info: String)? {
        guard let parts = captures("^ {0,3}(`{3,}|~{3,})(.*)$", text) else { return nil }
        let marker = parts[0], info = trim(parts[1])
        if marker.first == "`" && info.contains("`") { return nil }
        return (marker.first!, marker.count, info)
    }
    func heading(_ text: String) -> (Int, String)? {
        guard let parts = captures("^ {0,3}(#{1,6})(?:[ \\t]+(.*)|$)", text) else { return nil }
        let body = parts[1].replacingOccurrences(of: "[ \\t]+#+[ \\t]*$", with: "", options: .regularExpression)
        return (parts[0].count - 1, trim(body))
    }
    func list(_ text: String) -> (String, Int, String)? {
        if let parts = captures("^ {0,3}([-+*])[ \\t]+(.*)$", text) { return ("bullet", 1, parts[1]) }
        if let parts = captures("^ {0,3}([0-9]{1,9})[.)][ \\t]+(.*)$", text), let start = Int(parts[0]) { return ("decimal", start, parts[1]) }
        return nil
    }
    func unsupported(_ text: String) -> String? {
        let s = trim(text)
        if text.hasPrefix("    ") || text.hasPrefix("\t") { return "indentedBlock" }
        if s.hasPrefix(">") { return "blockQuote" }
        if captures("^<(?:/?[A-Za-z][A-Za-z0-9-]*(?:[ \\t]|/?>)|!--|!DOCTYPE|\\?)", s) != nil { return "HTML" }
        if captures("^\\[[^]]+\\]:", s) != nil { return "referenceLink" }
        if s.contains("|") { return "tableOrPipe" }
        if captures("^(?:\\*[ \\t]*){3,}$|^(?:_[ \\t]*){3,}$|^(?:-[ \\t]*){3,}$", s) != nil { return "thematicBreak" }
        return nil
    }
    func scan(_ callback: (Block) throws -> Void) throws -> ScanResult {
        var index = 0, count = 0
        func emit(_ p: Paragraph) throws {
            try charge(); try callback(.paragraph(p)); try Task.checkCancellation(); count += 1
        }
        while index < lines.count {
            try charge()
            let line = lines[index]
            if trim(line).isEmpty { activeList = nil; index += 1; continue }
            if let opening = fence(line) {
                activeList = nil; index += 1; var code: [String] = []
                if !opening.info.isEmpty { warn("codeLanguage") }
                while index < lines.count {
                    let candidate = lines[index], s = candidate.drop(while: { $0 == " " })
                    let indent = candidate.prefix(while: { $0 == " " }).count
                    let marker = s.prefix(while: { $0 == opening.character })
                    if indent <= 3 && marker.count >= opening.count && trim(String(s.dropFirst(marker.count))).isEmpty { index += 1; break }
                    try charge(candidate.utf8.count); code.append(candidate); index += 1
                }
                // A terminal source newline belongs to the fence, not to an additional code line.
                if index == lines.count, code.last == "", lines.last == "" { code.removeLast() }
                var p = Paragraph(); p.styleID = "MarkdownCode"
                var f = TextFormatting(); f.fontName = "Courier"
                p.inlines = [.text(TextRun(code.joined(separator: "\n"), formatting: f))]
                try emit(p); continue
            }
            if let (level, body) = heading(line) {
                activeList = nil; var p = Paragraph(); p.formatting.outlineLevel = level
                p.inlines = try inline(body); try emit(p); index += 1; continue
            }
            if let kind = unsupported(line) {
                activeList = nil; warn(kind); var p = Paragraph(); p.inlines = [.text(TextRun(line))]
                try charge(line.utf8.count); try emit(p); index += 1; continue
            }
            if let (kind, start, body) = list(line) {
                if activeList?.kind != kind {
                    listCount += 1; let id = "markdown-list-\(listCount)"
                    document.numbering[id] = NumberingDefinition(id: id, abstractID: id, levels: [0: NumberingLevel(level: 0, start: start, format: kind, text: kind == "bullet" ? "•" : "%1.")])
                    activeList = (kind, id)
                }
                var p = Paragraph(); p.list = ListReference(id: activeList!.id)
                p.inlines = try inline(body); try emit(p); index += 1; continue
            }
            activeList = nil
            var content: [String] = [line]; index += 1; var outline: Int?
            while index < lines.count && !trim(lines[index]).isEmpty {
                if let marker = captures("^ {0,3}(=+|-+)[ \\t]*$", lines[index]) { outline = marker[0].first == "=" ? 0 : 1; index += 1; break }
                if heading(lines[index]) != nil || fence(lines[index]) != nil || list(lines[index]) != nil || unsupported(lines[index]) != nil { break }
                content.append(lines[index]); index += 1
            }
            var p = Paragraph(); p.formatting.outlineLevel = outline
            for (i, value) in content.enumerated() {
                let hard = value.hasSuffix("  ") || value.hasSuffix("\\")
                let body = value.hasSuffix("\\") ? String(value.dropLast()) : value.trimmingCharacters(in: .whitespaces)
                p.inlines += try inline(body)
                if i + 1 < content.count { p.inlines.append(hard ? .lineBreak(.line) : .text(TextRun(" "))) }
            }
            try emit(p)
        }
        document.readWarnings = warnings.result
        return ScanResult(document: document, blocksRead: count)
    }
    func inline(_ text: String, formatting: TextFormatting = .init(), depth: Int = 0) throws -> [Inline] {
        guard depth < min(limits.maxXMLDepth, 128) else { throw DocumentError.limitExceeded("Markdown inline depth") }
        let chars = Array(text); var i = 0, pending = "", result: [Inline] = []
        func flush() { if !pending.isEmpty { result.append(.text(TextRun(pending, formatting: formatting))); pending = "" } }
        func match(_ marker: [Character], from start: Int) throws -> Int? {
            guard start <= chars.count - marker.count else { return nil }
            for j in start...chars.count - marker.count {
                try charge(marker.count)
                if Array(chars[j..<j + marker.count]) == marker && (j == 0 || chars[j - 1] != "\\") { return j }
            }
            return nil
        }
        func emphasisEnd(_ marker: Character, length: Int, from start: Int) throws -> Int? {
            var position = start
            while position < chars.count {
                try charge()
                if chars[position] == marker {
                    let runStart = position
                    while position < chars.count && chars[position] == marker { try charge(); position += 1 }
                    if position - runStart >= length && runStart > start && !chars[runStart - 1].isWhitespace && chars[runStart - 1] != "\\" { return position - length }
                } else { position += 1 }
            }
            return nil
        }
        while i < chars.count {
            try charge()
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, chars[i + 1].isASCII, chars[i + 1].isPunctuation || chars[i + 1].isSymbol { pending.append(chars[i + 1]); i += 2; continue }
            if c == "!", i + 1 < chars.count, chars[i + 1] == "[" {
                warn("image")
                if let labelEnd = try match(["]"], from: i + 2), labelEnd + 1 < chars.count, chars[labelEnd + 1] == "(", let end = try match([")"], from: labelEnd + 2) {
                    pending += String(chars[i...end]); i = end + 1; continue
                }
                pending.append(c); i += 1; continue
            }
            if c == "<", let end = try match([">"], from: i + 1) {
                let enclosed = String(chars[i + 1..<end])
                if enclosed.contains("://") || enclosed.contains("@") || captures("^/?[A-Za-z][A-Za-z0-9-]*(?:[ \\t].*)?/?$", enclosed) != nil { warn("HTMLOrAutolink") }
            }
            if c == "|" { warn("tableOrPipe") }
            if c == "`" {
                let length = chars[i...].prefix(while: { $0 == "`" }).count
                if let end = try match(Array(repeating: "`", count: length), from: i + length) {
                    flush(); var code = String(chars[i + length..<end]).replacingOccurrences(of: "\n", with: " ")
                    if code.hasPrefix(" ") && code.hasSuffix(" ") && code.contains(where: { $0 != " " }) { code.removeFirst(); code.removeLast() }
                    var f = formatting; f.fontName = "Courier"
                    result.append(.text(TextRun(code, formatting: f, styleID: "MarkdownCodeSpan"))); i = end + length; continue
                }
                pending += String(repeating: "`", count: length); i += length; continue
            }
            if c == "[", i == 0 || chars[i - 1] != "!", let close = try match(["]"], from: i + 1) {
                if close + 1 < chars.count && chars[close + 1] == "(", let end = try match([")"], from: close + 2) {
                    let destination = String(chars[close + 2..<end])
                    if !destination.isEmpty && !destination.contains(where: { $0.isWhitespace || $0 == "(" }) {
                        flush(); let label = try inline(String(chars[i + 1..<close]), formatting: formatting, depth: depth + 1)
                        result.append(.hyperlink(Hyperlink(target: destination, inlines: label))); i = end + 1; continue
                    }
                    warn("linkDestination")
                    pending += String(chars[i...end]); i = end + 1; continue
                } else {
                    warn("referenceLink")
                    var end = close
                    if close + 1 < chars.count && chars[close + 1] == "[", let referenceEnd = try match(["]"], from: close + 2) { end = referenceEnd }
                    pending += String(chars[i...end]); i = end + 1; continue
                }
            }
            if c == "*" || c == "_" {
                let length = min(3, chars[i...].prefix(while: { $0 == c }).count)
                let intraWord = c == "_" && i > 0 && chars[i - 1].isLetter
                if !intraWord, i + length < chars.count, !chars[i + length].isWhitespace,
                   let end = try emphasisEnd(c, length: length, from: i + length), end > i + length, !chars[end - 1].isWhitespace {
                    flush(); var f = formatting; if length >= 2 { f.bold = true }; if length != 2 { f.italic = true }
                    result += try inline(String(chars[i + length..<end]), formatting: f, depth: depth + 1)
                    i = end + length; continue
                }
            }
            if c == "~", i + 1 < chars.count, chars[i + 1] == "~" { warn("strikethroughExtension") }
            pending.append(c); i += 1
        }
        flush(); return result
    }
}
