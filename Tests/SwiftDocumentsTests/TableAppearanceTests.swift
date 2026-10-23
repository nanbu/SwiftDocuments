import Foundation
import Testing
import SwiftDocuments

private func appearanceCell(_ properties: String = "", text: String = "A") -> String {
    "<w:tc><w:tcPr>\(properties)</w:tcPr>\(paragraph(text))</w:tc>"
}

@Suite struct TableAppearanceTests {
    @Test(arguments: [wordNS, "http://purl.oclc.org/ooxml/wordprocessingml/main"])
    func wordTableAppearanceUsesPointsAndRetainsLogicalEdges(_ namespace: String) throws {
        let body = """
        <w:tbl><w:tblPr><w:jc w:val="center"/><w:tblLayout w:type="fixed"/>
        <w:tblInd w:w="-240" w:type="dxa"/><w:tblCellSpacing w:w="40" w:type="dxa"/><w:bidiVisual/>
        <w:tblBorders><w:start w:val="double" w:sz="16" w:space="2" w:color="123456" w:shadow="true"/><w:left w:val="nil"/></w:tblBorders>
        <w:tblCellMar><w:top w:w="100" w:type="dxa"/><w:end w:w="0" w:type="nil"/></w:tblCellMar></w:tblPr>
        <w:tr><w:trPr><w:gridBefore w:val="1"/><w:gridAfter w:val="2"/><w:wBefore w:w="500" w:type="dxa"/><w:wAfter w:w="1000" w:type="pct"/><w:cantSplit/></w:trPr>
        \(appearanceCell("<w:tcBorders><w:tr2bl w:val=\"single\" w:sz=\"4\"/></w:tcBorders><w:tcMar><w:left w:w=\"40\" w:type=\"dxa\"/></w:tcMar><w:noWrap w:val=\"0\"/><w:tcFitText/><w:textDirection w:val=\"tbRl\"/>"))</w:tr></w:tbl>
        """
        let parts = documentParts(body).mapValues { Data(String(decoding: $0, as: UTF8.self).replacingOccurrences(of: wordNS, with: namespace).utf8) }
        let data = makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        let result = try Document.read(data), table = result.document.tables[0], row = table.rows[0], cell = row.cells[0]
        #expect(table.alignment == .center && table.layout == .fixed && table.rightToLeft == true)
        #expect(table.indentation?.value == -12 && table.cellSpacing?.value == 2)
        #expect(table.borders[.start]?.width == 2 && table.borders[.start]?.spacing == 2 && table.borders[.start]?.shadow == true)
        #expect(table.borders[.left]?.style == "nil" && table.borders[.right] == nil)
        #expect(table.cellMargins[.top]?.value == 5 && table.cellMargins[.end]?.unit == TableWidth.Unit.none)
        #expect(row.omittedLeadingColumns == 1 && row.omittedTrailingColumns == 2 && row.leadingWidth?.value == 25 && row.trailingWidth?.value == 20 && row.preventSplit == true)
        #expect(cell.borders[.diagonalUp]?.width == 0.5 && cell.margins[.left]?.value == 2)
        #expect(cell.noWrap == false && cell.fitText == true && cell.textDirection == "tbRl")
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }

