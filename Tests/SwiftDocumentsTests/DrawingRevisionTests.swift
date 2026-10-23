import Foundation
import Testing
import SwiftDocuments

private let drawingMainNS = "http://schemas.openxmlformats.org/drawingml/2006/main"
private let drawingShapeNS = "http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
private func drawingRun(_ payload: String) -> String {
    """
    <w:r><w:drawing xmlns:a="\(drawingMainNS)" xmlns:wps="\(drawingShapeNS)"
      xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
      xmlns:wpc="http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
      xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
      xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
      <wp:inline><wp:extent cx="1270000" cy="635000"/><wp:docPr id="1" name="Example"/>
      <a:graphic><a:graphicData>\(payload)</a:graphicData></a:graphic></wp:inline>
    </w:drawing></w:r>
    """
}
private func scene(_ inline: Inline) throws -> DocumentDrawing {
    switch inline {
    case .drawing(let drawing): return drawing
    case .image(let image): return try #require(image.drawing)
    default: throw DocumentError.invalidModel("expected a drawing or picture")
    }
}

@Suite struct DrawingRevisionTests {
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all], ["ins", "del", "moveFrom", "moveTo"])
    func drawingsAndImagesKeepRevisionAttribution(_ view: ReadOptions.RevisionView, _ tag: String) throws {
        let shape = "<wps:wsp><wps:spPr><a:prstGeom prst=\"rect\"/></wps:spPr></wps:wsp>"
        let picture = "<pic:pic><pic:blipFill><a:blip r:embed=\"image\"/></pic:blipFill></pic:pic>"
        let legacy = "<w:r><w:pict xmlns:v=\"urn:schemas-microsoft-com:vml\"><v:rect id=\"legacy\"/></w:pict></w:r>"
        let content = drawingRun(shape) + drawingRun("<wpc:wpc>\(shape)</wpc:wpc>") + drawingRun(picture) + legacy
        let bytes = makeDocument("<w:p><w:\(tag) w:id=\"17\" w:author=\"Fictional Editor\" w:date=\"2026-01-02T03:04:05Z\">\(content)</w:\(tag)></w:p>",
            extra: ["word/media/example.png": "SYNTHETIC"], relations: [("image", "image", "media/example.png", false)])
        let options = ReadOptions(revisions: view)
        let result = try Document.read(bytes, options: options)
        var blocks: [Block] = []
        let scan = try Document.scan(bytes, options: options) { blocks.append($0) }
        let visible = view == .all || (view == .final ? ["ins", "moveTo"].contains(tag) : ["del", "moveFrom"].contains(tag))
        let expectedKind: Revision.Kind = tag == "ins" ? .insertion : tag == "del" ? .deletion : tag == "moveFrom" ? .moveFrom : .moveTo
        let inlines = result.document.paragraphs[0].inlines
        let scanned = try #require(blocks.first?.paragraphs.first).inlines
        #expect(inlines.count == (visible ? 4 : 0))
        #expect(scanned.count == inlines.count && scan.warnings == result.warnings)
        for inline in inlines + scanned {
            let drawing = try scene(inline)
            #expect(drawing.revision?.id == "17" && drawing.revision?.kind == expectedKind)
            #expect(drawing.revision?.author == "Fictional Editor" && drawing.revision?.date == "2026-01-02T03:04:05Z")
            if case .image(let image) = inline {
                #expect(image.revision?.id == drawing.revision?.id && image.revision?.kind == drawing.revision?.kind)
            }
        }
    }

    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func canvasTextUsesIndependentRevisionViews(_ view: ReadOptions.RevisionView) throws {
        let text = """
        <w:p><w:del w:id="2" w:author="Fictional A"><w:r><w:delText>旧</w:delText></w:r></w:del>
        <w:ins w:id="3" w:author="Fictional B"><w:r><w:t>新</w:t></w:r></w:ins></w:p>
        """
        let payload = "<wpc:wpc><wps:wsp><wps:spPr/><wps:txbx><w:txbxContent>\(text)</w:txbxContent></wps:txbx></wps:wsp></wpc:wpc>"
        let bytes = makeDocument("<w:p>\(drawingRun(payload))</w:p>")
        let result = try Document.read(bytes, options: .init(revisions: view))
        let drawing = try scene(result.document.paragraphs[0].inlines[0])
        let expected = view == .all ? "旧新" : view == .original ? "旧" : "新"
        #expect(drawing.revision == nil && drawing.root.plainText == expected)
        let runs = drawing.root.children[0].text.flatMap(\.paragraphs).flatMap(\.runs)
        #expect(runs.map(\.revision?.id) == (view == .all ? ["2", "3"] : view == .original ? ["2"] : ["3"]))
        var scanned: [String] = []
        let scan = try Document.scan(bytes, options: .init(revisions: view)) { scanned.append($0.plainText) }
        #expect(scanned == [expected] && scan.warnings == result.warnings)
    }

    @Test(arguments: [false, true])
    func connectorsAndCanvasOutlinesRetainTheirOwnProperties(_ strictDrawing: Bool) throws {
        let payload = """
        <wpc:wpc><wpc:bg/><wpc:whole><a:ln w="25400" cap="rnd"><a:solidFill><a:srgbClr val="123456"/></a:solidFill><a:prstDash val="dash"/></a:ln></wpc:whole>
          <wpg:wgp><wpg:grpSpPr/>
            <wps:wsp><wps:cNvPr id="10" name="Target"/><wps:cNvSpPr/><wps:spPr><a:prstGeom prst="rect"/></wps:spPr></wps:wsp>
            <wps:wsp><wps:cNvPr id="11" name="Link"/><wps:cNvCnPr><a:stCxn id="10" idx="0"/><a:endCxn id="12" idx="3"/></wps:cNvCnPr>
              <wps:spPr><a:prstGeom prst="bentConnector3"/><a:ln w="12700"><a:headEnd type="triangle"/><a:tailEnd type="none"/></a:ln></wps:spPr></wps:wsp>
          </wpg:wgp>
        </wpc:wpc>
        """
        var body = "<w:p>\(drawingRun(payload))</w:p>"
        if strictDrawing { body = body.replacingOccurrences(of: drawingMainNS, with: "http://purl.oclc.org/ooxml/drawingml/main") }
        let bytes = makeDocument(body)
        let result = try Document.read(bytes)
        let canvas = try scene(result.document.paragraphs[0].inlines[0]).root
        #expect(canvas.kind == .canvas && canvas.line?.width == 2 && canvas.line?.cap == "rnd")
        #expect(canvas.line?.fill?.color?.value == "123456" && canvas.line?.dash == "dash")
        let group = canvas.children[0], connector = group.children[1]
        #expect(group.id == nil && group.name == nil)
        #expect(connector.kind == .connector && connector.id == "11" && connector.name == "Link")
        #expect(connector.startConnection == DrawingConnection(targetID: "10", siteIndex: 0))
        #expect(connector.endConnection == DrawingConnection(targetID: "12", siteIndex: 3))
        #expect(connector.line?.width == 1 && connector.line?.head == "triangle" && connector.line?.tail == "none")
        #expect(result.warnings.isEmpty)
        var scanned: [Block] = []
        let scan = try Document.scan(bytes) { scanned.append($0) }
        let scannedCanvas = try scene(scanned[0].paragraphs[0].inlines[0]).root
        #expect(scannedCanvas.children[0].children[1].startConnection == connector.startConnection)
        #expect(scannedCanvas.line == canvas.line && scan.warnings == result.warnings)
    }

    @Test func unprojectedCanvasEffectsAndConnectorPropertiesRemainDiagnosed() throws {
        let payload = """
        <wpc:wpc><wpc:whole><a:ln><a:noFill/></a:ln><a:effectLst><a:reflection/></a:effectLst></wpc:whole>
          <wps:wsp><wps:cNvCnPr><x:stCxn id="999" idx="2"/><a:stCxn id="10" idx="1" x:future="preserved"/><a:cxnSpLocks noMove="1"/></wps:cNvCnPr><wps:spPr/></wps:wsp>
          <wps:wsp><x:cNvCnPr/><wps:spPr/></wps:wsp>
        </wpc:wpc>
        """
        let bytes = makeDocument("<w:p>\(drawingRun(payload))</w:p>")
        let result = try Document.read(bytes)
        let canvas = try scene(result.document.paragraphs[0].inlines[0]).root
        #expect(canvas.line?.fill?.kind == DrawingFill.Kind.none)
        #expect(canvas.rawProperties.contains { $0.contains("reflection") })
        #expect(canvas.children[0].startConnection == .init(targetID: "10", siteIndex: 1))
        #expect(canvas.children[0].rawProperties.contains { $0.contains("cxnSpLocks") && $0.contains("preserved") })
        #expect(canvas.children[1].kind == .shape)
        #expect(Set(result.warnings.map(\.element)).isSuperset(of: ["whole", "stCxn", "cNvCnPr"]))
        #expect(try Document.scan(bytes) { _ in }.warnings == result.warnings)
    }

    @Test func mainDrawingConnectorsAndEmptyCanvasFormattingReadWithoutWarnings() throws {
        let payload = """
        <wpc:wpc><wpc:bg/><wpc:whole/>
          <a:cxnSp><a:nvCxnSpPr><a:cNvPr id="20" name="Connector"/><a:cNvCxnSpPr><a:endCxn id="21" idx="2"/></a:cNvCxnSpPr></a:nvCxnSpPr><a:spPr/></a:cxnSp>
        </wpc:wpc>
        """
        let bytes = makeDocument("<w:p>\(drawingRun(payload))</w:p>")
        let result = try Document.read(bytes)
        let canvas = try scene(result.document.paragraphs[0].inlines[0]).root
        let connector = canvas.children[0]
        #expect(canvas.line == nil && canvas.fill == nil)
        #expect(connector.kind == .connector && connector.name == "Connector" && connector.id == "20")
        #expect(connector.startConnection == nil && connector.endConnection == .init(targetID: "21", siteIndex: 2))
        let scan = try Document.scan(bytes) { _ in }
        #expect(result.warnings.isEmpty && scan.warnings == result.warnings)
    }

    @Test(arguments: ["<a:stCxn idx=\"0\"/>", "<a:stCxn id=\"bad\" idx=\"0\"/>",
        "<a:stCxn id=\"1\"/>", "<a:stCxn id=\"1\" idx=\"-1\"/>",
        "<a:stCxn id=\"1\" idx=\"4294967296\"/>", "<a:stCxn id=\"1\" x:idx=\"0\"/>",
        "<a:stCxn id=\"1\" idx=\"0\"/><a:stCxn id=\"2\" idx=\"1\"/>"])
    func malformedConnectorEndpointsNeverBecomeSuccessfulDefaults(_ endpoint: String) throws {
        let bytes = makeDocument("<w:p>\(drawingRun("<wps:wsp><wps:cNvCnPr>\(endpoint)</wps:cNvCnPr><wps:spPr/></wps:wsp>"))</w:p>")
        #expect(throws: DocumentError.self) { try Document.read(bytes) }
        #expect(throws: DocumentError.self) { try Document.scan(bytes) { _ in } }
    }
}
