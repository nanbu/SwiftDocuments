import Foundation
import Testing
import SwiftDocuments

@Suite struct FormattingTests {
    @Test func eastAsianAndComplexScriptFormatting() throws {
        let d = try Document(data: makeDocument("<w:p><w:r><w:rPr><w:rFonts w:ascii=\"Latin\" w:eastAsia=\"日本語\" w:cs=\"Arabic\"/><w:sz w:val=\"24\"/><w:szCs w:val=\"28\"/><w:bCs/><w:iCs w:val=\"0\"/><w:lang w:val=\"en-US\" w:eastAsia=\"ja-JP\" w:bidi=\"ar-SA\"/><w:spacing w:val=\"20\"/><w:kern w:val=\"16\"/><w:vertAlign w:val=\"superscript\"/></w:rPr><w:t>文字</w:t></w:r></w:p>"))
        let f = d.paragraphs[0].runs[0].formatting
        #expect(f.fontNameEastAsia == "日本語" && f.fontNameComplexScript == "Arabic")
        #expect(f.fontSizeComplexScript == 14 && f.boldComplexScript == true && f.italicComplexScript == false)
        #expect(f.languageEastAsia == "ja-JP" && f.languageComplexScript == "ar-SA")
        #expect(f.characterSpacing == 1 && f.kerning == 8)
        #expect(f.verticalAlignment == .superscript)
        #expect(d.readWarnings.isEmpty)
    }
    @Test func paragraphPaginationProperties() throws {
        let d = try Document(data: makeDocument("<w:p><w:pPr><w:widowControl w:val=\"0\"/><w:contextualSpacing/><w:suppressAutoHyphens/><w:spacing w:line=\"360\" w:lineRule=\"auto\"/><w:ind w:start=\"720\" w:end=\"360\" w:hanging=\"240\"/></w:pPr><w:r><w:t>A</w:t></w:r></w:p>"))
        let f = d.paragraphs[0].formatting
        #expect(f.widowControl == false && f.contextualSpacing == true && f.suppressAutoHyphens == true)
        #expect(f.lineSpacingRule == .multiple && f.lineSpacing == 1.5)
        #expect(f.indentLeft == 36 && f.indentRight == 18 && f.firstLineIndent == -12)
    }
    @Test func directSpacingPreservesInheritedLineRule() throws {
        let styles = "<w:styles xmlns:w=\"\(wordNS)\"><w:style w:styleId=\"A\" w:type=\"paragraph\"><w:pPr><w:spacing w:line=\"280\" w:lineRule=\"exact\"/></w:pPr></w:style></w:styles>"
        let d = try Document(data: makeDocument("<w:p><w:pPr><w:pStyle w:val=\"A\"/><w:spacing w:before=\"240\"/></w:pPr></w:p>", extra: ["word/styles.xml": styles], relations: [("s", "styles", "styles.xml", false)]))
        #expect(d.paragraphs[0].formatting.lineSpacingRule == .exact)
        #expect(d.paragraphs[0].formatting.lineSpacing == 14)
    }
    @Test func unknownFormattingStaysRaw() throws {
        let d = try Document(data: makeDocument("<w:p><w:pPr><w:jc w:val=\"futureAlignment\"/></w:pPr><w:r><w:rPr><w:color w:val=\"123456\" w:themeTint=\"80\"/></w:rPr><w:t>A</w:t></w:r></w:p>"))
        #expect(d.paragraphs[0].formatting.rawProperties.count == 1)
        #expect(d.paragraphs[0].runs[0].formatting.rawProperties.count == 1)
        #expect(d.readWarnings.count == 2)
    }
    @Test func sectionHeadersInherit() throws {
        let header = "<w:hdr xmlns:w=\"\(wordNS)\">\(paragraph("Header"))</w:hdr>"
        let body = "<w:p><w:pPr><w:sectPr><w:headerReference w:type=\"default\" r:id=\"h\"/></w:sectPr></w:pPr></w:p>" + paragraph("Second") + "<w:sectPr/>"
        let d = try Document(data: makeDocument(body, extra: ["word/header.xml": header], relations: [("h", "header", "header.xml", false)]))
        #expect(d.sections.count == 2)
        #expect(d.sections[0].headers == d.sections[1].headers)
    }
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func trackedTableRows(_ view: ReadOptions.RevisionView) throws {
        let body = "<w:tbl><w:tr><w:trPr><w:del w:id=\"1\"/></w:trPr><w:tc>\(paragraph("Old"))</w:tc></w:tr><w:tr><w:trPr><w:ins w:id=\"2\"/></w:trPr><w:tc>\(paragraph("New"))</w:tc></w:tr></w:tbl>"
        let d = try Document(data: makeDocument(body), options: ReadOptions(revisions: view))
        #expect(d.plainText == (view == .final ? "New" : view == .original ? "Old" : "Old\nNew"))
    }
    @Test func unknownMixedWhitespaceSurvivesRaw() throws {
        let d = try Document(data: makeDocument("<x:widget><x:t>A</x:t> <x:t>B</x:t></x:widget>"))
        guard case .unsupported(let u) = d.blocks[0] else { Issue.record("Expected unsupported block"); return }
        #expect(u.rawXML.contains("</n:t> <n:t"))
    }
    @Test func missingNoteAndCommentReferencesWarn() throws {
        let data = makeDocument("<w:p><w:r><w:footnoteReference w:id=\"1\"/><w:footnoteReference w:id=\"1\"/><w:commentReference w:id=\"9\"/></w:r></w:p>")
        let result = try Document.read(data)
        #expect(result.warnings.filter { $0.code == .invalidReference }.count == 2)
        #expect(result.warnings.first { $0.element == "footnoteReference" }?.count == 2)
        var count = 0; let scanned = try Document.scan(data) { _ in count += 1 }
        #expect(count == 1 && scanned.warnings == result.warnings)
    }
}
