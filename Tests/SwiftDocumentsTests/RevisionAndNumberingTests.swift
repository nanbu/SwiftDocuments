import Foundation
import Testing
import SwiftDocuments

@Suite struct RevisionAndNumberingTests {
    @Test func pictureListMarkersKeepLazyImageReferencesAndSourceXML() throws {
        let numbering = "<w:numbering xmlns:w=\"\(wordNS)\" xmlns:r=\"\(relNS)\" xmlns:v=\"urn:schemas-microsoft-com:vml\"><w:numPicBullet w:numPicBulletId=\"9\"><w:pict><v:shape style=\"width:8pt;height:8pt\"><v:imagedata r:id=\"image\"/></v:shape></w:pict></w:numPicBullet><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"source\"/><w:lvlPicBulletId w:val=\"9\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        let data = makeDocument(paragraph("Item"), extra: ["word/numbering.xml": numbering,
            "word/_rels/numbering.xml.rels": relationships([("image", "image", "media/marker.png", false)]),
            "word/media/marker.png": "SYNTHETIC-IMAGE-BYTES"], relations: [("n", "numbering", "numbering.xml", false)])
        let document = try Document(data: data)
        let picture = try #require(document.numbering["1"]?.levels[0]?.picture)
        #expect(picture.assetPath == "word/media/marker.png" && picture.rawXML.contains("numPicBullet"))
        #expect(try document.asset(at: picture.assetPath!) == Data("SYNTHETIC-IMAGE-BYTES".utf8))
        #expect(document.numbering["1"]?.levels[0]?.text == "source")
        #expect(!document.readWarnings.contains { $0.part == "word/media/marker.png" && $0.code == .unsupportedPart })
    }
    @Test func missingPictureMarkersWarnAndUnknownNumberingPropertiesStayVisible() throws {
        let numbering = "<w:numbering xmlns:w=\"\(wordNS)\" xmlns:x=\"urn:future\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:lvlPicBulletId w:val=\"42\"/><x:future/><w:numFmt w:val=\"decimal\" x:mode=\"new\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        let d = try Document(data: makeDocument(paragraph("source"), extra: ["word/numbering.xml": numbering], relations: [("n", "numbering", "numbering.xml", false)]))
        #expect(d.numbering["1"]?.levels[0]?.picture == nil)
        #expect(d.readWarnings.contains { $0.element == "lvlPicBulletId" && $0.code == .invalidReference })
        #expect(d.readWarnings.contains { $0.element == "future" && $0.code == .uninterpretedFormatting })
        #expect(d.readWarnings.contains { $0.element == "numFmt" && $0.code == .uninterpretedFormatting })
    }
    @Test(arguments: ["bad", "-1", "9"])
    func invalidNumberingLevelTextIsNeverDefaultedToZero(_ index: String) throws {
        let numbering = "<w:numbering xmlns:w=\"\(wordNS)\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"\(index)\"/></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(paragraph("source"), extra: ["word/numbering.xml": numbering], relations: [("n", "numbering", "numbering.xml", false)])) }
    }
    @Test func invalidParagraphNumberingLevelIsNeverDefaultedToZero() throws {
        let body = "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"invalid\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>Source</w:t></w:r></w:p>"
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(body)) }
    }
    @Test func foreignFontPropertiesCannotImpersonateWordProperties() throws {
        let fonts = "<w:fonts xmlns:w=\"\(wordNS)\" xmlns:x=\"urn:foreign\"><w:font w:name=\"Source\"><x:charset x:val=\"02\"/><w:pitch w:val=\"variable\" x:extra=\"preserved\"/></w:font><x:font x:name=\"foreign\"/></w:fonts>"
        let d = try Document(data: makeDocument(paragraph("Source"), extra: ["word/fontTable.xml": fonts], relations: [("f", "fontTable", "fontTable.xml", false)]))
        #expect(d.fonts.count == 1 && d.fonts[0].charset == nil && d.fonts[0].pitch == "variable")
        #expect(Set(d.readWarnings.filter { $0.code == .uninterpretedFormatting }.map(\.element)).isSuperset(of: ["charset", "pitch", "font"]))
    }
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func deletedParagraphMarksJoinOnlyFinalView(_ view: ReadOptions.RevisionView) throws {
        let body = "<w:p><w:pPr><w:rPr><w:del w:id=\"1\" w:author=\"Sample Author\"/></w:rPr></w:pPr><w:r><w:t>前</w:t></w:r></w:p>" + paragraph("後")
        let data = makeDocument(body), options = ReadOptions(revisions: view)
        let read = try Document.read(data, options: options)
        #expect(read.document.plainText == (view == .final ? "前後" : "前\n後"))
        var blocks: [Block] = []
        let scan = try Document.scan(data, options: options) { blocks.append($0) }
        #expect(blocks.map(\.plainText).joined(separator: "\n") == read.document.plainText)
        #expect(scan.warnings == read.warnings && scan.blocksRead == read.document.blocks.count)
    }
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func insertedParagraphMarksJoinOnlyOriginalView(_ view: ReadOptions.RevisionView) throws {
        let data = makeDocument("<w:p><w:pPr><w:rPr><w:ins w:id=\"1\"/></w:rPr></w:pPr><w:r><w:t>A</w:t></w:r></w:p>" + paragraph("B"))
        let d = try Document(data: data, options: .init(revisions: view))
        #expect(d.plainText == (view == .original ? "AB" : "A\nB"))
    }
    @Test(arguments: [ReadOptions.RevisionView.final, .original, .all])
    func formerRunAndParagraphPropertiesFollowRevisionView(_ view: ReadOptions.RevisionView) throws {
        let body = "<w:p><w:pPr><w:jc w:val=\"center\"/><w:pPrChange w:id=\"3\" w:author=\"Sample Author\"><w:pPr><w:jc w:val=\"right\"/></w:pPr></w:pPrChange></w:pPr><w:r><w:rPr><w:b/><w:rPrChange w:id=\"4\" w:author=\"Sample Author\"><w:rPr><w:i/></w:rPr></w:rPrChange></w:rPr><w:t>Changed</w:t></w:r></w:p>"
        let d = try Document(data: makeDocument(body), options: .init(revisions: view)), p = d.paragraphs[0], run = p.runs[0]
        #expect(p.formatting.alignment == (view == .original ? .right : .center))
        #expect(run.formatting.bold == (view == .original ? nil : true))
        #expect(run.formatting.italic == (view == .original ? true : nil))
        #expect(p.formattingChange?.previous.alignment == .right && run.formattingChange?.previous.italic == true)
        #expect(run.formattingChange?.revision.id == "4" && p.formattingChange?.revision.author == "Sample Author")
    }
    @Test func numberingKeepsSourceLevelsRestartsAndLabelPatterns() throws {
        let definitions = "<w:numbering xmlns:w=\"\(wordNS)\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"3\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/></w:lvl><w:lvl w:ilvl=\"1\"><w:start w:val=\"1\"/><w:numFmt w:val=\"lowerLetter\"/><w:lvlText w:val=\"%1.%2)\"/><w:suff w:val=\"space\"/></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        func item(_ level: Int) -> String { "<w:p><w:pPr><w:numPr><w:numId w:val=\"1\"/><w:ilvl w:val=\"\(level)\"/></w:numPr></w:pPr><w:r><w:t>項目</w:t></w:r></w:p>" }
        let data = makeDocument([0,1,1,0,1].map(item).joined(), extra: ["word/numbering.xml": definitions], relations: [("n", "numbering", "numbering.xml", false)])
        let read = try Document.read(data)
        #expect(read.document.paragraphs.compactMap { $0.list?.level } == [0,1,1,0,1])
        #expect(read.document.numbering["1"]?.levels[0]?.start == 3)
        #expect(read.document.numbering["1"]?.levels[1]?.suffix == "space")
        #expect(read.document.numbering["1"]?.levels[1]?.text == "%1.%2)")
        #expect(read.document.numbering["1"]?.levels[1]?.format == "lowerLetter")
        var references: [ListReference] = []
        let scan = try Document.scan(data) { references += $0.paragraphs.compactMap(\.list) }
        #expect(references == read.document.paragraphs.compactMap(\.list))
        #expect(scan.warnings == read.warnings)
        #expect(try read.document.asset(at: "word/numbering.xml") == Data(definitions.utf8))
    }
    @Test func fontTableAndThemePreserveSourceDefinitions() throws {
        let fonts = "<w:fonts xmlns:w=\"\(wordNS)\"><w:font w:name=\"Symbol\"><w:charset w:val=\"00\"/></w:font><w:font w:name=\"Symbol\"><w:charset w:val=\"02\"/></w:font></w:fonts>"
        let theme = "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:themeElements><a:clrScheme name=\"Source\"><a:accent1><a:srgbClr val=\"123456\"/></a:accent1></a:clrScheme><a:fontScheme name=\"Source\"><a:majorFont><a:latin typeface=\"Source Latin\"/><a:font script=\"Jpan\" typeface=\"Source Japanese\"/></a:majorFont><a:minorFont><a:latin typeface=\"Minor Latin\"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>"
        let d = try Document(data: makeDocument(paragraph("原本"), extra: ["word/fontTable.xml": fonts, "word/theme.xml": theme], relations: [("f","fontTable","fontTable.xml",false),("t","theme","theme.xml",false)]))
        #expect(d.fonts.map(\.name) == ["Symbol", "Symbol"])
        #expect(d.fonts.map(\.charset) == ["00", "02"])
        #expect(d.theme?.majorFonts["Jpan"] == "Source Japanese" && d.theme?.majorFonts["latin"] == "Source Latin")
        #expect(d.theme?.colors["accent1"] == "123456")
    }
}
