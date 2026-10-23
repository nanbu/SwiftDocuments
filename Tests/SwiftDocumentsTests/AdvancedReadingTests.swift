import Foundation
import Testing
import SwiftDocuments

private let drawingNS = "http://schemas.openxmlformats.org/drawingml/2006/main"
private func drawing(_ payload: String, anchor: Bool = false) -> String {
    let tag = anchor ? "anchor" : "inline"
    return "<w:p><w:r><w:drawing xmlns:a=\"\(drawingNS)\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:wpc=\"http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\" xmlns:wpg=\"http://schemas.microsoft.com/office/word/2010/wordprocessingGroup\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><wp:\(tag) behindDoc=\"1\" relativeHeight=\"42\"><wp:extent cx=\"1270000\" cy=\"635000\"/><wp:positionH relativeFrom=\"page\"><wp:posOffset>254000</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"paragraph\"><wp:align>top</wp:align></wp:positionV><wp:wrapSquare wrapText=\"bothSides\"/><wp:docPr id=\"7\" name=\"Synthetic drawing\" descr=\"Example\"/><a:graphic><a:graphicData>\(payload)</a:graphicData></a:graphic></wp:\(tag)></w:drawing></w:r></w:p>"
}

@Suite struct AdvancedReadingTests {
    @Test func pictureFillsKeepPreferredSVGAndUnfetchedExternalFallback() throws {
        let shape = "<wps:wsp><wps:spPr><a:prstGeom prst=\"rect\"/><a:blipFill><a:blip r:link=\"fallback\"><a:extLst><a:ext uri=\"svg\"><asvg:svgBlip xmlns:asvg=\"http://schemas.microsoft.com/office/drawing/2016/SVG/main\" r:embed=\"svg\"/></a:ext></a:extLst></a:blip><a:srcRect l=\"10000\"/></a:blipFill></wps:spPr></wps:wsp>"
        let bytes = makeDocument(drawing(shape), extra: ["word/media/source.svg": "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"], relations: [("svg", "image", "media/source.svg", false), ("fallback", "image", "https://example.invalid/do-not-fetch.png", true)])
        let document = try Document(data: bytes)
        guard case .drawing(let scene) = document.paragraphs[0].inlines[0] else { Issue.record("Expected shape"); return }
        #expect(scene.root.fill?.kind == .picture)
        #expect(scene.root.fill?.image?.assetPath == "word/media/source.svg")
        #expect(scene.root.fill?.image?.fallbackExternalURL == "https://example.invalid/do-not-fetch.png")
        #expect(scene.root.fill?.image?.crop?.left == 0.1)
        #expect(try document.asset(at: "word/media/source.svg").count > 0)
    }
    @Test func canvasBackgroundAndPatternColorsRemainTyped() throws {
        let canvas = "<wpc:wpc><wpc:bg><a:solidFill><a:srgbClr val=\"112233\"/></a:solidFill></wpc:bg><wps:wsp><wps:spPr><a:prstGeom prst=\"rect\"/><a:pattFill prst=\"pct5\"><a:fgClr><a:srgbClr val=\"445566\"/></a:fgClr><a:bgClr><a:srgbClr val=\"FFFFFF\"/></a:bgClr></a:pattFill></wps:spPr></wps:wsp></wpc:wpc>"
        let document = try Document(data: makeDocument(drawing(canvas)))
        guard case .drawing(let scene) = document.paragraphs[0].inlines[0] else { Issue.record("Expected canvas"); return }
        #expect(scene.root.fill?.color?.value == "112233")
        #expect(scene.root.children[0].fill?.color?.value == "445566")
        #expect(scene.root.children[0].fill?.backgroundColor?.value == "FFFFFF")
    }
    @Test func canvasRetainsGroupsTransformsShapesAndText() throws {
        let shape = "<wps:wsp><wps:spPr><a:xfrm rot=\"5400000\" flipH=\"1\"><a:off x=\"127000\" y=\"254000\"/><a:ext cx=\"508000\" cy=\"254000\"/></a:xfrm><a:prstGeom prst=\"rect\"/><a:solidFill><a:srgbClr val=\"336699\"/></a:solidFill><a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill><a:prstDash val=\"dash\"/></a:ln></wps:spPr><wps:txbx><w:txbxContent>\(paragraph("図形内の日本語"))</w:txbxContent></wps:txbx></wps:wsp>"
        let data = makeDocument(drawing("<wpc:wpc><wpg:wgp><wpg:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"1270000\" cy=\"635000\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"2540000\" cy=\"1270000\"/></a:xfrm></wpg:grpSpPr>\(shape)</wpg:wgp></wpc:wpc>", anchor: true))
        let result = try Document.read(data)
        guard case .drawing(let scene) = result.document.paragraphs[0].inlines[0] else { Issue.record("Expected canvas"); return }
        #expect(scene.root.kind == .canvas && scene.root.children.count == 1)
        let group = scene.root.children[0], node = group.children[0]
        #expect(group.kind == .group && group.transform.childBounds?.width == 200)
        #expect(node.transform.bounds == DrawingRect(x: 10, y: 20, width: 40, height: 20))
        #expect(node.transform.rotation == 90 && node.transform.flipHorizontal)
        #expect(node.geometry?.preset == "rect" && node.fill?.color?.value == "336699")
        #expect(node.line?.width == 1 && node.line?.dash == "dash")
        #expect(node.plainText == "図形内の日本語")
        #expect(scene.placement.isFloating && scene.placement.behindText)
        #expect(scene.placement.horizontal?.offset == 20 && scene.placement.vertical?.alignment == "top")
        #expect(scene.placement.wrap == "Square" && scene.placement.relativeHeight == 42)
        #expect(try Document.scan(data) { _ in }.warnings == result.warnings)
    }
    @Test func svgIsPreferredAndFallbackAssetsStayLazy() throws {
        let image = "<pic:pic><pic:blipFill><a:blip r:embed=\"png\"><a:extLst><a:ext uri=\"svg\"><asvg:svgBlip xmlns:asvg=\"http://schemas.microsoft.com/office/drawing/2016/SVG/main\" r:embed=\"svg\"/></a:ext></a:extLst></a:blip><a:srcRect l=\"10000\" t=\"5000\" r=\"0\" b=\"2500\"/></pic:blipFill><pic:spPr><a:prstGeom prst=\"rect\"/></pic:spPr></pic:pic>"
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\"><rect width=\"100\" height=\"50\" fill=\"blue\"/></svg>"
        let data = makeDocument(drawing(image), extra: ["word/media/vector.svg": svg, "word/media/fallback.png": "synthetic-bytes"], relations: [("svg", "image", "media/vector.svg", false), ("png", "image", "media/fallback.png", false)])
        let d = try Document(data: data)
        guard case .image(let picture) = d.paragraphs[0].inlines[0] else { Issue.record("Expected picture"); return }
        #expect(picture.assetPath == "word/media/vector.svg" && picture.fallbackAssetPath == "word/media/fallback.png")
        #expect(picture.crop == ImageCrop(left: 0.1, top: 0.05, right: 0, bottom: 0.025))
        #expect(try d.asset(at: picture.assetPath!) == Data(svg.utf8))
        #expect(picture.width == 100 && picture.height == 50)
    }
    // Source preservation, per the revised reading/rendering boundary: no automatic glyph substitution.
    @Test func symbolFontsKeepOriginalCharacterCodesAndFontNames() throws {
        let source = "\u{F0A7}§漢字"
        let d = try Document(data: makeDocument("<w:p><w:r><w:rPr><w:rFonts w:ascii=\"Wingdings\"/></w:rPr><w:t>\(source)</w:t><w:sym w:font=\"Symbol\" w:char=\"F0B7\"/></w:r></w:p>"))
        #expect(d.plainText == source + "\u{F0B7}")
        #expect(d.paragraphs[0].runs[0].text == source)
        #expect(d.paragraphs[0].runs[0].formatting.fontName == "Wingdings")
        #expect(d.paragraphs[0].runs[1].symbol == SymbolCharacter(fontName: "Symbol", characterCode: 0xF0B7))
        #expect(d.readWarnings.isEmpty)
    }
    @Test func rubyAndJapaneseParagraphSettingsAreTyped() throws {
        let body = "<w:p><w:pPr><w:kinsoku/><w:wordWrap w:val=\"0\"/><w:autoSpaceDE/><w:autoSpaceDN w:val=\"0\"/><w:textDirection w:val=\"tbRl\"/><w:tabs><w:tab w:pos=\"720\" w:val=\"right\" w:leader=\"dot\"/></w:tabs></w:pPr><w:r><w:rPr><w:rFonts w:eastAsiaTheme=\"minorEastAsia\" w:hint=\"eastAsia\"/><w:em w:val=\"dot\"/></w:rPr><w:ruby><w:rubyPr><w:rubyAlign w:val=\"center\"/><w:hps w:val=\"12\"/><w:hpsBaseText w:val=\"24\"/><w:lid w:val=\"ja-JP\"/></w:rubyPr><w:rt><w:r><w:t>かんじ</w:t></w:r></w:rt><w:rubyBase><w:r><w:t>漢字</w:t></w:r></w:rubyBase></w:ruby></w:r></w:p>"
        let d = try Document(data: makeDocument(body)), p = d.paragraphs[0]
        #expect(p.plainText == "漢字" && p.formatting.kinsoku == true && p.formatting.wordWrap == false)
        #expect(p.formatting.autoSpaceEastAsianLatin == true && p.formatting.autoSpaceEastAsianNumbers == false)
        #expect(p.formatting.textDirection == "tbRl" && p.formatting.tabs == [TabStop(position: 36, alignment: "right", leader: "dot")])
        guard case .ruby(let ruby) = p.inlines[0] else { Issue.record("Expected ruby"); return }
        #expect(ruby.annotation.map(\.plainText).joined() == "かんじ" && ruby.annotationSize == 6 && ruby.baseSize == 12)
        #expect(ruby.base.flatMap(\.runs)[0].formatting.fontThemeEastAsia == "minorEastAsia")
    }
    @Test func foreignFormattingAttributesAreDiagnosed() throws {
        let d = try Document(data: makeDocument("<w:p><w:r><w:rPr><w:b x:val=\"0\"/></w:rPr><w:t>A</w:t></w:r></w:p>"))
        #expect(d.readWarnings.contains { $0.code == .uninterpretedFormatting && $0.element == "b" })
    }
}
