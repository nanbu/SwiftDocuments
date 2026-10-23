import Foundation
import Testing
import SwiftDocuments

private let chartNS = "http://schemas.openxmlformats.org/drawingml/2006/chart"
private func chartDrawing() -> String {
    "<w:p><w:r><w:drawing xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:c=\"\(chartNS)\"><wp:inline><wp:extent cx=\"1270000\" cy=\"1270000\"/><a:graphic><a:graphicData><c:chart r:id=\"chart\"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
}
private func chartPackage(_ data: String, extra: [String: String] = [:], chartRelationships: String = "", strict: Bool = false) -> Data {
    let ns = strict ? "http://purl.oclc.org/ooxml/drawingml/chart" : chartNS
    let chart = "<c:chartSpace xmlns:c=\"\(ns)\" xmlns:r=\"\(relNS)\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><c:chart><c:title><c:tx><c:rich><a:p><a:r><a:t>Quarterly chart</a:t></a:r></a:p></c:rich></c:tx></c:title><c:plotArea>\(data)</c:plotArea><c:legend><c:legendPos val=\"b\"/></c:legend></c:chart>\(chartRelationships)</c:chartSpace>"
    return makeDocument(paragraph("before") + chartDrawing() + paragraph("after"), extra: ["word/charts/chart1.xml": chart].merging(extra) { _, new in new }, relations: [("chart", "chart", "charts/chart1.xml", false)])
}
private func readChart(_ document: Document) throws -> Chart {
    let charts = document.paragraphs.flatMap(\.inlines).compactMap { inline -> Chart? in
        if case .drawing(let drawing) = inline { return drawing.root.chart }; return nil
    }
    return try #require(charts.first)
}

