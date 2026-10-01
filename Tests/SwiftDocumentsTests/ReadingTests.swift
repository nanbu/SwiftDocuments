import Foundation
import Testing
import SwiftDocuments

@Suite struct ReadingTests {
    @Test(arguments: ["minimal.docx", "stored.docx", "strict.docx"])
    func minimal(_ name: String) throws {
        let result = try Document.read(fixture(name))
        #expect(result.document.sourceFormat == .docx)
        #expect(result.document.plainText == "こんにちは & Swift \tDocuments\n第二行")
        #expect(result.document.paragraphs.count == 1)
        #expect(result.document.sections.first?.pageWidth == 595.3)
        #expect(result.document.sections.first?.margins["top"] == 72)
        #expect(result.warnings.isEmpty)
    }
    @Test func relocatedMainPart() throws {
        #expect(try Document(data: fixture("relocated.docx")).plainText == "別の場所")
    }
    @Test func contentDetectionIgnoresExtension() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture("minimal.docx").write(to: url)
        #expect(try DocumentFormat.detect(contentsOf: url) == .docx)
        #expect(try Document(contentsOf: url).paragraphs.count == 1)
    }
    @Test func convenienceRetainsWarnings() throws {
        let bytes = try fixture("unknown.docx")
        #expect(try Document(data: bytes).readWarnings == Document.read(bytes).warnings)
    }
    @Test func formattingAndStyleToggles() throws {
        let d = try Document(data: fixture("features.docx")), p = try #require(d.paragraphs.first)
        #expect(p.styleID == "Heading")
        #expect(p.formatting.alignment == .center)
        #expect(p.formatting.spacingBefore == 12)
        #expect(p.formatting.spacingAfter == 6)
        #expect(p.formatting.keepWithNext == true)
        #expect(p.runs[0].formatting.fontName == "Default")
        #expect(p.runs[0].formatting.fontSize == 18)
        #expect(p.runs[0].formatting.bold == false) // inherited bold toggled twice
        #expect(p.runs[0].formatting.italic == true)
        #expect(p.runs[1].formatting.italic == false) // character-style toggle
        #expect(p.runs[1].formatting.bold == false) // explicit direct off
        #expect(p.runs[1].formatting.color == "FF0000")
    }
    @Test func numberingDefinitionsAndOverrides() throws {
        let d = try Document(data: fixture("features.docx"))
        #expect(d.paragraphs[0].list == ListReference(id: "4", level: 0))
        #expect(d.numbering["4"]?.levels[0]?.start == 7)
        #expect(d.numbering["4"]?.levels[0]?.format == "decimal")
        #expect(d.numbering["4"]?.levels[0]?.text == "%1.")
    }
    @Test func tablesMergesAndNestedContent() throws {
        let d = try Document(data: fixture("features.docx")), t = try #require(d.tables.first)
        #expect(d.tables.count == 2)
        #expect(t.columnWidths == [75, 75])
        #expect(t.rows[0].isHeader)
        #expect(t.rows[0].cells[0].columnSpan == 2)
        #expect(t.rows[0].cells[0].verticalMerge == .restart)
        #expect(t.rows[0].cells[0].width == 150)
        #expect(t.rows[0].cells[0].shading == "EEEEEE")
        #expect(t.rows[1].cells[0].verticalMerge == .continuation)
        #expect(t.plainText == "結合\n\tセル\n入れ子")
        #expect(d.paragraphs.map(\.plainText).contains("入れ子"))
        #expect(t.properties.contains { $0.contains("tblBorders") })
    }
    @Test func linksAndBookmarks() throws {
        let p = try Document(data: fixture("features.docx")).paragraphs[0]
        let link = try #require(p.inlines.compactMap { if case .hyperlink(let h) = $0 { h } else { nil } }.first)
        #expect(link.target == "https://example.com/guide")
        #expect(link.tooltip == "案内")
        #expect(link.inlines.map(\.plainText).joined() == "リンク")
        let bookmarks = p.inlines.compactMap { if case .bookmark(let b) = $0 { b } else { nil } }
        #expect(bookmarks.count == 2)
        #expect(bookmarks[0].isStart && bookmarks[0].name == "start")
        #expect(!bookmarks[1].isStart)
    }
    @Test func simpleAndComplexFields() throws {
        let p = try Document(data: fixture("features.docx")).paragraphs[1]
        let fields = p.inlines.compactMap { if case .field(let f) = $0 { f } else { nil } }
        #expect(fields.count == 2)
        #expect(fields[0].instruction == " PAGE ")
        #expect(fields[0].isLocked)
        #expect(fields[0].result.map(\.plainText).joined() == "3")
        #expect(fields[1].instruction == "DATE")
        #expect(p.plainText == "32026/01/01")
    }
    @Test func nestedFields() throws {
        let data = makeDocument("<w:p><w:r><w:fldChar w:fldCharType=\"begin\"/><w:instrText> IF </w:instrText><w:fldChar w:fldCharType=\"separate\"/><w:t>A</w:t><w:fldChar w:fldCharType=\"begin\"/><w:instrText> PAGE </w:instrText><w:fldChar w:fldCharType=\"separate\"/><w:t>2</w:t><w:fldChar w:fldCharType=\"end\"/><w:t>B</w:t><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>")
        let d = try Document(data: data)
        #expect(d.plainText == "A2B")
        #expect(d.readWarnings.isEmpty)
    }
    @Test func incompleteFieldWarnsAndKeepsDisplay() throws {
        let data = makeDocument("<w:p><w:r><w:fldChar w:fldCharType=\"begin\"/><w:instrText> PAGE </w:instrText><w:fldChar w:fldCharType=\"separate\"/><w:t>2</w:t></w:r></w:p>")
        let d = try Document(data: data)
        #expect(d.plainText == "2")
        #expect(d.readWarnings.contains { $0.code == .incompleteField })
    }
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func revisionViews(_ view: ReadOptions.RevisionView) throws {
        let d = try Document(data: fixture("features.docx"), options: ReadOptions(revisions: view))
        let p = d.paragraphs[2]
        let expected = view == .final ? "新" : view == .original ? "旧" : "旧新"
        #expect(p.plainText == "変更:\(expected)注釈対象")
        if view == .all {
            #expect(p.runs[1].revision?.kind == .deletion)
            #expect(p.runs[1].revision?.author == "Sample")
            #expect(p.runs[2].revision?.kind == .insertion)
        }
    }
    @Test func relatedStoriesAndReferences() throws {
        let d = try Document(data: fixture("features.docx"))
        #expect(d.stories.first { $0.kind == .header }?.plainText == "ヘッダー")
        #expect(d.stories.first { $0.kind == .footer }?.plainText == "フッター")
        #expect(d.stories.first { $0.kind == .footnote && $0.id == "1" }?.plainText == "脚注")
        #expect(d.stories.first { $0.kind == .endnote }?.plainText == "文末脚注")
        let comment = try #require(d.stories.first { $0.kind == .comment })
        #expect(comment.id == "3" && comment.author == "Sample")
        #expect(comment.plainText == "コメント")
        #expect(!d.plainText.contains("ヘッダー"))
        let refs = d.paragraphs[2].inlines.compactMap { if case .noteReference(let r) = $0 { r } else { nil } }
        #expect(refs.map(\.id) == ["1", "2"])
        let comments = d.paragraphs[2].inlines.compactMap { if case .commentReference(let r) = $0 { r.boundary } else { nil } }
        #expect(comments == [.start, .reference, .end])
    }
    @Test func omitStoriesIsExplicit() throws {
        let d = try Document(data: fixture("features.docx"), options: ReadOptions(includeRelatedStories: false))
        #expect(d.stories.isEmpty)
        #expect(d.readWarnings.filter { $0.code == .storiesOmitted }.count == 5)
    }
    @Test func imagesAreLazyAndTyped() throws {
        let d = try Document(data: fixture("features.docx"))
        let image = try #require(d.paragraphs[3].inlines.compactMap { if case .image(let i) = $0 { i } else { nil } }.first)
        #expect(image.width == 72 && image.height == 36)
        #expect(image.alternativeText == "架空の画像")
        #expect(!image.isFloating)
        let bytes = try d.asset(at: #require(image.assetPath))
        #expect(bytes.starts(with: [0x89, 0x50, 0x4e, 0x47]))
        #expect(throws: DocumentError.missingPart("missing")) { try d.asset(at: "missing") }
    }
    @Test func sectionsAndMetadata() throws {
        let d = try Document(data: fixture("features.docx")), s = try #require(d.sections.first)
        #expect(s.pageWidth == 612 && s.pageHeight == 792)
        #expect(s.columnCount == 2 && s.hasDifferentFirstPage)
        #expect(s.headers["default"] == "word/header.xml")
        #expect(s.footers["default"] == "word/footer.xml")
        #expect(d.metadata.title == "架空の文書")
        #expect(d.metadata.creator == "Sample Author")
        #expect(d.metadata.created == "2026-01-01T00:00:00Z")
        #expect(d.metadata.application == "Fixture Generator")
        #expect(d.metadata.declaredPages == 2)
        #expect(d.metadata.custom["Project"] == "Sample")
    }
    @Test func unknownContentIsRecoverable() throws {
        let d = try Document(data: fixture("unknown.docx"))
        #expect(d.plainText.contains("表示内容"))
        #expect(d.plainText.contains("未知x+y"))
        #expect(d.readWarnings.contains { $0.code == .unsupportedContent })
        #expect(d.readWarnings.contains { $0.code == .uninterpretedFormatting })
        #expect(d.readWarnings.contains { $0.code == .unsupportedPart })
        #expect(try d.asset(at: "word/chunk.html") == Data("<p>html</p>".utf8))
    }
    @Test func warningsAggregate() throws {
        let body = (0..<200).map { _ in "<w:p><w:r><x:widget><x:t>X</x:t></x:widget></w:r></w:p>" }.joined()
        let d = try Document(data: makeDocument(body))
        #expect(d.readWarnings.count == 1)
        #expect(d.readWarnings[0].count == 200)
        #expect(d.blocks.count == 200)
    }
    @Test func macrosRemainOpaque() throws {
        let data = try fixture("macro.docm")
        #expect(try DocumentFormat.detect(data) == .docm)
        let d = try Document(data: data)
        #expect(d.plainText == "マクロは実行しない")
        #expect(d.readWarnings.contains { $0.code == .unsupportedPart })
        #expect(try d.asset(at: "word/vbaProject.bin") == Data("SYNTHETIC-NOT-EXECUTABLE".utf8))
    }
    @Test func scanMatchesWholeRead() throws {
        let data = try fixture("features.docx")
        var texts: [String] = []
        let result = try Document.scan(data) { texts.append($0.plainText) }
        let full = try Document.read(data)
        #expect(texts == full.document.blocks.map(\.plainText))
        #expect(result.blocksRead == full.document.blocks.count)
        #expect(result.document.blocks.isEmpty)
        #expect(result.document.stories.count == full.document.stories.count)
        #expect(result.warnings == full.warnings)
    }
    @Test func callbackFailurePropagates() throws {
        enum ConsumerError: Error { case stop }
        var calls = 0
        #expect(throws: ConsumerError.stop) {
            try Document.scan(makeDocument(paragraph("A") + paragraph("B"))) { _ in calls += 1; throw ConsumerError.stop }
        }
        #expect(calls == 1)
    }
    @Test func inspectionDoesNotParseMainStory() throws {
        var parts = documentParts(paragraph("A")); parts["word/document.xml"] = Data("not xml".utf8)
        let data = makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        let summary = try Document.inspect(data)
        #expect(summary.format == .docx && summary.parts.count == 3)
        #expect(summary.expandedBytes > 0)
        #expect(throws: DocumentError.self) { try Document.read(data) }
    }
    @Test func alternateContentUsesOneFallback() throws {
        let body = "<mc:AlternateContent><mc:Choice Requires=\"x\">\(paragraph("Choice"))</mc:Choice><mc:Fallback>\(paragraph("Fallback"))</mc:Fallback></mc:AlternateContent>"
        #expect(try Document(data: makeDocument(body)).plainText == "Fallback")
    }
    @Test func plainTextBreaks() throws {
        let data = makeDocument("<w:p><w:r><w:t>A</w:t><w:br w:type=\"page\"/><w:t>B</w:t><w:br w:type=\"column\"/><w:t>C</w:t><w:noBreakHyphen/><w:softHyphen/></w:r></w:p>")
        #expect(try Document(data: data).plainText == "A\u{000C}B\nC\u{2011}\u{00AD}")
    }
    @Test func independentProducerOracle() throws {
        struct Oracle: Decodable { let paragraphs: [String]; let tables: [[[String]]]; let header: String; let footer: String }
        let oracle = try JSONDecoder().decode(Oracle.self, from: fixture("producer-oracle.json"))
        let d = try Document(data: fixture("python-docx.docx"))
        let paragraphs = d.blocks.compactMap { if case .paragraph(let p) = $0 { p.plainText } else { nil } }
        #expect(paragraphs == oracle.paragraphs)
        #expect(d.tables.map { $0.rows.map { $0.cells.map(\.plainText) } } == oracle.tables)
        #expect(d.stories.first { $0.kind == .header }?.plainText == oracle.header)
        #expect(d.stories.first { $0.kind == .footer }?.plainText == oracle.footer)
        #expect(d.paragraphs[1].runs.first { $0.text == "太字" }?.formatting.bold == true)
        #expect(d.paragraphs[1].runs.first { $0.text == "太字" }?.formatting.fontSize == 14)
    }
    @Test func sendableConcurrentReads() async throws {
        let data = try fixture("features.docx")
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { try Document(data: data).plainText } }
            var texts: [String] = []; for try await text in group { texts.append(text) }; return texts
        }
        #expect(results.count == 8 && Set(results).count == 1)
    }
    @Test func libreOfficeProducerParity() throws {
        let original = try Document(data: fixture("python-docx.docx"))
        let saved = try Document(data: fixture("libreoffice.docx"))
        #expect(saved.plainText == original.plainText)
        #expect(saved.tables.map(\.plainText) == original.tables.map(\.plainText))
        // Writer emits empty even-page stories as well. Match the default section reference, not ZIP order.
        let section = try #require(saved.sections.first)
        #expect(saved.stories.first { $0.id == section.headers["default"] }?.plainText == "Producer header")
        #expect(saved.stories.first { $0.id == section.footers["default"] }?.plainText == "Producer footer")
        let images = saved.paragraphs.flatMap(\.inlines).compactMap { if case .image(let i) = $0 { i } else { nil } }
        #expect(images.count == 1 && images.first?.width == 18)
        #expect(saved.paragraphs[1].runs.first { $0.text == "太字" }?.formatting.bold == true)
    }
}
