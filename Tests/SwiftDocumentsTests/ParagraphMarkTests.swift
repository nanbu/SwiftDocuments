import Foundation
import Testing
import SwiftDocuments

@Suite struct ParagraphMarkTests {
    private let styles = """
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="20"/><w:lang w:eastAsia="ja-JP"/></w:rPr></w:rPrDefault></w:docDefaults>
    <w:style w:styleId="Body" w:type="paragraph" w:default="1"><w:rPr><w:rFonts w:eastAsia="Source Japanese"/><w:b/></w:rPr></w:style>
    </w:styles>
    """
    @Test func emptyParagraphTypographyAndMarkPropertiesRemainSeparateFromRuns() throws {
        let body = """
        <w:p/><w:p><w:pPr><w:rPr><w:rFonts w:eastAsia="Mark Japanese"/><w:sz w:val="144"/><w:color w:val="FF0000"/></w:rPr></w:pPr>
        <w:r><w:t>本文</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:pPr><w:rPr><w:sz w:val="36"/></w:rPr></w:pPr></w:p></w:tc></w:tr></w:tbl>
        """
        let data = makeDocument(body, extra: ["word/styles.xml": styles], relations: [("s", "styles", "styles.xml", false)])
        let result = try Document.read(data), paragraphs = result.document.paragraphs
        #expect(paragraphs[0].runs.isEmpty && paragraphs[0].plainText.isEmpty)
        #expect(paragraphs[0].defaultTextFormatting.fontNameEastAsia == "Source Japanese")
        #expect(paragraphs[0].defaultTextFormatting.fontSize == 10 && paragraphs[0].paragraphMarkFormatting == nil)
        #expect(paragraphs[1].paragraphMarkFormatting?.fontNameEastAsia == "Mark Japanese")
        #expect(paragraphs[1].paragraphMarkFormatting?.fontSize == 72 && paragraphs[1].paragraphMarkFormatting?.color == "FF0000")
        #expect(paragraphs[1].runs[0].formatting.fontSize == 10 && paragraphs[1].runs[0].formatting.color == nil)
        #expect(paragraphs[1].runs[0].formatting.fontNameEastAsia == "Source Japanese")
        #expect(paragraphs[2].paragraphMarkFormatting?.fontSize == 18 && paragraphs[2].plainText.isEmpty)
        var scanned: [Paragraph] = []
        let scan = try Document.scan(data) { scanned += $0.paragraphs }
        #expect(scanned.map(\.defaultTextFormatting) == paragraphs.map(\.defaultTextFormatting))
        #expect(scanned.map(\.paragraphMarkFormatting) == paragraphs.map(\.paragraphMarkFormatting))
        #expect(result.warnings.isEmpty && scan.warnings == result.warnings)
    }
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func paragraphMarkHistoryUsesItsOwnRevisionView(_ view: ReadOptions.RevisionView) throws {
        let body = """
        <w:p><w:pPr><w:rPr><w:sz w:val="48"/><w:rFonts w:eastAsia="Current Japanese"/>
        <w:rPrChange w:id="mark" w:author="Sample Author"><w:rPr><w:sz w:val="24"/><w:rFonts w:eastAsia="Previous Japanese"/></w:rPr></w:rPrChange>
        </w:rPr></w:pPr><w:r><w:t>本文</w:t></w:r></w:p>
        """
        let data = makeDocument(body, extra: ["word/styles.xml": styles], relations: [("s", "styles", "styles.xml", false)])
        let options = ReadOptions(revisions: view), result = try Document.read(data, options: options)
        let p = try #require(result.document.paragraphs.first)
        #expect(p.paragraphMarkFormatting?.fontSize == (view == .original ? 12 : 24))
        #expect(p.paragraphMarkFormatting?.fontNameEastAsia == (view == .original ? "Previous Japanese" : "Current Japanese"))
        #expect(p.paragraphMarkFormattingChange?.previous.fontSize == 12)
        #expect(p.paragraphMarkFormattingChange?.revision.id == "mark" && p.paragraphMarkFormattingChange?.revision.author == "Sample Author")
        #expect(p.paragraphMarkFormattingChange?.source?.name == "rPrChange")
        #expect(p.runs[0].formatting.fontSize == 10 && p.runs[0].formattingChange == nil)
        #expect(p.plainText == "本文" && result.warnings.isEmpty)
        #expect(try Document.scan(data, options: options) { _ in }.warnings == result.warnings)
    }
    @Test func markExtensionsAndMultipleAnnotationsRemainVisibleWithoutJoining() throws {
        let data = makeDocument("""
        <w:p><w:pPr><w:rPr x:extra="source"><w:ins w:id="1"/><w:del w:id="2"/><x:setting/></w:rPr></w:pPr><w:r><w:t>A</w:t></w:r></w:p>
        <w:p><w:r><w:t>B</w:t></w:r></w:p>
        """)
        let result = try Document.read(data), p = result.document.paragraphs[0]
        #expect(p.paragraphMarkRevisions.map(\.id) == ["1", "2"])
        #expect(p.paragraphMarkFormatting?.rawProperties.contains { $0.contains("extra") } == true)
        #expect(result.document.plainText == "A\nB")
        #expect(Set(result.warnings.map(\.element)).isSuperset(of: ["rPr", "setting", "paragraphMarkRevisions"]))
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
        var copy = p; copy.paragraphMarkRevision = Revision(id: "copy", kind: .insertion)
        copy.defaultTextFormatting.fontNameEastAsia = "Changed"
        #expect(p.paragraphMarkRevisions.count == 2 && copy.paragraphMarkRevisions.count == 1)
        #expect(p.defaultTextFormatting.fontNameEastAsia == nil)
    }
    @Test(arguments: ["<w:r><w:rPr><w:rPrChange w:id=\"1\"/></w:rPr><w:t>A</w:t></w:r>",
                       "<w:pPr><w:pPrChange w:id=\"1\"/></w:pPr>",
                       "<w:pPr><w:rPr><w:rPrChange w:id=\"1\"><w:rPr/><w:rPr/></w:rPrChange></w:rPr></w:pPr>"])
    func malformedFormerPropertiesNeverBecomeUnchangedSuccess(_ content: String) throws {
        #expect(throws: DocumentError.self) { try Document.read(makeDocument("<w:p>\(content)</w:p>")) }
    }
}
