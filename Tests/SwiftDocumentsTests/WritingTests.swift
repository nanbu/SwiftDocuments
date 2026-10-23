import Foundation
import Testing
import SwiftDocuments

private func basicWritingDocument() -> Document {
    var document = Document(), p = Paragraph(), f = TextFormatting()
    f.bold = true; f.italic = true; f.strike = false; f.underline = "double"
    f.fontName = "Sample Serif"; f.fontSize = 12.5; f.color = "1234AB"
    p.formatting.alignment = .center; p.formatting.outlineLevel = 1
    p.inlines = [.text(TextRun("日本語 😀 <&\"'", formatting: f)), .tab, .text(TextRun("Tail")), .lineBreak(.line), .hyperlink(Hyperlink(target: "https://example.invalid/?a=1&b=2", inlines: [.text(TextRun("Link"))]))]
    document.blocks = [.paragraph(p)]
    var list = Paragraph(); list.inlines = [.text(TextRun("Item"))]; list.list = .init(id: "list-a")
    document.numbering["list-a"] = .init(id: "list-a", abstractID: "source", levels: [0: .init(level: 0, start: 3)])
    document.blocks += [.paragraph(list), .paragraph(list)]
    var table = Table()
    for texts in [["A", "B"], ["C", "D"]] {
        var row = TableRow()
        for text in texts { var cell = TableCell(), p = Paragraph(); p.inlines = [.text(TextRun(text))]; cell.blocks = [.paragraph(p)]; row.cells.append(cell) }
        table.rows.append(row)
    }
    document.blocks.append(.table(table))
    var empty = Paragraph(); empty.defaultTextFormatting.bold = true
    document.blocks.append(.paragraph(empty))
    document.metadata.title = "Fictional <Title>"; document.metadata.creator = "Sample Author"
    document.metadata.subject = "Subject"; document.metadata.description = "Description"; document.metadata.keywords = "one"
    return document
}
@Suite struct WritingTests {
    @Test(arguments: [DocumentFormat.docx, .docm, .odt]) func basicWritingRoundTrip(format: DocumentFormat) throws {
        let source = basicWritingDocument(), result = try source.write(as: format, options: .init(strict: true))
        #expect(result.warnings.isEmpty)
        #expect(try DocumentFormat.detect(result.data) == format)
        let doc = try Document(data: result.data)
        #expect(doc.blocks.map(\.plainText) == source.blocks.map(\.plainText))
        #expect(doc.paragraphs[0].formatting.alignment == .center && doc.paragraphs[0].formatting.outlineLevel == 1)
        let run = try #require(doc.paragraphs[0].runs.first)
        #expect(run.formatting.bold == true && run.formatting.italic == true && run.formatting.strike == false)
        #expect(run.formatting.fontSize == 12.5 && run.formatting.color == "1234AB")
        #expect(run.formatting.fontName == "Sample Serif" && run.formatting.underline == "double")
        #expect(doc.paragraphs.last?.defaultTextFormatting.bold == true)
        #expect(doc.tables.count == 1 && doc.tables[0].rows[1].cells[1].plainText == "D")
        #expect(doc.paragraphs[1].list != nil)
        let list = try #require(doc.paragraphs[1].list)
        #expect(doc.numbering[list.id]?.levels[list.level]?.start == 3)
        #expect(doc.metadata.title == source.metadata.title && doc.metadata.creator == "Sample Author")
        #expect(doc.metadata.description == "Description" && doc.metadata.subject == "Subject" && doc.metadata.keywords == "one")
        #expect(doc.paragraphs[0].inlines.contains { if case .hyperlink(let h) = $0 { h.target == "https://example.invalid/?a=1&b=2" } else { false } })
    }
    @Test func writingODTMimetypeAndZIPDeterminism() throws {
        let source = basicWritingDocument()
        for format in [DocumentFormat.docx, .docm, .odt, .pages] {
            for compress in [true, false] {
                let a = try source.write(as: format, options: .init(compress: compress)), b = try source.write(as: format, options: .init(compress: compress))
                #expect(a.data == b.data && a.warnings == b.warnings)
                #expect(try DocumentFormat.detect(a.data) == format)
                if format == .odt {
                    #expect(a.data[8] == 0 && a.data[9] == 0) // first local header compression
                    #expect(a.data[28] == 0 && a.data[29] == 0) // no extra data
                    #expect(String(decoding: a.data[30..<38], as: UTF8.self) == "mimetype")
                    #expect(String(decoding: a.data[38..<77], as: UTF8.self) == "application/vnd.oasis.opendocument.text")
                }
            }
        }
    }
    @Test(arguments: [DocumentFormat.docx, .docm, .odt, .pages]) func writingEmptyDocument(format: DocumentFormat) throws {
        let result = try Document().write(as: format, options: .init(strict: true))
        #expect(result.warnings.isEmpty)
        #expect(try Document(data: result.data).plainText.isEmpty)
    }
    @Test func writingPagesUnicodeParagraphsAndControls() throws {
        var doc = Document(), p = Paragraph(), empty = Paragraph()
        p.inlines = [.text(TextRun("A😀B 日本語")), .tab, .text(TextRun("T")), .lineBreak(.line), .text(TextRun("L")), .lineBreak(.page), .text(TextRun("P"))]
        empty.inlines = []
        doc.blocks = [.paragraph(p), .paragraph(empty), .paragraph(p)]
        let result = try doc.write(as: .pages, options: .init(strict: true))
        #expect(result.warnings.isEmpty)
        let read = try Document(data: result.data)
        #expect(read.blocks.map(\.plainText) == doc.blocks.map(\.plainText))
        #expect(read.paragraphs.count == 3)
        let large = String(repeating: "😀日本語", count: 15_000)
        p.inlines = [.text(TextRun(large))]; doc.blocks = [.paragraph(p)]
        #expect(try Document(data: doc.write(as: .pages).data).plainText == large)
    }
    @Test func writingNestedTablesAndWhitespace() throws {
        var source = basicWritingDocument(), p = Paragraph()
        p.inlines = [.text(TextRun("  Leading  repeated\tTab\nLine <&>  "))]
        var cell = TableCell(); cell.blocks = [source.blocks[3], .paragraph(Paragraph())]
        var row = TableRow(); row.cells = [cell]
        var table = Table(); table.rows = [row]
        source = Document(); source.blocks = [.paragraph(p), .table(table)]
        for format in [DocumentFormat.docx, .odt] {
            let read = try Document(data: source.write(as: format).data)
            #expect(read.blocks.map(\.plainText) == source.blocks.map(\.plainText))
            #expect(read.tables.count == 2)
        }
    }
    @Test func writingWordAddsAndDiagnosesRequiredCellTerminator() throws {
        var cell = TableCell(); cell.blocks = [basicWritingDocument().blocks[3]]
        var row = TableRow(); row.cells = [cell]
        var table = Table(); table.rows = [row]
        var doc = Document(); doc.blocks = [.table(table)]
        let result = try doc.write(as: .docx)
        #expect(result.warnings.map(\.element) == ["cellTerminator"])
        let read = try Document(data: result.data)
        #expect(read.tables[0].rows[0].cells[0].blocks.count == 2)
        #expect(read.plainText == "A\tB\nC\tD\n")
        #expect(throws: DocumentError.writingLoss(result.warnings)) { try doc.write(as: .docx, options: .init(strict: true)) }
    }
    @Test func writingLossWarningsAndStrictDestinationSafety() throws {
        var doc = basicWritingDocument()
        var p = Paragraph(); p.inlines = [.text(TextRun("Value"))]; p.defaultTextFormatting.hidden = true
        doc.blocks.append(.paragraph(p)); doc.metadata.custom["unwritten"] = "value"
        let ordinary = try doc.write(as: .docx)
        #expect(ordinary.warnings.contains { $0.element == "textFormatting" })
        #expect(ordinary.warnings.contains { $0.element == "metadata" })
        #expect(throws: DocumentError.writingLoss(ordinary.warnings)) { try doc.write(as: .docx, options: .init(strict: true)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        let original = Data("existing".utf8); try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: DocumentError.self) { try doc.write(to: url, options: .init(strict: true)) }
        #expect(try Data(contentsOf: url) == original)
        var invalid = Paragraph(); invalid.inlines = [.text(TextRun("bad\0text"))]; doc.blocks = [.paragraph(invalid)]
        #expect(throws: DocumentError.self) { try doc.write(to: url) }
        #expect(try Data(contentsOf: url) == original)
    }
    @Test func writingPagesLossesAndMacroOmission() throws {
        let result = try basicWritingDocument().write(as: .pages)
        #expect(Set(result.warnings.map(\.element)).isSuperset(of: ["table", "list", "hyperlink", "metadata", "textFormatting"]))
        let macro = try Document(data: fixture("macro.docm"))
        let written = try macro.write(as: .docm)
        #expect(written.warnings.contains { $0.code == .sourcePartsOmitted })
        #expect(try Document.inspect(written.data).parts.allSatisfy { !$0.path.lowercased().contains("vba") })
        #expect(throws: DocumentError.self) { try macro.write(as: .docm, options: .init(strict: true)) }
    }
    @Test func writingFormatSelectionAndReadOnlyCodecCompatibility() throws {
        let doc = Document()
        #expect(try DocumentFormat.detect(doc.write().data) == .docx)
        #expect(throws: DocumentError.writingNotSupported(.markdown)) { try doc.write(as: .markdown) }
        #expect(throws: DocumentError.noCodec(.odt)) { try CodecSet([.docx]).write(doc, as: .odt) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".odt")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try DocumentFormat.detect(doc.write(to: url).data) == .odt)
        #expect(try DocumentFormat.detect(doc.write(to: url, as: .docm).data) == .docm)
        #expect(try Data(contentsOf: url) == doc.write(as: .docm).data)
        #expect(throws: DocumentError.self) { try doc.write(to: URL(string: "https://example.invalid/out.docx")!) }
        var imported = Document(); imported.sourceFormat = .odt
        #expect(try DocumentFormat.detect(imported.write().data) == .odt)
    }
    @Test func writingNestedLinksAndDeepCachedFieldsAreBounded() throws {
        var p = Paragraph(), doc = Document()
        let inner = Inline.hyperlink(Hyperlink(target: "https://example.invalid/inner", inlines: [.text(TextRun("Nested"))]))
        p.inlines = [.hyperlink(Hyperlink(target: "https://example.invalid/outer", inlines: [inner]))]
        doc.blocks = [.paragraph(p)]
        for format in [DocumentFormat.docx, .odt] {
            let result = try doc.write(as: format)
            #expect(result.warnings.map(\.element) == ["nestedHyperlink"])
            #expect(try Document(data: result.data).plainText == "Nested")
        }
        var inline = Inline.text(TextRun("Deep"))
        for _ in 0..<140 { inline = .field(Field(instruction: "cached", result: [inline])) }
        p.inlines = [inline]; doc.blocks = [.paragraph(p)]
        #expect(throws: DocumentError.self) { try doc.write(as: .docx) }
        var supported = Inline.text(TextRun("Within limit"))
        for _ in 0..<31 { supported = .field(Field(instruction: "cached", result: [supported])) }
        p.inlines = [supported]; doc.blocks = [.paragraph(p)]
        for format in [DocumentFormat.docx, .odt, .pages] { #expect(try !doc.write(as: format).data.isEmpty) }
        p.inlines = [.text(TextRun("Leaf"))]
        var block = Block.paragraph(p)
        for level in 1...32 {
            var cell = TableCell(); cell.blocks = [block, .paragraph(Paragraph())]
            var row = TableRow(); row.cells = [cell]
            var table = Table(); table.rows = [row]
            block = .table(table); doc.blocks = [block]
            if level == 31 {
                for format in [DocumentFormat.docx, .odt, .pages] { #expect(try !doc.write(as: format).data.isEmpty) }
            }
            if level == 32 { #expect(throws: DocumentError.self) { try doc.write(as: .docx) } }
        }
    }
    @Test func writingInvalidValuesAreRejected() throws {
        for size in [Double.nan, .infinity, -1, 0, 12.25, 2000] {
            var doc = Document(), p = Paragraph(), f = TextFormatting(); f.fontSize = size
            p.inlines = [.text(TextRun("size", formatting: f))]; doc.blocks = [.paragraph(p)]
            for format in [DocumentFormat.docx, .odt] { #expect(throws: DocumentError.self) { try doc.write(as: format) } }
        }
        var doc = Document(), p = Paragraph(); p.formatting.outlineLevel = 99; doc.blocks = [.paragraph(p)]
        #expect(throws: DocumentError.self) { try doc.write(as: .docx) }
    }
    @Test func writingAsyncAndCancellationPreserveDestination() async throws {
        let doc = Document(), output = try await doc.write(as: .odt)
        #expect(try await Document.inspect(output.data).format == .odt)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try Data("original".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await doc.write(to: url)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: url) == Data("original".utf8))
    }
}
