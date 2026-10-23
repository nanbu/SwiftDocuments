import Foundation
import Testing
import SwiftDocuments

private let geometryNS = "http://schemas.openxmlformats.org/drawingml/2006/main"
private let placementNS = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
private func geometryDocument(_ geometry: String, strict: Bool = false, replacements: [String: String] = [:]) -> Data {
    let body = """
    <w:p><w:r><w:drawing xmlns:a="\(geometryNS)" xmlns:wp="\(placementNS)"
      xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
      <wp:inline><wp:extent cx="1270000" cy="635000"/><wp:docPr id="1" name="Geometry"/>
      <a:graphic><a:graphicData><wps:wsp><wps:spPr>\(geometry)</wps:spPr></wps:wsp></a:graphicData></a:graphic>
      </wp:inline></w:drawing></w:r></w:p>
    """
    var parts = documentParts(body)
    for (old, new) in replacements {
        parts["word/document.xml"] = Data(String(decoding: parts["word/document.xml"]!, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8)
    }
    if strict {
        let xml = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
            .replacingOccurrences(of: wordNS, with: "http://purl.oclc.org/ooxml/wordprocessingml/main")
            .replacingOccurrences(of: geometryNS, with: "http://purl.oclc.org/ooxml/drawingml/main")
            .replacingOccurrences(of: placementNS, with: "http://purl.oclc.org/ooxml/drawingml/wordprocessingDrawing")
        parts["word/document.xml"] = Data(xml.utf8)
    }
    return makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
}
private func readGeometry(_ document: Document) throws -> DrawingGeometry {
    let inline = try #require(document.paragraphs.first?.inlines.first)
    guard case .drawing(let drawing) = inline else { throw DocumentError.invalidModel("expected drawing") }
    return try #require(drawing.root.geometry)
}

@Suite struct GeometryReadingTests {
    @Test func drawingNamespacesCannotSupplyForeignPlacementOrShapeProperties() throws {
        let bytes = geometryDocument("""
        <x:prstGeom prst="ellipse"/><a:prstGeom prst="rect"/><x:solidFill><a:srgbClr val="FF0000"/></x:solidFill>
        """, replacements: [
            "<wp:extent": "<x:extent", "<wp:docPr": "<x:docPr",
            "<wp:inline>": "<wp:inline w:behindDoc=\"1\"><wp:positionH relativeFrom=\"page\"><x:posOffset>12700</x:posOffset></wp:positionH>"
        ])
        let result = try Document.read(bytes)
        guard case .drawing(let scene) = result.document.paragraphs[0].inlines[0] else { Issue.record("expected drawing"); return }
        #expect(scene.placement.width == nil && scene.placement.height == nil)
        #expect(scene.placement.horizontal?.offset == nil && scene.placement.behindText == false)
        #expect(scene.root.id == nil && scene.root.name == nil && scene.root.fill == nil)
        #expect(scene.root.geometry?.preset == "rect")
        #expect(Set(result.warnings.map(\.element)).isSuperset(of: ["inline", "extent", "docPr", "posOffset", "prstGeom", "solidFill"]))
        #expect(try Document.scan(bytes) { _ in }.warnings == result.warnings)
    }
    @Test func percentagePlacementAndInvalidFlagsRemainExplicit() throws {
        let bytes = geometryDocument("<a:prstGeom prst=\"rect\"/>", replacements: ["<wp:inline>": """
        <wp:inline behindDoc="invalid" allowOverlap="invalid" layoutInCell="invalid">
        <wp:positionH relativeFrom="page"><wp14:pctPosHOffset xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing">25000</wp14:pctPosHOffset></wp:positionH>
        <wp:positionV relativeFrom="page"><wp14:pctPosVOffset xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing">50%</wp14:pctPosVOffset></wp:positionV>
        """])
        let result = try Document.read(bytes)
        guard case .drawing(let scene) = result.document.paragraphs[0].inlines[0] else { Issue.record("expected drawing"); return }
        #expect(scene.placement.horizontal?.percentage == 0.25 && scene.placement.vertical?.percentage == 0.5)
        #expect(scene.placement.behindText == false && scene.placement.allowOverlap && scene.placement.layoutInCell)
        #expect(result.warnings.count == 1 && result.warnings[0].element == "inline" && result.warnings[0].count == 1)
        #expect(scene.placement.rawProperties.contains { $0.contains("invalid") })
        #expect(try Document.scan(bytes) { _ in }.warnings == result.warnings)
    }
    @Test func foreignDrawingContainerNeverBecomesAStandardScene() throws {
        let bytes = geometryDocument("<a:prstGeom prst=\"rect\"/>", replacements: [placementNS: "urn:foreign/wordprocessingDrawing"])
        let result = try Document.read(bytes)
        guard case .unsupported = result.document.paragraphs[0].inlines[0] else { Issue.record("expected source preservation"); return }
        #expect(result.warnings.contains { $0.code == .unsupportedContent })
        #expect(try Document.scan(bytes) { _ in }.warnings == result.warnings)
    }
    @Test(arguments: [false, true])
    func customPathsKeepDimensionsFlagsAndEveryCommand(_ strict: Bool) throws {
        let bytes = geometryDocument("""
        <a:custGeom><a:avLst><a:gd name="adjust" fmla="val 10"/></a:avLst>
        <a:gdLst><a:gd name="edge" fmla="*/ w 1 2"/></a:gdLst>
        <a:pathLst><a:path w="100" h="50" fill="none" stroke="false" extrusionOk="0">
        <a:moveTo><a:pt x="0" y="0"/></a:moveTo><a:lnTo><a:pt x="edge" y="adjust"/></a:lnTo>
        <a:quadBezTo><a:pt x="20" y="0"/><a:pt x="30" y="10"/></a:quadBezTo>
        <a:cubicBezTo><a:pt x="30" y="20"/><a:pt x="40" y="30"/><a:pt x="50" y="25"/></a:cubicBezTo>
        <a:arcTo wR="10" hR="5" stAng="0" swAng="cd4"/><a:close/>
        </a:path></a:pathLst></a:custGeom>
        """, strict: strict)
        let result = try Document.read(bytes), geometry = try readGeometry(result.document)
        let path = try #require(geometry.paths.first)
        #expect(path.width == 100 && path.height == 50 && path.fill == "none")
        #expect(path.stroke == false && path.extrusionOK == false && path.commands.count == 6)
        let evaluated = try GeometryEvaluator.evaluate(geometry, width: 100, height: 50)
        #expect(evaluated.paths[0].extrusionOK == false)
        #expect(result.warnings.isEmpty)
        #expect(try Document.scan(bytes) { _ in }.warnings == result.warnings)
    }
    @Test(arguments: [
        "<a:avLst><a:gd fmla=\"val 1\"/></a:avLst>",
        "<a:gdLst><a:gd name=\"x\"/></a:gdLst>",
        "<a:gdLst><a:gd name=\"x\" fmla=\"val 1\"/><a:gd name=\"x\" fmla=\"val 2\"/></a:gdLst>",
        "<a:pathLst><a:path><a:moveTo><a:pt x=\"1\"/></a:moveTo></a:path></a:pathLst>",
        "<a:pathLst><a:path><a:lnTo/></a:path></a:pathLst>",
        "<a:pathLst><a:path><a:quadBezTo><a:pt x=\"1\" y=\"2\"/></a:quadBezTo></a:path></a:pathLst>",
        "<a:pathLst><a:path><a:arcTo wR=\"1\" hR=\"2\" stAng=\"0\"/></a:path></a:pathLst>",
        "<a:pathLst><a:path><a:moveTo><x:pt x=\"1\" y=\"2\"/></a:moveTo></a:path></a:pathLst>",
        "<a:pathLst><a:path><a:moveTo><a:pt w:x=\"1\" y=\"2\"/></a:moveTo></a:path></a:pathLst>"
    ])
    func malformedGeometryNeverInventsCoordinates(_ content: String) throws {
        let bytes = geometryDocument("<a:custGeom>\(content)</a:custGeom>")
        #expect(throws: DocumentError.self) { try Document.read(bytes) }
        #expect(throws: DocumentError.self) { try Document.scan(bytes) { _ in } }
    }
    @Test func optionalGeometryExtensionsStayRawAndWarnOnce() throws {
        let bytes = geometryDocument("""
        <a:custGeom x:extra="geometry"><x:gdLst/><a:pathLst><x:path/>
        <a:path w="NaN" h="-1" stroke="invalid" extrusionOk="invalid" x:extra="path">
        <a:moveTo x:extra="move"><a:pt x="0" y="0"/></a:moveTo><x:lnTo/><a:futureCommand/>
        </a:path></a:pathLst></a:custGeom>
        """)
        let result = try Document.read(bytes), geometry = try readGeometry(result.document)
        #expect(geometry.paths.count == 1)
        #expect(geometry.paths[0].width == nil && geometry.paths[0].height == nil)
        #expect(geometry.paths[0].stroke == nil && geometry.paths[0].extrusionOK == nil)
        #expect(geometry.rawXML?.contains("futureCommand") == true)
        for name in ["custGeom", "gdLst", "path", "moveTo", "lnTo", "futureCommand"] {
            #expect(result.warnings.contains { $0.element == name && $0.code == .uninterpretedFormatting })
        }
        #expect(result.warnings.first { $0.element == "path" }?.count == 2)
        #expect(try Document.scan(bytes) { _ in }.warnings == result.warnings)
    }
    @Test func presetExpansionKeepsSourceAndDiagnosesUnknownAdjustments() throws {
        let bytes = geometryDocument("""
        <a:prstGeom prst="roundRect" x:extra="kept"><a:avLst>
        <a:gd name="adj" fmla="val 20000"/><a:gd name="future" fmla="val 1"/>
        </a:avLst><x:extension/></a:prstGeom>
        """)
        let result = try Document.read(bytes), geometry = try readGeometry(result.document)
        #expect(geometry.preset == "roundRect" && !geometry.paths.isEmpty)
        #expect(geometry.adjustments.first { $0.name == "adj" }?.formula == "val 20000")
        #expect(geometry.rawXML?.contains("future") == true && geometry.rawXML?.contains("extension") == true)
        #expect(result.warnings.contains { $0.element == "gd" })
        #expect(try Document.scan(bytes) { _ in }.warnings == result.warnings)
    }
}
