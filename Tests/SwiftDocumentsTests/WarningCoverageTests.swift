import Foundation
import Testing
import SwiftDocuments

@Suite struct WarningCoverageTests {
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func historyWarningsCountSourceOccurrencesOnceInEveryView(_ view: ReadOptions.RevisionView) throws {
        let data = makeDocument("""
        <w:p><w:pPr><w:pPrChange w:id="p"><w:pPr><w:jc w:val="left" x:extra="paragraph"/></w:pPr></w:pPrChange>
        <w:rPr><w:rPrChange w:id="mark"><w:rPr><w:i x:extra="mark"/></w:rPr></w:rPrChange></w:rPr></w:pPr>
        <w:r><w:rPr><w:rPrChange w:id="r"><w:rPr><w:b x:extra="run"/></w:rPr></w:rPrChange></w:rPr><w:t>Text</w:t></w:r></w:p>
        <w:tbl><w:tblPr><w:tblPrChange w:id="t"><w:tblPr><w:tblStyle w:val="source" x:extra="table"/></w:tblPr></w:tblPrChange></w:tblPr>
        <w:tblGrid><w:tblGridChange w:id="g"><w:tblGrid><w:gridCol w:w="1000" x:extra="column"/></w:tblGrid></w:tblGridChange></w:tblGrid>
        <w:tr><w:trPr><w:trPrChange w:id="tr"><w:trPr><w:tblHeader x:extra="row"/></w:trPr></w:trPrChange></w:trPr>
        <w:tc><w:tcPr><w:tcPrChange w:id="tc"><w:tcPr><w:vAlign w:val="top" x:extra="cell"/></w:tcPr></w:tcPrChange></w:tcPr><w:p/></w:tc></w:tr></w:tbl>
        """)
        let options = ReadOptions(revisions: view), result = try Document.read(data, options: options)
        for element in ["jc", "b", "i", "tblStyle", "gridCol", "tblHeader", "vAlign"] {
            #expect(result.warnings.first { $0.element == element }?.count == 1)
        }
        #expect(try Document.scan(data, options: options) { _ in }.warnings == result.warnings)
    }
    @Test func propertyContainersAndRecognizedLeavesKeepExtensionsAndWarn() throws {
        let body = """
        <w:p><w:pPr x:container="paragraph"><w:keepNext><x:extension/></w:keepNext>
        <w:tabs x:extra="tabs"><w:tab w:pos="720" w:val="left"><x:tabExtension/></w:tab></w:tabs>
        <w:numPr x:extra="numbering"><w:numId w:val="0"/></w:numPr></w:pPr>
        <w:r><w:rPr x:container="run"><w:b/></w:rPr><w:t>Kept</w:t></w:r></w:p>
        """
        let data = makeDocument(body), result = try Document.read(data)
        let p = try #require(result.document.paragraphs.first)
        #expect(p.formatting.keepWithNext == true && p.formatting.tabs?.first?.position == 36)
        #expect(p.formatting.rawProperties.contains { $0.contains("container") })
        #expect(p.formatting.rawProperties.contains { $0.contains("tabExtension") })
        #expect(p.runs[0].formatting.rawProperties.contains { $0.contains("container") })
        #expect(Set(result.warnings.map(\.element)).isSuperset(of: ["pPr", "rPr", "keepNext", "tabs", "numPr"]))
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }
    @Test func sectionExtensionsCannotOverwriteStandardGridSettings() throws {
        let data = makeDocument(paragraph("Kept") + """
        <w:sectPr x:container="section"><w:pgSz w:w="12240" w:h="15840" x:extra="size"/>
        <w:pgMar w:top="1440" x:extra="margin"/><w:cols w:num="2" w:equalWidth="invalid" w:sep="invalid"/>
        <w:docGrid w:linePitch="360" x:linePitch="999" w:type="lines"/><w:type w:val="continuous"><x:extension/></w:type></w:sectPr>
        """)
        let result = try Document.read(data), section = try #require(result.document.sections.first)
        #expect(section.documentGrid["linePitch"] == "360")
        #expect(section.pageWidth == 612 && section.margins["top"] == 72)
        #expect(section.equalColumnWidths == nil && section.columnSeparator == nil)
        #expect(section.rawProperties.contains { $0.contains("container") })
        #expect(Set(result.warnings.map(\.element)).isSuperset(of: ["sectPr", "pgSz", "pgMar", "cols", "docGrid", "type"]))
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }
    @Test func malformedParagraphMeasuresStayRawAndDiagnosed() throws {
        let result = try Document.read(makeDocument("""
        <w:p><w:pPr><w:spacing w:before="invalid"/><w:ind w:left="NaN"/><w:outlineLvl w:val="future"/>
        <w:tabs><w:tab w:pos="invalid" w:val="left"/></w:tabs></w:pPr><w:r><w:rPr><w:w w:val="NaN"/></w:rPr><w:t>Kept</w:t></w:r></w:p>
        """))
        let p = try #require(result.document.paragraphs.first)
        #expect(p.formatting.spacingBefore == nil && p.formatting.indentLeft == nil && p.formatting.tabs?.isEmpty == true)
        #expect(p.runs[0].formatting.textScale == nil)
        #expect(Set(result.warnings.map(\.element)).isSuperset(of: ["spacing", "ind", "outlineLvl", "tabs", "w"]))
    }
    @Test func unknownRowAndCellPropertiesWarnAndSurvive() throws {
        let body = "<w:tbl><w:tr><w:trPr><x:rowSetting/></w:trPr><w:tc><w:tcPr><x:cellSetting/></w:tcPr>" + paragraph("Kept") + "</w:tc></w:tr></w:tbl>"
        let data = makeDocument(body)
        let read = try Document.read(data)
        let row = try #require(read.document.tables.first?.rows.first)
        #expect(row.properties.contains { $0.contains("rowSetting") })
        #expect(row.cells[0].properties.contains { $0.contains("cellSetting") })
        #expect(Set(read.warnings.filter { $0.code == .uninterpretedFormatting }.map(\.element)) == ["rowSetting", "cellSetting"])
        let scan = try Document.scan(data) { _ in }
        #expect(scan.warnings == read.warnings)
        #expect(read.document.plainText == "Kept")
    }
    @Test func unequalColumnDetailsAreNeverSilentlyIgnored() throws {
        let data = makeDocument(paragraph("Kept") + "<w:sectPr><w:cols w:num=\"2\" w:equalWidth=\"0\"><w:col w:w=\"2000\" w:space=\"720\"/><w:col w:w=\"4000\"/></w:cols></w:sectPr>")
        let read = try Document.read(data)
        #expect(read.document.sections[0].rawProperties.contains { $0.contains("2000") && $0.contains("4000") })
        #expect(read.document.sections[0].columns.map(\.width) == [100, 200])
        #expect(read.document.sections[0].columns[0].spacingAfter == 36)
        #expect(read.document.sections[0].equalColumnWidths == false)
        #expect(try Document.scan(data) { _ in }.warnings == read.warnings)
    }
    @Test func unknownDocumentRootChildrenWarnWithoutChangingBody() throws {
        var parts = documentParts(paragraph("Body"))
        let xml = String(decoding: parts["word/document.xml"]!, as: UTF8.self).replacingOccurrences(of: "<w:body>", with: "<x:rootSetting/><x:rootSetting/><w:body>")
        parts["word/document.xml"] = Data(xml.utf8)
        let data = makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        let read = try Document.read(data)
        let warning = try #require(read.warnings.first { $0.code == .unsupportedContent && $0.element.contains("rootSetting") })
        #expect(warning.count == 2)
        #expect(read.document.plainText == "Body")
        #expect(try Document.scan(data) { _ in }.warnings == read.warnings)
    }
}