    @Test func tableBordersAndMarginsMergePerEdgeThroughConditionalStyles() throws {
        let styles = """
        <w:styles xmlns:w="\(wordNS)"><w:style w:type="table" w:styleId="Base">
        <w:tblPr><w:jc w:val="right"/><w:tblBorders><w:top w:val="single" w:sz="8"/><w:bottom w:val="double" w:sz="16"/></w:tblBorders><w:tblCellMar><w:left w:w="200"/></w:tblCellMar></w:tblPr>
        <w:tcPr><w:tcBorders><w:left w:val="single" w:sz="8"/></w:tcBorders><w:tcMar><w:top w:w="100"/><w:bottom w:w="100"/></w:tcMar><w:noWrap/></w:tcPr>
        <w:tblStylePr w:type="firstRow"><w:tcPr><w:tcBorders><w:left w:val="double" w:sz="24"/></w:tcBorders></w:tcPr></w:tblStylePr></w:style>
        <w:style w:type="table" w:styleId="Derived"><w:basedOn w:val="Base"/><w:tblPr><w:tblBorders><w:top w:val="none"/></w:tblBorders></w:tblPr></w:style></w:styles>
        """
        let body = "<w:tbl><w:tblPr><w:tblStyle w:val=\"Derived\"/><w:tblLook w:firstRow=\"1\"/></w:tblPr><w:tr>\(appearanceCell("<w:tcBorders><w:left w:val=\"nil\"/></w:tcBorders><w:tcMar><w:top w:w=\"0\"/></w:tcMar><w:noWrap w:val=\"0\"/>"))</w:tr><w:tr>\(appearanceCell())</w:tr></w:tbl>"
        let result = try Document.read(makeDocument(body, extra: ["word/styles.xml": styles], relations: [("styles", "styles", "styles.xml", false)]))
        let table = result.document.tables[0]
        #expect(table.alignment == .right && table.borders[.top]?.style == "none" && table.borders[.bottom]?.width == 2)
        #expect(table.cellMargins[.left]?.value == 10)
        #expect(table.rows[0].cells[0].borders[.left]?.style == "nil" && table.rows[1].cells[0].borders[.left]?.width == 1)
        #expect(table.rows[0].cells[0].margins[.top]?.value == 0 && table.rows[0].cells[0].margins[.bottom]?.value == 5)
        #expect(table.rows[0].cells[0].noWrap == false && table.rows[1].cells[0].noWrap == true)
        #expect(result.warnings.isEmpty)
    }

    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func previousTableAppearanceAndGridPositionsFollowTheRevisionView(_ view: ReadOptions.RevisionView) throws {
        let styles = "<w:styles xmlns:w=\"\(wordNS)\"><w:style w:type=\"table\" w:styleId=\"T\"><w:tblStylePr w:type=\"firstCol\"><w:tcPr><w:shd w:fill=\"ABCDEF\"/></w:tcPr></w:tblStylePr></w:style></w:styles>"
        let props = "<w:tblPr><w:tblStyle w:val=\"T\"/><w:tblBorders><w:top w:val=\"single\" w:sz=\"8\"/></w:tblBorders><w:tblPrChange w:id=\"t\"><w:tblPr><w:tblStyle w:val=\"T\"/><w:tblLook w:firstColumn=\"1\"/><w:tblBorders><w:top w:val=\"double\" w:sz=\"16\"/></w:tblBorders></w:tblPr></w:tblPrChange></w:tblPr>"
        let row = "<w:trPr><w:gridBefore w:val=\"1\"/><w:trPrChange w:id=\"r\"><w:trPr><w:gridBefore w:val=\"0\"/><w:cantSplit/></w:trPr></w:trPrChange></w:trPr>"
        let cell = "<w:tcBorders><w:left w:val=\"none\"/></w:tcBorders><w:tcPrChange w:id=\"c\"><w:tcPr><w:tcBorders><w:left w:val=\"single\" w:sz=\"4\"/></w:tcBorders><w:tcMar><w:top w:w=\"200\"/></w:tcMar></w:tcPr></w:tcPrChange>"
        let data = makeDocument("<w:tbl>\(props)<w:tr>\(row)\(appearanceCell(cell))</w:tr></w:tbl>", extra: ["word/styles.xml": styles], relations: [("styles", "styles", "styles.xml", false)])
        let result = try Document.read(data, options: .init(revisions: view)), table = result.document.tables[0], original = view == .original
        #expect(table.borders[.top]?.width == (original ? 2 : 1))
        #expect(table.rows[0].omittedLeadingColumns == (original ? 0 : 1))
        #expect(table.rows[0].cells[0].shading == (original ? "ABCDEF" : nil))
        #expect(table.rows[0].cells[0].borders[.left]?.style == (original ? "single" : "none"))
        #expect(table.formattingChange?.previous.borders[.top]?.width == 2)
        #expect(table.rows[0].formattingChange?.previous.preventSplit == true)
        #expect(table.rows[0].cells[0].formattingChange?.previous.margins[.top]?.value == 10)
        #expect(try Document.scan(data, options: .init(revisions: view)) { _ in }.warnings == result.warnings)
    }

    @Test func invalidBorderValuesAndForeignEdgesRemainSourceAndWarn() throws {
        let borders = "<w:tblBorders x:extra=\"1\"><w:top w:val=\"single\" w:sz=\"NaN\" w:shadow=\"maybe\"/><x:bottom w:val=\"double\" w:sz=\"16\"/><w:start w:val=\"apples\" w:sz=\"24\"/><w:end w:val=\"single\" w:color=\"not-rgb\" x:sz=\"80\"/></w:tblBorders>"
        let data = makeDocument("<w:tbl><w:tblPr>\(borders)</w:tblPr><w:tr>\(appearanceCell())</w:tr></w:tbl>")
        let result = try Document.read(data), table = result.document.tables[0]
        #expect(table.borders[.top]?.width == nil && table.borders[.top]?.shadow == nil && table.borders[.bottom] == nil)
        #expect(table.borders[.start]?.width == nil && table.borders[.start]?.sourceWidth == "24")
        #expect(table.borders[.end]?.width == nil && table.borders[.end]?.color == nil)
        #expect(table.borders[.top]?.rawProperties.first?.contains("NaN") == true)
        #expect(result.warnings.filter { $0.code == .uninterpretedFormatting }.count == 5)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }

    @Test func tablePropertyTextAndMisplacedHistoryNeverDisappearSilently() throws {
        let props = "<w:tblPr>source<w:jc w:val=\"left\">extension</w:jc><w:tblBorders>extension<w:top w:val=\"single\" w:sz=\"8\">extension</w:top></w:tblBorders><w:tblPrExChange/><w:shd w:val=\"nil\"/></w:tblPr>"
        let result = try Document.read(makeDocument("<w:tbl>\(props)<w:tr>\(appearanceCell())</w:tr></w:tbl>"))
        #expect(result.document.tables[0].properties.contains { $0.contains("source") })
        #expect(Set(result.warnings.map(\.element)).isSuperset(of: ["tblPr", "jc", "tblBorders", "top", "tblPrExChange", "shd"]))
        #expect(throws: DocumentError.self) { try Document.read(makeDocument("<w:tbl><w:tr>\(appearanceCell("<w:tcMar><w:left w:w=\"-20\"/></w:tcMar>"))</w:tr></w:tbl>")) }
    }

    @Test(arguments: ["<w:tblBorders><w:top w:val=\"single\"/><w:top w:val=\"none\"/></w:tblBorders>", "<w:tblCellMar><w:left w:w=\"20\"/><w:left w:w=\"40\"/></w:tblCellMar>"])
    func duplicateTableEdgesAreRejected(_ properties: String) throws {
        #expect(throws: DocumentError.self) { try Document.read(makeDocument("<w:tbl><w:tblPr>\(properties)</w:tblPr></w:tbl>")) }
    }

    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func rowTableExceptionsKeepTheirOwnFormerProperties(_ view: ReadOptions.RevisionView) throws {
        let exceptions = "<w:tblPrEx><w:tblBorders><w:bottom w:val=\"single\" w:sz=\"8\"/></w:tblBorders><w:tblPrExChange w:id=\"old\"><w:tblPrEx><w:tblCellMar><w:top w:w=\"100\"/></w:tblCellMar></w:tblPrEx></w:tblPrExChange></w:tblPrEx>"
        let data = makeDocument("<w:tbl><w:tblPr><w:jc w:val=\"center\"/></w:tblPr><w:tr>\(exceptions)\(appearanceCell())</w:tr></w:tbl>")
        let result = try Document.read(data, options: .init(revisions: view)), table = result.document.tables[0], row = table.rows[0]
        #expect(table.alignment == .center && table.borders.isEmpty)
        #expect(row.tableOverrides?.borders[.bottom]?.width == (view == .original ? nil : 1))
        #expect(row.tableOverridesChange?.previous.cellMargins[.top]?.value == 5)
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data, options: .init(revisions: view)) { _ in }.warnings == result.warnings)
        #expect(throws: DocumentError.self) { try Document.read(makeDocument("<w:tbl><w:tr><w:tblPrEx><w:tblPrExChange/></w:tblPrEx></w:tr></w:tbl>")) }
    }

    @Test func odtTableStylesResolveGeometryPaddingBordersAndDefaultCells() throws {
        let styles = """
        <office:styles>
        <style:style style:name="T" style:family="table"><style:table-properties style:width="12cm" style:rel-width="75%" table:align="center"/></style:style>
        <style:style style:name="C" style:family="table-column"><style:table-column-properties style:column-width="2cm"/></style:style>
        <style:style style:name="R" style:family="table-row"><style:table-row-properties style:min-row-height="12pt" fo:keep-together="always"/></style:style>
        <style:style style:name="Base" style:family="table-cell"><style:table-cell-properties fo:border="0.5pt solid #123456" fo:padding="2pt" fo:background-color="#AAAAAA"/></style:style>
        <style:style style:name="Cell" style:family="table-cell" style:parent-style-name="Base"><style:table-cell-properties fo:border-left="none" fo:padding-top="0pt" fo:wrap-option="no-wrap"/></style:style>
        <style:style style:name="RowDefault" style:family="table-cell"><style:table-cell-properties fo:background-color="#BBBBBB"/></style:style>
        </office:styles>
        """
        let body = """
        <table:table table:style-name="T"><table:table-columns><table:table-column table:style-name="C" table:default-cell-style-name="Cell" table:number-columns-repeated="2"/></table:table-columns>
        <table:table-row table:style-name="R"><table:table-cell><text:p>Column default</text:p></table:table-cell><table:table-cell table:style-name="Base"><text:p>Explicit</text:p></table:table-cell></table:table-row>
        <table:table-row table:default-cell-style-name="RowDefault"><table:table-cell><text:p>Row default</text:p></table:table-cell></table:table-row></table:table>
        """
        let data = odtPackage(body, styles: styles), result = try Document.read(data), table = result.document.tables[0]
        #expect(table.preferredWidth?.unit == .percent && table.preferredWidth?.value == 75 && table.alignment == .center)
        #expect(table.columns.count == 2 && abs(table.columns[0].width! - 144 / 2.54) < 0.0001)
        #expect(table.rows[0].height == 12 && table.rows[0].heightRule == .minimum && table.rows[0].preventSplit == true)
        let cell = table.rows[0].cells[0]
        #expect(cell.borders[.left]?.style == "none" && cell.borders[.top]?.width == 0.5 && cell.borders[.top]?.color == "123456")
        #expect(cell.margins[.top]?.value == 0 && cell.margins[.right]?.value == 2 && cell.noWrap == true)
        #expect(cell.shading == "AAAAAA" && table.rows[1].cells[0].shading == "BBBBBB")
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }

    @Test func odtCoveredCellsRetainSourcePositionsAndHiddenContent() throws {
        let body = """
        <table:table><table:table-row><table:table-cell table:number-columns-spanned="2" table:number-rows-spanned="2"><text:p>Anchor</text:p></table:table-cell><table:covered-table-cell><text:p>Hidden source</text:p></table:covered-table-cell><table:table-cell><text:p>Right</text:p></table:table-cell></table:table-row>
        <table:table-row><table:covered-table-cell table:number-columns-repeated="2"/><table:table-cell><text:p>Bottom</text:p></table:table-cell></table:table-row></table:table>
        """
        let data = odtPackage(body), result = try Document.read(data), table = result.document.tables[0]
        #expect(table.rows.map { $0.cells.count } == [3, 3])
        #expect(table.rows[0].cells[0].rowSpan == 2 && table.rows[0].cells[0].columnSpan == 2)
        #expect(table.rows[0].cells[1].isCovered && table.rows[0].cells[1].blocks[0].plainText == "Hidden source")
        #expect(result.document.plainText == "Anchor\t\tRight\n\t\tBottom")
        #expect(result.document.paragraphs.map(\.plainText) == ["Anchor", "Right", "Bottom"])
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
        #expect(throws: DocumentError.self) { try Document.read(data, options: .init(limits: .init(maxXMLNodes: 12))) }
    }

    @Test func odtCellPropertiesFallBackIndividuallyThroughRowAndColumnDefaults() throws {
        let styles = """
        <office:styles>
        <style:default-style style:family="table-cell"><style:table-cell-properties fo:background-color="#111111" fo:padding="1pt"/></style:default-style>
        <style:style style:name="Column" style:family="table-cell"><style:table-cell-properties fo:border="1pt solid #222222" fo:background-color="#222222"/></style:style>
        <style:style style:name="Row" style:family="table-cell"><style:table-cell-properties fo:background-color="#333333"/></style:style>
        <style:style style:name="Cell" style:family="table-cell"><style:table-cell-properties fo:padding-top="3pt"/></style:style>
        </office:styles>
        """
        let body = "<table:table><table:table-column table:default-cell-style-name=\"Column\"/><table:table-row table:default-cell-style-name=\"Row\"><table:table-cell table:style-name=\"Cell\"><text:p>A</text:p></table:table-cell></table:table-row></table:table>"
        let result = try Document.read(odtPackage(body, styles: styles)), cell = result.document.tables[0].rows[0].cells[0]
        #expect(cell.shading == "333333" && cell.borders[.top]?.width == 1)
        #expect(cell.margins[.top]?.value == 3 && cell.margins[.bottom]?.value == 1)
        #expect(result.warnings.isEmpty)
        var copy = cell
        copy.borders[.top]?.width = 9; copy.margins[.bottom]?.value = 7; copy.formatting.noWrap = true
        #expect(cell.borders[.top]?.width == 1 && cell.margins[.bottom]?.value == 1 && cell.noWrap == nil)
    }

    @Test func odtCellTextStylesRespectParagraphOverridesAndIndependentNestedStories() throws {
        let styles = """
        <office:styles>
        <style:default-style style:family="paragraph"><style:text-properties fo:font-size="10pt"/></style:default-style>
        <style:style style:name="Cell" style:family="table-cell"><style:text-properties fo:font-weight="bold" fo:font-size="14pt"/><style:paragraph-properties fo:text-align="center"/></style:style>
        <style:style style:name="Paragraph" style:family="paragraph"><style:text-properties fo:font-weight="normal"/></style:style>
        </office:styles>
        """
        let note = "<text:note text:id=\"n\"><text:note-body><text:p>Note</text:p></text:note-body></text:note>"
        let nested = "<table:table><table:table-row><table:table-cell><text:p>Inner</text:p></table:table-cell></table:table-row></table:table>"
        let body = "<table:table><table:table-row table:default-cell-style-name=\"Cell\"><table:table-cell><text:p>Before\(note)</text:p>\(nested)<text:p text:style-name=\"Paragraph\">After</text:p></table:table-cell></table:table-row></table:table>"
        let data = odtPackage(body, styles: styles), result = try Document.read(data), paragraphs = result.document.paragraphs
        #expect(paragraphs.map(\.plainText) == ["Before", "Inner", "After"])
        #expect(paragraphs[0].runs[0].formatting.bold == true && paragraphs[0].runs[0].formatting.fontSize == 14)
        #expect(paragraphs[0].formatting.alignment == .center)
        #expect(paragraphs[1].runs[0].formatting.bold == nil && paragraphs[1].runs[0].formatting.fontSize == 10 && paragraphs[1].formatting.alignment == nil)
        #expect(paragraphs[2].runs[0].formatting.bold == false && paragraphs[2].runs[0].formatting.fontSize == 14 && paragraphs[2].formatting.alignment == .center)
        let noteRun = result.document.stories[0].blocks[0].paragraphs[0].runs[0]
        #expect(noteRun.formatting.bold == nil && noteRun.formatting.fontSize == 10)
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }
}
