import Foundation
import Testing
import SwiftDocuments

private func pagesRanges(_ values: [(UInt64, UInt64?)]) -> Data {
    values.reduce(into: Data()) { result, entry in
        result += pbBytes(1, pbInt(1, entry.0) + (entry.1.map { pbRef(2, $0) } ?? Data()))
    }
}
private func pagesLanguages(_ values: [(UInt64, String?)]) -> Data {
    values.reduce(into: Data()) { result, entry in
        result += pbBytes(1, pbInt(1, entry.0) + (entry.1.map { pbText(2, $0) } ?? Data()))
    }
}

@Suite struct PagesFormattingTests {
    @Test func pagesLanguagesFollowUTF16RangesAndResetToStyleDefaults() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        let style = iwaArchive(20, 2022, pbBytes(11, pbText(9, "en-US")))
        let text = "A😀日本\nZ", languages = pagesLanguages([(1, "ja-JP"), (5, nil), (7, "fr-FR")])
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, text) + pbBytes(5, pagesRanges([(0, 20)])) + pbBytes(19, languages))
        let data = pagesPackage(root + style + body, chunkSize: 23), result = try Document.read(data)
        let paragraphs = result.document.paragraphs
        #expect(result.document.plainText == text)
        #expect(paragraphs[0].runs.map(\.text) == ["A", "😀日本"])
        #expect(paragraphs[0].runs.map { $0.formatting.language } == ["en-US", "ja-JP"])
        #expect(paragraphs[1].runs[0].formatting.language == "en-US")
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }

    @Test func pagesNullStyleDeclarationsClearInheritedAndParagraphDefaults() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        let color = pbInt(1, 1) + pbFloat(3, 1) + pbFloat(4, 0) + pbFloat(5, 0)
        let base = iwaArchive(20, 2021, pbBytes(11, pbText(5, "Sample Serif") + pbText(9, "ar") + pbBytes(7, color) + pbInt(35, 1) + pbText(37, "dot")))
        let clears = iwaArchive(21, 2021, pbBytes(1, pbRef(3, 20)) + pbBytes(11, pbInt(4, 1) + pbInt(6, 1) + pbInt(8, 1) + pbInt(36, 1) + pbInt(35, UInt64.max)))
        let inheritedClears = iwaArchive(22, 2021, pbBytes(1, pbRef(3, 21)) + pbBytes(11, pbInt(1, 1)))
        let restored = iwaArchive(23, 2021, pbBytes(1, pbRef(3, 22)) + pbBytes(11, pbText(5, "Sample Sans") + pbInt(35, 0)))
        let para = iwaArchive(30, 2022, pbBytes(11, pbText(5, "Paragraph Font") + pbText(9, "en") + pbBytes(7, color)))
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "ABC") + pbBytes(5, pagesRanges([(0, 30)])) + pbBytes(8, pagesRanges([(0, 22), (1, 23), (2, nil)])))
        let data = pagesPackage(root + base + clears + inheritedClears + restored + para + body), result = try Document.read(data)
        let runs = result.document.paragraphs[0].runs
        #expect(runs[0].formatting.fontName == nil && runs[0].formatting.color == nil && runs[0].formatting.language == nil && runs[0].formatting.rightToLeft == nil)
        #expect(runs[0].formatting.emphasis == nil && runs[0].formatting.bold == true)
        #expect(runs[1].formatting.fontName == "Sample Sans" && runs[1].formatting.rightToLeft == false && runs[1].formatting.language == nil)
        #expect(runs[2].formatting.fontName == "Paragraph Font" && runs[2].formatting.language == "en")
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }

    @Test func pagesTabStopsOutlineCapitalizationAndDirectionsAreTyped() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        let tabs = pbBytes(1, pbFloat(1, 36) + pbInt(2, 1) + pbText(3, ".")) + pbBytes(1, pbFloat(1, 72) + pbInt(2, 3))
        let baseProperties = pbBytes(25, tabs) + pbInt(27, 2) + pbInt(38, 1) + pbBytes(13, pbInt(1, 2) + pbFloat(2, 18))
        let base = iwaArchive(20, 2022, pbBytes(11, pbInt(13, 2) + pbInt(35, 1)) + pbBytes(12, baseProperties))
        let cleared = iwaArchive(21, 2022, pbBytes(1, pbRef(3, 20)) + pbBytes(12, pbInt(24, 1) + pbInt(12, 1) + pbInt(38, UInt64.max)))
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "One\nTwo") + pbBytes(5, pagesRanges([(0, 20), (4, 21)])))
        let result = try Document.read(pagesPackage(root + base + cleared + body)), paragraphs = result.document.paragraphs
        #expect(paragraphs[0].formatting.tabs == [TabStop(position: 36, alignment: "center", leader: "."), TabStop(position: 72, alignment: "decimal")])
        #expect(paragraphs[0].formatting.outlineLevel == 2 && paragraphs[0].formatting.rightToLeft == true)
        #expect(paragraphs[0].runs[0].formatting.smallCaps == true && paragraphs[0].runs[0].formatting.allCaps == false)
        #expect(paragraphs[1].formatting.tabs == nil && paragraphs[1].formatting.lineSpacing == nil && paragraphs[1].formatting.lineSpacingRule == nil && paragraphs[1].formatting.rightToLeft == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test(arguments: [UInt64(2), 99])
    func pagesLanguageBoundariesRejectSurrogateSplitsAndOutOfRangeOffsets(_ offset: UInt64) throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "A😀B") + pbBytes(19, pagesLanguages([(offset, "ja")])) )
        #expect(throws: DocumentError.self) { try Document.read(pagesPackage(root + body)) }
    }

    @Test func pagesMalformedLanguageAndUnsupportedTabsRemainDiagnosed() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        let duplicate = pbBytes(19, pagesLanguages([(0, "ja"), (0, "en")]))
        let malformed = pbBytes(19, pbBytes(1, pbInt(1, 0) + pbBytes(2, Data([255]))))
        for table in [duplicate, malformed] {
            let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "X") + table)
            #expect(throws: DocumentError.self) { try Document.read(pagesPackage(root + body)) }
        }
        let tabs = pbBytes(1, pbFloat(1, 36) + pbInt(2, 99))
        let style = iwaArchive(20, 2022, pbBytes(12, pbBytes(25, tabs) + pbInt(38, 99)))
        let language = pbBytes(19, pbBytes(1, pbInt(1, 0) + pbText(2, "ja") + pbInt(99, 1)))
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "X") + pbBytes(5, pagesRanges([(0, 20)])) + language)
        let data = pagesPackage(root + style + body), result = try Document.read(data)
        #expect(result.document.paragraphs[0].formatting.tabs == [] && result.document.paragraphs[0].formatting.rightToLeft == nil)
        #expect(result.warnings.contains { $0.element == "Pages.tabStop" })
        #expect(result.warnings.contains { $0.element == "Pages.writingDirection" })
        #expect(result.warnings.contains { $0.element == "IWA.2001.field19.field1.field99" })
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }
}
