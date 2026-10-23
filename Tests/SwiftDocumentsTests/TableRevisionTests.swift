import Foundation
import Testing
import SwiftDocuments

private func revisionCell(_ text: String, properties: String = "") -> String {
    "<w:tc><w:tcPr>\(properties)</w:tcPr>\(paragraph(text))</w:tc>"
}

@Suite struct TableRevisionTests {
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func formerTableRowCellAndColumnPropertiesFollowRevisionView(_ view: ReadOptions.RevisionView) throws {
        let properties = "<w:tblPr><w:tblW w:type=\"dxa\" w:w=\"2000\"/><w:tblPrChange w:id=\"t\" w:author=\"Sample Author\"><w:tblPr><w:tblW w:type=\"dxa\" w:w=\"4000\"/></w:tblPr></w:tblPrChange></w:tblPr>"
        let grid = "<w:tblGrid><w:gridCol w:w=\"2000\"/><w:tblGridChange w:id=\"g\"><w:tblGrid><w:gridCol w:w=\"1000\"/><w:gridCol/></w:tblGrid></w:tblGridChange></w:tblGrid>"
        let row = "<w:trPr><w:tblHeader/><w:trHeight w:val=\"400\" w:hRule=\"exact\"/><w:trPrChange w:id=\"r\" w:author=\"Sample Author\"><w:trPr><w:trHeight w:val=\"200\" w:hRule=\"atLeast\"/></w:trPr></w:trPrChange></w:trPr>"
        let cell = "<w:gridSpan w:val=\"1\"/><w:tcW w:w=\"2000\" w:type=\"dxa\"/><w:shd w:fill=\"FF0000\"/><w:tcPrChange w:id=\"c\" w:author=\"Sample Author\"><w:tcPr><w:gridSpan w:val=\"2\"/><w:tcW w:w=\"4000\" w:type=\"dxa\"/><w:shd w:fill=\"0000FF\"/></w:tcPr></w:tcPrChange>"
        let data = makeDocument("<w:tbl>\(properties)\(grid)<w:tr>\(row)\(revisionCell("Source", properties: cell))</w:tr></w:tbl>")
        let result = try Document.read(data, options: .init(revisions: view)), table = result.document.tables[0]
        let r = table.rows[0], c = r.cells[0], original = view == .original
        #expect(table.preferredWidth?.value == (original ? 200 : 100))
        #expect(table.columns.count == (original ? 2 : 1) && table.columnWidths == (original ? [50] : [100]))
        #expect(table.columnChange?.previous.count == 2 && table.columnChange?.previous[1].width == nil)
        #expect(r.isHeader == !original && r.height == (original ? 10 : 20) && r.heightRule == (original ? .minimum : .exact))
        #expect(c.columnSpan == (original ? 2 : 1) && c.preferredWidth?.value == (original ? 200 : 100) && c.shading == (original ? "0000FF" : "FF0000"))
        #expect(table.formattingChange?.previous.preferredWidth?.value == 200 && r.formattingChange?.previous.height == 10 && c.formattingChange?.previous.columnSpan == 2)
        #expect(c.formattingChange?.revision.author == "Sample Author" && c.formattingChange?.source?.name == "tcPrChange")
        #expect(try Document.scan(data, options: .init(revisions: view)) { _ in }.warnings == result.warnings)
    }
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func insertedAndDeletedCellsFollowTheSelectedViewAndKeepAttribution(_ view: ReadOptions.RevisionView) throws {
        let body = "<w:tbl><w:tr>\(revisionCell("base"))\(revisionCell("inserted", properties: "<w:cellIns w:id=\"1\" w:author=\"Sample Author\"/>"))\(revisionCell("deleted", properties: "<w:cellDel w:id=\"2\" w:author=\"Sample Author\"/>"))</w:tr></w:tbl>"
        let document = try Document(data: makeDocument(body), options: .init(revisions: view))
        let cells = document.tables[0].rows[0].cells
        #expect(cells.map(\.plainText) == (view == .final ? ["base", "inserted"] : view == .original ? ["base", "deleted"] : ["base", "inserted", "deleted"]))
        #expect(cells[1].revisions[0].author == "Sample Author")
        #expect(cells[1].revisions[0].kind == (view == .original ? .deletion : .insertion))
    }
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func trackedMergeUsesContAndRestWithoutInventingAMergeStart(_ view: ReadOptions.RevisionView) throws {
        let merged = "<w:cellMerge w:id=\"1\" w:vMerge=\"cont\" w:vMergeOrig=\"rest\"/>"
        let split = "<w:vMerge/><w:cellMerge w:id=\"2\" w:vMerge=\"rest\" w:vMergeOrig=\"cont\"/>"
        let document = try Document(data: makeDocument("<w:tbl><w:tr>\(revisionCell("merge", properties: merged))\(revisionCell("split", properties: split))</w:tr></w:tbl>"), options: .init(revisions: view))
        let cells = document.tables[0].rows[0].cells
        #expect(cells[0].verticalMerge == (view == .original ? nil : .continuation))
        #expect(cells[1].verticalMerge == (view == .original ? .continuation : nil))
        #expect(cells[0].mergeChange?.wasMergedWithPrevious == false && cells[0].mergeChange?.isMergedWithPrevious == true)
        #expect(cells[1].mergeChange?.wasMergedWithPrevious == true && cells[1].mergeChange?.isMergedWithPrevious == false)
    }
    @Test func wrapperRevisionMetadataAndExtensionsRemainAvailable() throws {
        let body = "<w:tbl><w:ins w:id=\"r\" w:author=\"Sample Author\" x:time=\"source-time\"><w:tr><w:ins w:id=\"c\" w:author=\"Sample Author\">\(revisionCell("Source"))</w:ins></w:tr></w:ins></w:tbl>"
        let document = try Document(data: makeDocument(body), options: .init(revisions: .all))
        let row = document.tables[0].rows[0]
        #expect(row.revisions[0].id == "r" && row.revisions[0].sourceAttributes["urn:foreign|time"] == "source-time")
        #expect(row.cells[0].revisions[0].id == "c")
        #expect(document.readWarnings.contains { $0.element == "ins" && $0.code == .uninterpretedFormatting })
    }
    @Test(arguments: ["0", "-1", "invalid"])
    func invalidSpansDoNotBecomeOne(_ value: String) throws {
        #expect(throws: DocumentError.self) { try Document.read(makeDocument("<w:tbl><w:tr>\(revisionCell("Source", properties: "<w:gridSpan w:val=\"\(value)\"/>"))</w:tr></w:tbl>")) }
    }
    @Test func missingPreviousPropertiesDoNotBecomeEmptyFormatting() throws {
        let body = "<w:tbl><w:tr><w:trPr><w:trPrChange w:id=\"1\"/></w:trPr>\(revisionCell("Source"))</w:tr></w:tbl>"
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(body)) }
    }
}