@Suite struct ChartTests {
    @Test(arguments: [false, true])
    func chartCachesKeepSparseIndicesFormulasAndLexicalValues(_ strict: Bool) throws {
        let data = "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/><c:ser><c:idx val=\"7\"/><c:order val=\"0\"/><c:tx><c:v>Series A</c:v></c:tx><c:cat><c:strLit><c:ptCount val=\"5\"/><c:pt idx=\"2\"><c:v>Spring</c:v></c:pt></c:strLit></c:cat><c:val><c:numRef><c:f>'Sheet 1'!$B$2:$B$6</c:f><c:numCache><c:formatCode>0.00</c:formatCode><c:ptCount val=\"5\"/><c:pt idx=\"2\"><c:v>12.50</c:v></c:pt><c:pt idx=\"4\"><c:v>#N/A</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser><c:axId val=\"10\"/></c:barChart><c:valAx><c:axId val=\"10\"/><c:crossAx val=\"11\"/><c:axPos val=\"l\"/><c:scaling><c:min val=\"0\"/><c:max val=\"100\"/></c:scaling><c:numFmt formatCode=\"0.0\"/></c:valAx>"
        let bytes = chartPackage(data, strict: strict), read = try Document.read(bytes)
        let chart = try readChart(read.document), series = try #require(chart.groups.first?.series.first)
        #expect(chart.title == "Quarterly chart" && chart.legendPosition == "b")
        #expect(chart.part.path == "word/charts/chart1.xml" && chart.groups[0].axisIDs == ["10"])
        #expect(series.index == 7 && series.order == 0 && series.title == "Series A")
        #expect(series.categories?.points == [ChartPoint(index: 2, text: "Spring")])
        #expect(series.values?.pointCount == 5 && series.values?.points.map(\.index) == [2, 4])
        #expect(series.values?.points[0].number == 12.5 && series.values?.points[1].number == nil)
        #expect(series.values?.points[1].text == "#N/A" && series.values?.formula == "'Sheet 1'!$B$2:$B$6")
        #expect(chart.axes[0].minimum == 0 && chart.axes[0].maximum == 100 && chart.axes[0].numberFormat == "0.0")
        #expect(read.warnings.contains { $0.element == "chartNumericPoint" })
        #expect(read.warnings.contains { $0.element == "chartAppearance" })
        #expect(!read.warnings.contains { $0.element == "chart" && $0.code == .unsupportedPart })
        var blocks: [Block] = []
        let scan = try Document.scan(bytes) { blocks.append($0) }
        #expect(scan.warnings == read.warnings && blocks.count == 3)
        #expect(try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart)) == chart)
    }
    @Test func multiLevelCategoriesAndUncachedReferencesRetainTheirSource() throws {
        let data = "<c:lineChart><c:ser><c:cat><c:multiLvlStrRef><c:f>Sheet1!$A$1:$B$3</c:f><c:multiLvlStrCache><c:ptCount val=\"3\"/><c:lvl><c:pt idx=\"0\"><c:v>North</c:v></c:pt></c:lvl><c:lvl><c:pt idx=\"2\"><c:v>April</c:v></c:pt></c:lvl></c:multiLvlStrCache></c:multiLvlStrRef></c:cat><c:val><c:numRef><c:f>Sheet1!$C$1:$C$3</c:f></c:numRef></c:val></c:ser></c:lineChart>"
        let document = try Document(data: chartPackage(data)), chart = try readChart(document)
        let series = chart.groups[0].series[0]
        #expect(series.categories?.levels?.map { $0.map(\.index) } == [[0], [2]])
        #expect(series.categories?.points.isEmpty == true)
        #expect(series.values?.source == .numberReference && series.values?.points.isEmpty == true)
        #expect(document.readWarnings.contains { $0.element == "numRef" })
    }
    @Test func workbookReferencesStayLazyAndExternalTargetsAreNeverFetched() throws {
        let rels = relationships([("book", "package", "../embeddings/book.xlsx", false)])
        let bytes = chartPackage("<c:pieChart/>", extra: ["word/charts/_rels/chart1.xml.rels": rels, "word/embeddings/book.xlsx": "SYNTHETIC-WORKBOOK-BYTES"], chartRelationships: "<c:externalData r:id=\"book\"/>")
        let document = try Document(data: bytes), chart = try readChart(document)
        #expect(chart.externalData?.path == "word/embeddings/book.xlsx")
        #expect(try document.asset(at: chart.externalData!.path!) == Data("SYNTHETIC-WORKBOOK-BYTES".utf8))
        let external = try Document(data: makeDocument(chartDrawing(), relations: [("chart", "chart", "https://example.invalid/do-not-fetch", true)]))
        #expect(try readChart(external).part.externalTarget == "https://example.invalid/do-not-fetch")
        #expect(try readChart(external).properties == nil)
        #expect(external.readWarnings.contains { $0.element == "chart" })
    }
    @Test(arguments: [
        "<c:lineChart><c:ser><c:val><c:numLit><c:pt idx=\"0\"><c:v>1</c:v></c:pt><c:pt idx=\"0\"><c:v>2</c:v></c:pt></c:numLit></c:val></c:ser></c:lineChart>",
        "<c:lineChart><c:ser><c:val><c:numLit><c:pt idx=\"-1\"><c:v>1</c:v></c:pt></c:numLit></c:val></c:ser></c:lineChart>",
        "<c:valAx><c:scaling><c:min val=\"INF\"/></c:scaling></c:valAx>",
        "<c:lineChart><c:ser><c:val><c:numLit><c:pt idx=\"0\"/></c:numLit></c:val></c:ser></c:lineChart>"
    ])
    func malformedChartPointsAndAxesThrow(_ data: String) throws {
        #expect(throws: DocumentError.self) { try Document.read(chartPackage(data)) }
    }
    @Test func declaredCountsDoNotAllocateOrFillMissingPoints() throws {
        let data = "<c:lineChart><c:ser><c:val><c:numLit><c:ptCount val=\"9223372036854775807\"/><c:pt idx=\"2\"><c:v>1</c:v></c:pt></c:numLit></c:val></c:ser></c:lineChart>"
        let d = try Document(data: chartPackage(data)), chart = try readChart(d)
        #expect(chart.groups[0].series[0].values?.points.count == 1)
    }
}
