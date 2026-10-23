import Foundation
import Testing
import SwiftDocuments

@Suite struct MeasurementTests {
    @Test func strictUniversalLengthsPreservePointsAcrossTextParagraphsAndSections() throws {
        let body = "<w:p><w:pPr><w:spacing w:before=\"0.5in\" w:after=\"12pt\" w:line=\"14pt\" w:lineRule=\"exact\"/><w:ind w:left=\"2.54cm\" w:hanging=\"1pc\"/><w:tabs><w:tab w:pos=\"25.4mm\" w:val=\"left\"/></w:tabs></w:pPr><w:r><w:rPr><w:sz w:val=\"12pt\"/><w:szCs w:val=\"1pc\"/><w:spacing w:val=\"1pt\"/><w:position w:val=\"-2pt\"/></w:rPr><w:t>Source</w:t></w:r></w:p><w:sectPr><w:pgSz w:w=\"210mm\" w:h=\"297mm\"/><w:pgMar w:top=\"1in\" w:left=\"2.54cm\"/><w:cols w:num=\"2\" w:space=\"0.5in\"/></w:sectPr>"
        var parts = documentParts(body)
        parts["word/document.xml"] = Data(String(decoding: parts["word/document.xml"]!, as: UTF8.self).replacingOccurrences(of: wordNS, with: "http://purl.oclc.org/ooxml/wordprocessingml/main").utf8)
        let document = try Document(data: makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }))
        let paragraph = document.paragraphs[0], formatting = paragraph.runs[0].formatting
        #expect(formatting.fontSize == 12 && formatting.fontSizeComplexScript == 12 && formatting.characterSpacing == 1 && formatting.position == -2)
        #expect(paragraph.formatting.spacingBefore == 36 && paragraph.formatting.spacingAfter == 12 && paragraph.formatting.lineSpacing == 14)
        #expect(paragraph.formatting.indentLeft == 72 && paragraph.formatting.firstLineIndent == -12 && paragraph.formatting.tabs?[0].position == 72)
        #expect(abs((document.sections[0].pageWidth ?? 0) - 210 * 72 / 25.4) < 0.000001)
        #expect(document.sections[0].margins["top"] == 72 && document.sections[0].columnSpacing == 36)
        #expect(document.readWarnings.isEmpty)
    }
    @Test(arguments: [
        ("2500", "pct", 50.0, TableWidth.Unit.percent),
        ("33.3%", "pct", 33.3, .percent),
        ("33.3%", "dxa", 33.3, .percent),
        ("2in", "dxa", 144.0, .points),
        ("2880", "dxa", 144.0, .points),
        ("12pi", "dxa", 144.0, .points)
    ])
    func preferredTableAndCellWidthsNormalizeUnitsAndKeepSource(_ input: (String, String, Double, TableWidth.Unit)) throws {
        let (raw, unit, expected, normalized) = input
        let width = "w:w=\"\(raw)\" w:type=\"\(unit)\""
        let body = "<w:tbl><w:tblPr><w:tblW \(width)/></w:tblPr><w:tr><w:tc><w:tcPr><w:tcW \(width)/></w:tcPr>\(paragraph("Cell"))</w:tc></w:tr></w:tbl>"
        let document = try Document(data: makeDocument(body)), table = document.tables[0]
        #expect(table.preferredWidth?.unit == normalized && table.preferredWidth?.value == expected)
        #expect(table.rows[0].cells[0].preferredWidth == table.preferredWidth)
        #expect(table.preferredWidth?.sourceValue == raw && table.preferredWidth?.sourceUnit == unit)
        #expect(document.readWarnings.isEmpty)
    }
    @Test func automaticNoneAndUnknownWidthUnitsAreNotInvented() throws {
        let body = "<w:tbl><w:tblPr><w:tblW w:type=\"auto\"/></w:tblPr><w:tr><w:tc><w:tcPr><w:tcW w:type=\"nil\"/></w:tcPr>\(paragraph("None"))</w:tc><w:tc><w:tcPr><w:tcW w:type=\"vendor\" w:w=\"42\"/></w:tcPr>\(paragraph("Native"))</w:tc></w:tr></w:tbl>"
        let document = try Document(data: makeDocument(body)), table = document.tables[0]
        #expect(table.preferredWidth?.unit == .automatic && table.preferredWidth?.value == nil)
        #expect(table.rows[0].cells[0].preferredWidth?.unit == TableWidth.Unit.none)
        #expect(table.rows[0].cells[1].preferredWidth?.unit == .native && table.rows[0].cells[1].preferredWidth?.sourceValue == "42")
        #expect(document.readWarnings.contains { $0.element == "tcW" && $0.code == .uninterpretedFormatting })
    }
    @Test(arguments: ["NaN", "INF", "unknown", "NaN%"])
    func invalidPhysicalWidthsDoNotBecomeMissingSuccess(_ raw: String) throws {
        let body = "<w:tbl><w:tr><w:tc><w:tcPr><w:tcW w:type=\"dxa\" w:w=\"\(raw)\"/></w:tcPr>\(paragraph("Cell"))</w:tc></w:tr></w:tbl>"
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(body)) }
    }
    @Test func nonfiniteTextMeasuresRemainRawAndDiagnosed() throws {
        let document = try Document(data: makeDocument("<w:p><w:r><w:rPr><w:sz w:val=\"NaN\"/><w:position w:val=\"inf\"/></w:rPr><w:t>Source</w:t></w:r></w:p>"))
        #expect(document.paragraphs[0].runs[0].formatting.fontSize == nil)
        #expect(Set(document.readWarnings.map(\.element)).isSuperset(of: ["sz", "position"]))
    }
}
