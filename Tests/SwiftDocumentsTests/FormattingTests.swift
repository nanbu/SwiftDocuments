import Foundation
import Testing
import SwiftDocuments

@Suite struct FormattingTests {
    @Test func invalidBooleanFormattingStaysRawInsteadOfBecomingTrue() throws {
        let d = try Document(data: makeDocument("<w:p><w:pPr><w:keepNext w:val=\"unknown\"/></w:pPr><w:r><w:rPr><w:b w:val=\"unknown\"/></w:rPr><w:t>Source</w:t></w:r></w:p>"))
        #expect(d.paragraphs[0].formatting.keepWithNext == nil && d.paragraphs[0].runs[0].formatting.bold == nil)
        #expect(Set(d.readWarnings.map(\.element)).isSuperset(of: ["keepNext", "b"]))
    }
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
    @Test func missingStyleWarningsIdentifyEachReferringPart() throws {
        let styled = "<w:p><w:pPr><w:pStyle w:val=\"missingParagraph\"/></w:pPr><w:r><w:rPr><w:rStyle w:val=\"missingCharacter\"/><w:b/></w:rPr><w:t>Kept</w:t></w:r></w:p>"
        let header = "<w:hdr xmlns:w=\"\(wordNS)\">\(styled)</w:hdr>"
        let data = makeDocument(styled + styled, extra: ["word/header.xml": header],
                                relations: [("header", "header", "header.xml", false)])
        let result = try Document.read(data)
        #expect(result.document.plainText == "Kept\nKept")
        #expect(result.document.paragraphs.allSatisfy { $0.styleID == "missingParagraph" })
        #expect(result.document.paragraphs.flatMap(\.runs).allSatisfy { $0.styleID == "missingCharacter" && $0.formatting.bold == true })
        let warnings = result.warnings.filter { $0.code == .invalidReference }
        #expect(warnings.count == 4)
        for element in ["pStyle", "rStyle"] {
            #expect(warnings.first { $0.part == "word/document.xml" && $0.element == element }?.count == 2)
            #expect(warnings.first { $0.part == "word/header.xml" && $0.element == element }?.count == 1)
        }
        let scan = try Document.scan(data) { _ in }
        #expect(scan.warnings == result.warnings)
        let omitted = try Document.read(data, options: .init(includeRelatedStories: false))
        #expect(!omitted.warnings.contains { $0.code == .invalidReference && $0.part == "word/header.xml" })
    }
    @Test func missingBaseStyleWarnsOncePerDeclarationAndRetainsFormatting() throws {
        let styles = "<w:styles xmlns:w=\"\(wordNS)\"><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val=\"24\"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:styleId=\"Base\"><w:basedOn w:val=\"missing\"/><w:rPr><w:b/></w:rPr></w:style><w:style w:styleId=\"Child\"><w:basedOn w:val=\"Base\"/><w:rPr><w:i/></w:rPr></w:style></w:styles>"
        let styled = "<w:p><w:pPr><w:pStyle w:val=\"Child\"/></w:pPr><w:r><w:t>Kept</w:t></w:r></w:p>"
        let result = try Document.read(makeDocument(styled + styled, extra: ["word/styles.xml": styles],
                                      relations: [("styles", "styles", "styles.xml", false)]))
        let warning = try #require(result.warnings.first { $0.code == .invalidReference })
        #expect(warning.part == "word/styles.xml" && warning.element == "basedOn" && warning.count == 1)
        #expect(result.warnings.filter { $0.code == .invalidReference }.count == 1)
        let formatting = try #require(result.document.paragraphs.first?.runs.first?.formatting)
        #expect(formatting.bold == true && formatting.italic == true && formatting.fontSize == 12)
        #expect(result.document.styles["Base"]?.basedOn == "missing")
    }
}
