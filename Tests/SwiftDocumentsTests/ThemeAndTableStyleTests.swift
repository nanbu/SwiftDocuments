import Foundation
import Testing
import SwiftDocuments

private let drawingNS = "http://schemas.openxmlformats.org/drawingml/2006/main"
private func stylePackage(_ body: String, styles: String) -> Data {
    makeDocument(body, extra: ["word/styles.xml": "<w:styles xmlns:w=\"\(wordNS)\">\(styles)</w:styles>"], relations: [("styles", "styles", "styles.xml", false)])
}
@Suite struct ThemeAndTableStyleTests {
    @Test func themeColorsTintShadeFontsAndDirectOverrides() throws {
        let theme = """
        <a:theme xmlns:a="\(drawingNS)"><a:themeElements><a:clrScheme name="Sample"><a:accent1><a:srgbClr val="4F81BD"/></a:accent1><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1></a:clrScheme><a:fontScheme name="Sample"><a:majorFont><a:latin typeface="Sample Serif"/><a:ea typeface=""/><a:font script="Jpan" typeface="Sample Japanese"/></a:majorFont><a:minorFont><a:latin typeface="Sample Sans"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>
        """
        let body = """
        <w:p><w:r><w:rPr><w:color w:val="FFFFFF" w:themeColor="accent1" w:themeTint="99"/><w:rFonts w:asciiTheme="majorHAnsi" w:eastAsiaTheme="majorEastAsia"/><w:lang w:eastAsia="ja-JP"/></w:rPr><w:t>A</w:t></w:r><w:r><w:rPr><w:color w:themeColor="accent1" w:themeShade="BF"/></w:rPr><w:t>B</w:t></w:r><w:r><w:rPr><w:color w:themeColor="accent1" w:themeTint="99" w:themeShade="00"/></w:rPr><w:t>C</w:t></w:r></w:p>
        """
        let data = makeDocument(body, extra: ["word/theme.xml": theme], relations: [("theme", "theme", "theme.xml", false)])
        let result = try Document.read(data), runs = result.document.paragraphs[0].runs
        #expect(runs[0].formatting.color == "95B3D7")
        #expect(runs[1].formatting.color == "376092")
        #expect(runs[2].formatting.color == "95B3D7")
        #expect(runs[0].formatting.themeTint == "99" && runs[0].formatting.themeColor == "accent1")
        #expect(runs[0].formatting.fontName == "Sample Serif" && runs[0].formatting.fontNameEastAsia == "Sample Japanese")
        #expect(result.warnings.isEmpty)
        var direct = TextFormatting(); direct.fontName = "Explicit"; direct.color = "123456"
        var inherited = runs[0].formatting; inherited.merge(direct)
        #expect(inherited.fontName == "Explicit" && inherited.fontTheme == nil && inherited.themeColor == nil && inherited.themeTint == nil)
    }
    @Test func inheritedThemeFontsFollowEffectiveRunLanguageAndDirectNames() throws {
        let theme = "<a:theme xmlns:a=\"\(drawingNS)\"><a:themeElements><a:fontScheme name=\"Sample\"><a:majorFont><a:latin typeface=\"Sample Latin\"/><a:font script=\"Jpan\" typeface=\"Sample Japanese\"/><a:font script=\"Hang\" typeface=\"Sample Korean\"/></a:majorFont></a:fontScheme></a:themeElements></a:theme>"
        let styles = "<w:styles xmlns:w=\"\(wordNS)\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:asciiTheme=\"majorAscii\" w:eastAsiaTheme=\"majorEastAsia\"/><w:lang w:eastAsia=\"ja-JP\"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>"
        let body = "<w:p><w:r><w:rPr><w:lang w:eastAsia=\"ko-KR\"/></w:rPr><w:t>Korean</w:t></w:r><w:r><w:rPr><w:rFonts w:ascii=\"Explicit\"/></w:rPr><w:t>Explicit</w:t></w:r></w:p>"
        let result = try Document.read(makeDocument(body, extra: ["word/theme.xml": theme, "word/styles.xml": styles], relations: [("theme", "theme", "theme.xml", false), ("styles", "styles", "styles.xml", false)]))
        #expect(result.document.paragraphs[0].runs[0].formatting.fontNameEastAsia == "Sample Korean")
        #expect(result.document.paragraphs[0].runs[1].formatting.fontName == "Explicit")
        #expect(result.document.paragraphs[0].runs[1].formatting.fontTheme == nil)
        #expect(result.warnings.isEmpty)
    }
    @Test func themeSchemeMappingAndSettingsFontLanguage() throws {
        let theme = "<a:theme xmlns:a=\"\(drawingNS)\"><a:themeElements><a:clrScheme name=\"Sample\"><a:accent1><a:srgbClr val=\"112233\"/></a:accent1><a:accent2><a:srgbClr val=\"445566\"/></a:accent2></a:clrScheme><a:fontScheme name=\"Sample\"><a:minorFont><a:font script=\"Jpan\" typeface=\"Sample Japanese\"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>"
        let settings = "<w:settings xmlns:w=\"\(wordNS)\"><w:clrSchemeMapping w:accent1=\"accent2\"/><w:themeFontLang w:eastAsia=\"ja-JP\"/></w:settings>"
        let body = "<w:p><w:r><w:rPr><w:color w:themeColor=\"accent1\"/><w:rFonts w:eastAsiaTheme=\"minorEastAsia\"/></w:rPr><w:t>A</w:t></w:r></w:p>"
        let result = try Document.read(makeDocument(body, extra: ["word/theme.xml": theme, "word/settings.xml": settings], relations: [("theme", "theme", "theme.xml", false), ("settings", "settings", "settings.xml", false)]))
        #expect(result.document.paragraphs[0].runs[0].formatting.color == "445566")
        #expect(result.document.paragraphs[0].runs[0].formatting.fontNameEastAsia == "Sample Japanese")
        #expect(result.warnings.isEmpty)
    }
    @Test func missingThemeAndInvalidTintRemainRawAndWarn() throws {
        let result = try Document.read(makeDocument("<w:p><w:r><w:rPr><w:color w:val=\"123456\" w:themeColor=\"accent1\" w:themeTint=\"ZZ\"/><w:rFonts w:asciiTheme=\"majorAscii\"/></w:rPr><w:t>A</w:t></w:r></w:p>"))
        #expect(result.document.paragraphs[0].runs[0].formatting.color == "123456")
        #expect(result.warnings.contains { $0.code == .uninterpretedFormatting && $0.element == "color" })
        #expect(result.warnings.contains { $0.element == "rFonts" })
    }
    @Test func conditionalTableStylePrecedenceAndDirectFormatting() throws {
        let styles = """
        <w:style w:type="table" w:styleId="Base"><w:rPr><w:i/></w:rPr><w:tcPr><w:shd w:fill="EEEEEE"/></w:tcPr><w:tblStylePr w:type="band1Horz"><w:tcPr><w:shd w:fill="111111"/></w:tcPr></w:tblStylePr><w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr><w:tcPr><w:shd w:fill="222222"/></w:tcPr></w:tblStylePr></w:style>
        <w:style w:type="table" w:styleId="Table"><w:basedOn w:val="Base"/><w:tblStylePr w:type="firstCol"><w:tcPr><w:shd w:fill="333333"/></w:tcPr></w:tblStylePr><w:tblStylePr w:type="nwCell"><w:tcPr><w:shd w:fill="444444"/></w:tcPr></w:tblStylePr></w:style>
        """
        let cell = "<w:tc>\(paragraph("A"))</w:tc>"
        let data = stylePackage("<w:tbl><w:tblPr><w:tblStyle w:val=\"Table\"/><w:tblLook w:firstRow=\"1\" w:firstColumn=\"1\" w:noVBand=\"1\"/></w:tblPr><w:tblGrid><w:gridCol/><w:gridCol/></w:tblGrid><w:tr>\(cell)\(cell)</w:tr><w:tr>\(cell)<w:tc><w:tcPr><w:shd w:fill=\"ABCDEF\"/></w:tcPr><w:p><w:r><w:rPr><w:i w:val=\"0\"/></w:rPr><w:t>B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>", styles: styles)
        let result = try Document.read(data), table = result.document.tables[0]
        #expect(table.rows[0].cells.map(\.shading) == ["444444", "222222"])
        #expect(table.rows[1].cells.map(\.shading) == ["333333", "ABCDEF"])
        #expect(table.rows[0].cells[0].blocks[0].paragraphs[0].runs[0].formatting.bold == true)
        #expect(table.rows[1].cells[1].blocks[0].paragraphs[0].runs[0].formatting.italic == false)
        #expect(result.document.styles["Table"]?.tableRules.count == 3)
        var scanned: [String] = []
        let scan = try Document.scan(data) { scanned.append($0.plainText) }
        #expect(scan.warnings == result.warnings && scanned == [table.plainText])
    }
    @Test func conditionalRegionInheritanceTogglesBeforeRegionPrecedence() throws {
        let styles = "<w:style w:type=\"table\" w:styleId=\"Base\"><w:tblStylePr w:type=\"firstRow\"><w:rPr><w:b/></w:rPr></w:tblStylePr></w:style><w:style w:type=\"table\" w:styleId=\"Derived\"><w:basedOn w:val=\"Base\"/><w:tblStylePr w:type=\"firstRow\"><w:rPr><w:b/></w:rPr></w:tblStylePr><w:tblStylePr w:type=\"nwCell\"><w:rPr><w:b/></w:rPr></w:tblStylePr></w:style>"
        let cell = "<w:tc>\(paragraph("A"))</w:tc>"
        let body = "<w:tbl><w:tblPr><w:tblStyle w:val=\"Derived\"/><w:tblLook w:firstRow=\"1\" w:firstColumn=\"1\"/></w:tblPr><w:tr>\(cell)\(cell)</w:tr></w:tbl>"
        let doc = try Document.read(stylePackage(body, styles: styles)).document
        #expect(doc.paragraphs[0].runs[0].formatting.bold == true)
        #expect(doc.paragraphs[1].runs[0].formatting.bold == false)
    }
    @Test func tableLookMaskBandSizesAndNestedContexts() throws {
        let styles = """
        <w:style w:type="table" w:styleId="Table"><w:tblPr><w:tblStyleRowBandSize w:val="2"/></w:tblPr><w:rPr><w:b/></w:rPr><w:tblStylePr w:type="band1Horz"><w:tcPr><w:shd w:fill="111111"/></w:tcPr></w:tblStylePr><w:tblStylePr w:type="band2Horz"><w:tcPr><w:shd w:fill="222222"/></w:tcPr></w:tblStylePr><w:tblStylePr w:type="firstRow"><w:tcPr><w:shd w:fill="333333"/></w:tcPr></w:tblStylePr></w:style>
        """
        let rows = (0..<4).map { _ in "<w:tr><w:tc>\(paragraph("A"))</w:tc></w:tr>" }.joined()
        let result = try Document.read(stylePackage("<w:tbl><w:tblPr><w:tblStyle w:val=\"Table\"/><w:tblLook w:val=\"0020\" w:firstRow=\"0\"/></w:tblPr>\(rows)</w:tbl>", styles: styles))
        #expect(result.document.tables[0].rows.map { $0.cells[0].shading } == ["111111", "111111", "222222", "222222"])
        let nested = "<w:tbl><w:tr><w:tc>\(paragraph("inner"))</w:tc></w:tr></w:tbl>"
        let outer = try Document.read(stylePackage("<w:tbl><w:tblPr><w:tblStyle w:val=\"Table\"/></w:tblPr><w:tr><w:tc>\(nested)\(paragraph("outer"))</w:tc></w:tr></w:tbl>", styles: styles)).document
        #expect(outer.paragraphs.first?.runs.first?.formatting.bold == nil)
        #expect(outer.paragraphs.last?.runs.first?.formatting.bold == true)
        #expect(throws: DocumentError.self) { try Document.read(stylePackage("<w:tbl><w:tblPr><w:tblStyleRowBandSize w:val=\"0\"/></w:tblPr></w:tbl>", styles: styles)) }
    }
}
