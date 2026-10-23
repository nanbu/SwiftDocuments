import Foundation
import Testing
import SwiftDocuments

@Suite struct MarkdownTests {
    func read(_ text: String, options: ReadOptions = .init()) throws -> ReadResult { try Document.read(Data(text.utf8), format: .markdown, options: options) }
    @Test func markdownHeadingsParagraphsAndUnicode() throws {
        let result = try read("\u{feff}# 日本語 😀\r\n\r\nSecond\rline\r\n\r\nSubtitle\r\n---\r\n\r\n###### Last ####\n")
        #expect(result.document.sourceFormat == .markdown)
        #expect(result.document.blocks.map(\.plainText) == ["日本語 😀", "Second line", "Subtitle", "Last"])
        #expect(result.document.paragraphs.map { $0.formatting.outlineLevel } == [0, nil, 1, 5])
        #expect(result.warnings.isEmpty)
        #expect(try read("Literal <&> and a < b").warnings.isEmpty)
        #expect(try read("").document.blocks.isEmpty)
        #expect(try read(" \n\t\n").document.blocks.isEmpty)
    }
    @Test func markdownEmphasisCodeLinksAndEscapes() throws {
        let result = try read("**bold** *italic* ***both*** `a * b` [日本語](https://example.invalid/a?x=1&y=2) \\*literal\\*")
        let p = try #require(result.document.paragraphs.first)
        #expect(p.plainText == "bold italic both a * b 日本語 *literal*")
        #expect(p.runs.first { $0.text == "bold" }?.formatting.bold == true)
        #expect(p.runs.first { $0.text == "italic" }?.formatting.italic == true)
        #expect(p.runs.first { $0.text == "both" }?.formatting.bold == true)
        #expect(p.runs.first { $0.text == "both" }?.formatting.italic == true)
        #expect(p.runs.first { $0.text == "a * b" }?.styleID == "MarkdownCodeSpan")
        #expect(p.inlines.contains { if case .hyperlink(let h) = $0 { h.target == "https://example.invalid/a?x=1&y=2" } else { false } })
        #expect(result.warnings.isEmpty)
        #expect(try read("snake_case_name *unclosed").document.plainText == "snake_case_name *unclosed")
    }
    @Test func markdownNestedEmphasisAndLiteralImageSource() throws {
        let result = try read("**bold *italic*** and *italic **bold*** ![**literal**](https://example.invalid/image)")
        #expect(result.document.plainText == "bold italic and italic bold ![**literal**](https://example.invalid/image)")
        #expect(result.document.paragraphs[0].runs.filter { $0.formatting.bold == true && $0.formatting.italic == true }.map(\.text) == ["italic", "bold"])
        #expect(result.warnings.map(\.element) == ["image"])
        let literal = "[**reference**][id] [*invalid*](target with spaces)"
        #expect(try read(literal).document.plainText == literal)
    }
    @Test func markdownListsAndHardBreaks() throws {
        let result = try read("- One\n- **Two**\n\n3. Three\n4. Four\n\nfirst  \nsecond\\\nthird")
        let p = result.document.paragraphs
        #expect(p.count == 5 && p.last?.plainText == "first\nsecond\nthird")
        #expect(p[0].list == p[1].list && p[0].list?.id != p[2].list?.id)
        let id = try #require(p[2].list?.id)
        #expect(result.document.numbering[id]?.levels[0]?.start == 3)
        #expect(result.document.numbering[id]?.levels[0]?.format == "decimal")
    }
    @Test func markdownFencesRetainLiteralCode() throws {
        let result = try read("~~~\n**literal**\n日本語 😀\n~~~\n\n````\nx```y\n````\n\n```swift\nlet x = 1\n")
        #expect(result.document.blocks.map(\.plainText) == ["**literal**\n日本語 😀", "x```y", "let x = 1"])
        #expect(result.document.paragraphs.allSatisfy { $0.styleID == "MarkdownCode" && $0.runs.first?.formatting.fontName == "Courier" })
        #expect(result.warnings.map(\.element) == ["codeLanguage"])
    }
    @Test func markdownUnsupportedSourceAndScanParity() throws {
        let source = "> Quote\n\n---\n\n| A | B |\n\n<script>literal</script>\n\n![alt](https://example.invalid/image) [ref][id]\n\n[id]: /target\n\n    nested"
        let data = Data(source.utf8), read = try read(source)
        #expect(read.document.plainText.contains("![alt](https://example.invalid/image) [ref][id]"))
        #expect(Set(read.warnings.map(\.element)).isSuperset(of: ["blockQuote", "thematicBreak", "tableOrPipe", "HTML", "image", "referenceLink", "indentedBlock"]))
        var blocks: [String] = []
        let scanned = try Document.scan(data, format: .markdown) { blocks.append($0.plainText) }
        #expect(blocks == read.document.blocks.map(\.plainText) && scanned.warnings == read.warnings)
        #expect(scanned.document.blocks.isEmpty && scanned.blocksRead == blocks.count)
        enum Stop: Error { case requested }
        #expect(throws: Stop.requested) { try Document.scan(data, format: .markdown) { _ in throw Stop.requested } }
    }
    @Test func markdownEncodingLimitsAndNoTextGuessing() throws {
        for data in [Data([0xff]), Data("a\0b".utf8), Data([0xff, 0xfe, 0x41, 0])] {
            #expect(throws: DocumentError.self) { try Document.read(data, format: .markdown) }
            #expect(throws: DocumentError.self) { try Document.inspect(data, format: .markdown) }
        }
        #expect(throws: DocumentError.unknownFormat) { try Document.read(Data("# Text".utf8)) }
        #expect(throws: DocumentError.unknownFormat) { try DocumentFormat.detect(Data("# Text".utf8)) }
        #expect(throws: DocumentError.self) { try read("12345", options: .init(limits: .init(maxPartBytes: 4))) }
        #expect(throws: DocumentError.self) { try read("12345", options: .init(limits: .init(maxExpandedBytes: 4))) }
        #expect(throws: DocumentError.self) { try read("**nested**", options: .init(limits: .init(maxXMLDepth: 1))) }
        #expect(throws: DocumentError.self) { try read(String(repeating: "*a", count: 100), options: .init(limits: .init(maxXMLNodes: 30))) }
        let summary = try Document.inspect(Data("# Text".utf8), format: .markdown)
        #expect(summary.format == .markdown && summary.parts.isEmpty && summary.expandedBytes == 0)
    }
    @Test func markdownURLSelectionAndPackageSignaturePrecedence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fiction.MARKDOWN")
        try Data("# Sample".utf8).write(to: url)
        #expect(try Document(contentsOf: url).plainText == "Sample")
        #expect(try Document.inspect(contentsOf: url).format == .markdown)
        #expect(try Document.scan(contentsOf: url) { _ in }.blocksRead == 1)
        try fixture("minimal.docx").write(to: url)
        #expect(try Document.read(contentsOf: url).document.sourceFormat == .docx)
        #expect(try DocumentFormat.detect(contentsOf: url) == .docx)
        #expect(DocumentFormat.markdown.fileExtension == "md" && DocumentFormat(fileExtension: "MD") == .markdown)
        #expect(throws: DocumentError.noCodec(.markdown)) { try CodecSet([.docx]).read(Data(), format: .markdown) }
    }
    @Test func markdownAsyncAndCancellation() async throws {
        let result = try await Document.read(Data("# Async".utf8), format: .markdown)
        #expect(result.document.plainText == "Async")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Document.read(Data("# Cancelled".utf8), format: .markdown)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
