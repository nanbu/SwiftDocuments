import Foundation
import Testing
import SwiftDocuments

private let odfOffice = "urn:oasis:names:tc:opendocument:xmlns:office:1.0"
private let odfText = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
private let odfStyle = "urn:oasis:names:tc:opendocument:xmlns:style:1.0"
private let odfTable = "urn:oasis:names:tc:opendocument:xmlns:table:1.0"
private let odfBindings = """
xmlns:office="\(odfOffice)" xmlns:text="\(odfText)" xmlns:style="\(odfStyle)" xmlns:table="\(odfTable)" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:x="urn:foreign"
"""
func odtPackage(_ body: String, styles: String = "", automatic: String = "", extras: [(String, Data)] = []) -> Data {
    var entries = [("mimetype", Data("application/vnd.oasis.opendocument.text".utf8)),
                   ("content.xml", Data("<office:document-content \(odfBindings)><office:automatic-styles>\(automatic)</office:automatic-styles><office:body><office:text>\(body)</office:text></office:body></office:document-content>".utf8))]
    if !styles.isEmpty { entries.append(("styles.xml", Data("<office:document-styles \(odfBindings)>\(styles)</office:document-styles>".utf8))) }
    return makeZIP(entries + extras)
}
@Suite struct ODTTests {
    @Test func odtContainerAndInlineExtensionsWarnOncePerSourceOccurrence() throws {
        let body = """
        <text:p x:setting="source">A<text:span x:flag="true">B</text:span><text:tab><x:extra/></text:tab></text:p>
        <table:table x:table="1"><table:table-column x:column="1"/><table:table-row table:number-rows-repeated="3" x:row="1"><table:table-cell table:number-columns-repeated="2" x:cell="1"><text:p>Cell</text:p></table:table-cell></table:table-row></table:table>
        """
        let data = odtPackage(body), result = try Document.read(data)
        #expect(result.document.paragraphs[0].plainText == "AB\t")
        #expect(result.document.tables[0].rows.count == 3)
        for name in ["p", "span", "extra", "table", "table-column", "table-row", "table-cell"] {
            let warning = try #require(result.warnings.first { $0.element.hasSuffix("}" + name) })
            #expect(warning.count == 1)
        }
        let source = try result.document.readSourceXML(at: "content.xml")
        #expect(source.root.descendants(named: "span", namespace: odfText)[0].attributes["urn:foreign|flag"] == "true")
        var blocks: [Block] = []
        let scan = try Document.scan(data) { blocks.append($0) }
        #expect(blocks.map(\.plainText) == result.document.blocks.map(\.plainText) && scan.warnings == result.warnings)
    }
    @Test func odtUnsupportedFormattingNeverInventsResolvedValues() throws {
        let styles = """
        <style:style style:name="P" style:family="paragraph"><style:text-properties fo:font-size="1e308in" style:text-underline-style="alien" style:text-line-through-style="alien"/><style:paragraph-properties fo:text-align="alien" fo:break-before="column" fo:keep-with-next="alien" fo:line-height="NaN%"/></style:style>
        """
        let result = try Document.read(odtPackage("<text:p text:style-name=\"P\">Text</text:p>", automatic: styles))
        let paragraph = result.document.paragraphs[0], text = paragraph.runs[0].formatting
        #expect(text.fontSize == nil && text.underline == nil && text.strike == nil)
        #expect(paragraph.formatting.alignment == nil && paragraph.formatting.pageBreakBefore == nil)
        #expect(paragraph.formatting.keepWithNext == nil && paragraph.formatting.lineSpacing == nil && paragraph.formatting.lineSpacingRule == nil)
        #expect(result.warnings.filter { $0.code == .uninterpretedFormatting }.count == 2)
        #expect(text.rawProperties.contains { $0.contains("alien") })
        #expect(paragraph.formatting.rawProperties.contains { $0.contains("NaN%") })
    }
    @Test(arguments: ["", "text:level=\"zero\"", "text:level=\"0\"", "text:level=\"1\" text:start-value=\"bad\"", "text:level=\"1\" text:start-value=\"0\""])
    func odtMalformedListLevelsNeverDefaultToValidNumbering(_ attributes: String) throws {
        let automatic = "<text:list-style style:name=\"L\"><text:list-level-style-number \(attributes)/></text:list-style>"
        #expect(throws: DocumentError.self) { try Document.read(odtPackage("<text:p/>", automatic: automatic)) }
        #expect(throws: DocumentError.self) { try Document.scan(odtPackage("<text:p/>", automatic: automatic)) { _ in } }
    }
    @Test func odtDuplicateListLevelsAndMalformedNotesThrowEvenWhenStoriesAreOmitted() throws {
        let list = "<text:list-style style:name=\"L\"><text:list-level-style-number text:level=\"1\"/><text:list-level-style-number text:level=\"1\"/></text:list-style>"
        #expect(throws: DocumentError.self) { try Document.read(odtPackage("<text:p/>", automatic: list)) }
        for body in ["", "<text:note-body/><text:note-body/>"] {
            let data = odtPackage("<text:p><text:note>\(body)</text:note></text:p>")
            for include in [true, false] {
                #expect(throws: DocumentError.self) { try Document.read(data, options: .init(includeRelatedStories: include)) }
            }
        }
    }
    @Test func odtAutomaticTableStyleIDReferencesItsActualDeclaration() throws {
        let automatic = "<style:style style:name=\"T\" style:family=\"table\"><style:table-properties style:width=\"2in\"/></style:style>"
        let result = try Document.read(odtPackage("<table:table><table:table-row><table:table-cell><text:p/></table:table-cell></table:table-row></table:table>", automatic: automatic))
        #expect(result.document.tables[0].styleID == nil)
        let styled = try Document.read(odtPackage("<table:table table:style-name=\"T\"/>", automatic: automatic)).document
        #expect(styled.tables[0].styleID == "table:content.xml:T")
        #expect(styled.styles[try #require(styled.tables[0].styleID)] != nil && styled.tables[0].preferredWidth?.value == 144)
    }
    @Test func odtMissingStylesKeepReferenceIDsAndDeclarationSourceParts() throws {
        let automatic = "<style:style style:name=\"P\" style:family=\"paragraph\" style:parent-style-name=\"AbsentBase\"/>"
        let result = try Document.read(odtPackage("<text:p text:style-name=\"P\">Text</text:p><table:table table:style-name=\"AbsentTable\"/>", automatic: automatic))
        #expect(result.document.tables[0].styleID == "table:AbsentTable")
        #expect(result.warnings.filter { $0.code == .invalidReference }.allSatisfy { $0.part == "content.xml" })
        #expect(result.warnings.contains { $0.code == .invalidReference })
    }
    @Test func odtInfrastructureExtensionsAndMalformedStatisticsRemainVisible() throws {
        let content = "<office:document-content \(odfBindings) x:root=\"1\"><office:body x:body=\"1\"><x:body-extension/><office:text x:text=\"1\"><text:p>Body</text:p></office:text></office:body></office:document-content>"
        let metadata = "<office:document-meta \(odfBindings) xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\"><office:meta><meta:document-statistic meta:page-count=\"-1\" meta:word-count=\"bad\" meta:character-count=\"12\"/></office:meta></office:document-meta>"
        let data = makeZIP([("mimetype", Data("application/vnd.oasis.opendocument.text".utf8)), ("content.xml", Data(content.utf8)), ("meta.xml", Data(metadata.utf8))])
        let result = try Document.read(data)
        #expect(result.document.plainText == "Body")
        #expect(result.document.metadata.declaredPages == nil && result.document.metadata.declaredWords == nil)
        for name in ["document-content", "body", "text", "body-extension", "document-statistic"] {
            #expect(result.warnings.contains { $0.element.hasSuffix("}" + name) && $0.count == 1 })
        }
        let scan = try Document.scan(data) { _ in }
        #expect(scan.warnings == result.warnings)
    }
    @Test func odtTextStylesTablesListsAndStories() throws {
        let styles = """
        <office:styles><style:default-style style:family="paragraph"><style:text-properties fo:font-size="11pt"/></style:default-style><style:style style:name="Base" style:family="paragraph"><style:text-properties fo:font-weight="bold"/></style:style><style:style style:name="Body" style:family="paragraph" style:parent-style-name="Base"><style:paragraph-properties fo:text-align="center" fo:margin-left="1in"/></style:style><style:style style:name="Plain" style:family="text"><style:text-properties fo:font-weight="normal"/></style:style><style:style style:name="Cell" style:family="table-cell"><style:table-cell-properties fo:background-color="#ABCDEF"/></style:style><text:list-style style:name="List"><text:list-level-style-number text:level="1" style:num-format="1"/></text:list-style></office:styles><office:master-styles><style:master-page style:name="Standard"><style:header><text:p>Header</text:p></style:header></style:master-page></office:master-styles>
        """
        let body = """
        <text:h text:style-name="Body" text:outline-level="1">A<text:span text:style-name="Plain">😀</text:span><text:s text:c="2"/><text:tab/><text:a xlink:href="https://example.invalid">Link</text:a><text:line-break/>End<text:note text:id="n"><text:note-body><text:p>Note</text:p></text:note-body></text:note></text:h><text:list text:style-name="List"><text:list-item><text:p>Item</text:p></text:list-item></text:list><table:table><table:table-header-rows><table:table-row><table:table-cell table:style-name="Cell" table:number-columns-repeated="2"><text:p>Cell</text:p></table:table-cell></table:table-row></table:table-header-rows><table:table-row table:number-rows-repeated="2"><table:table-cell><text:p>Repeat</text:p></table:table-cell></table:table-row></table:table>
        """
        let data = odtPackage(body, styles: styles), result = try Document.read(data), doc = result.document
        #expect(doc.sourceFormat == .odt && doc.paragraphs[0].plainText == "A😀  \tLink\nEnd")
        #expect(doc.paragraphs[0].formatting.alignment == .center && doc.paragraphs[0].formatting.indentLeft == 72)
        #expect(doc.paragraphs[0].runs[0].formatting.bold == true && doc.paragraphs[0].runs[1].formatting.bold == false)
        #expect(doc.paragraphs[0].defaultTextFormatting.fontSize == 11 && doc.paragraphs[1].list?.id == "List")
        #expect(doc.tables[0].rows.count == 3 && doc.tables[0].rows[0].cells.count == 2)
        #expect(doc.tables[0].rows[0].isHeader && doc.tables[0].rows[0].cells[0].shading == "ABCDEF")
        #expect(doc.stories.map(\.plainText) == ["Note", "Header"])
        var text: [String] = []
        let scan = try Document.scan(data) { text.append($0.plainText) }
        #expect(text == doc.blocks.map(\.plainText) && scan.document.blocks.isEmpty && scan.warnings == result.warnings)
        let omitted = try Document.read(data, options: .init(includeRelatedStories: false))
        #expect(omitted.document.stories.isEmpty && omitted.warnings.contains { $0.code == .storiesOmitted })
    }
    @Test func odtImagesMetadataAndInspectWithoutBodyParsing() throws {
        let meta = "<office:document-meta xmlns:office=\"\(odfOffice)\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><office:meta><dc:title>Sample</dc:title><dc:creator>Sample Author</dc:creator></office:meta></office:document-meta>"
        let image = Data([1, 2, 3, 4])
        let data = odtPackage("<text:p><draw:frame text:anchor-type=\"as-char\" svg:width=\"1in\"><draw:image xlink:href=\"Pictures/sample.bin\"/></draw:frame><draw:frame text:anchor-type=\"page\"><draw:text-box><text:p>Positioned</text:p></draw:text-box></draw:frame></text:p>", extras: [("meta.xml", Data(meta.utf8)), ("Pictures/sample.bin", image)])
        let result = try Document.read(data)
        #expect(result.document.metadata.title == "Sample" && result.document.plainText.isEmpty)
        if case .image(let value) = result.document.paragraphs[0].inlines[0] {
            #expect(value.width == 72 && value.assetPath == "Pictures/sample.bin")
            #expect(try result.document.asset(at: value.assetPath!) == image)
        } else { Issue.record("missing image") }
        #expect(result.warnings.contains { $0.element.contains("frame") })
        let malformed = makeZIP([("mimetype", Data("application/vnd.oasis.opendocument.text".utf8)), ("content.xml", Data("<broken".utf8)), ("meta.xml", Data(meta.utf8))])
        #expect(try Document.inspect(malformed).metadata.title == "Sample")
        #expect(throws: DocumentError.self) { try Document.read(malformed) }
    }
    @Test func odtRejectsMalformedCyclesRepetitionAndEncryption() throws {
        #expect(throws: DocumentError.self) { try Document.read(odtPackage("<table:table><table:table-row table:number-rows-repeated=\"-1\"/></table:table>")) }
        let large = odtPackage("<table:table><table:table-row table:number-rows-repeated=\"100\"><table:table-cell table:number-columns-repeated=\"100\"><text:p>X</text:p></table:table-cell></table:table-row></table:table>")
        #expect(throws: DocumentError.self) { try Document.read(large, options: .init(limits: .init(maxXMLNodes: 500))) }
        let cycle = "<office:styles><style:style style:name=\"A\" style:family=\"paragraph\" style:parent-style-name=\"B\"/><style:style style:name=\"B\" style:family=\"paragraph\" style:parent-style-name=\"A\"/></office:styles>"
        #expect(throws: DocumentError.corruptedPackage("ODF style inheritance cycle")) { try Document.read(odtPackage("<text:p/>", styles: cycle)) }
        let manifest = "<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\"><manifest:file-entry manifest:full-path=\"content.xml\"><manifest:encryption-data/></manifest:file-entry></manifest:manifest>"
        #expect(throws: DocumentError.unsupportedContainer("encrypted ODF")) { try Document.inspect(odtPackage("", extras: [("META-INF/manifest.xml", Data(manifest.utf8))])) }
        #expect(throws: DocumentError.self) { try Document.read(makeZIP([("mimetype", Data("application/vnd.oasis.opendocument.text".utf8)), ("content.xml", Data("<document/>".utf8))])) }
    }
    @Test func odtAutomaticStyleScopeAndExplicitBooleanInheritance() throws {
        let common = "<office:styles><style:style style:name=\"Body\" style:family=\"paragraph\"><style:text-properties fo:font-weight=\"bold\"/></style:style></office:styles><office:automatic-styles><style:style style:name=\"P1\" style:family=\"paragraph\"><style:text-properties fo:font-style=\"italic\"/></style:style></office:automatic-styles>"
        let automatic = "<style:style style:name=\"P1\" style:family=\"paragraph\" style:parent-style-name=\"Body\"><style:text-properties fo:font-weight=\"normal\" fo:font-size=\"14pt\"/></style:style>"
        let result = try Document.read(odtPackage("<text:p text:style-name=\"P1\">Body</text:p>", styles: common, automatic: automatic))
        let run = result.document.paragraphs[0].runs[0]
        #expect(run.formatting.bold == false && run.formatting.italic == nil && run.formatting.fontSize == 14)
        #expect(result.document.paragraphs[0].styleID == "paragraph:content.xml:P1")
        #expect(result.document.styles["paragraph:styles.xml:P1"] != nil)
    }
    @Test func odtLibreOfficeProducerMatchesIndependentOracle() throws {
        struct Oracle: Decodable { var paragraphs: [String]; var tables: [[[String]]]; var header: String; var footer: String }
        let oracle = try JSONDecoder().decode(Oracle.self, from: fixture("producer-oracle.json"))
        let result = try Document.read(fixture("libreoffice.odt")), doc = result.document
        let top = doc.blocks.compactMap { if case .paragraph(let p) = $0 { p.plainText } else { nil } }
        #expect(top == oracle.paragraphs)
        #expect(doc.tables.map { $0.rows.map { $0.cells.map(\.plainText) } } == oracle.tables)
        #expect(doc.stories.first { $0.kind == .header }?.plainText == oracle.header)
        #expect(doc.stories.first { $0.kind == .footer }?.plainText == oracle.footer)
        let emphasized = try #require(doc.paragraphs.first { $0.plainText.contains("emoji") })
        #expect(emphasized.runs.first { $0.text == "太字" }?.formatting.bold == true)
        #expect(emphasized.runs.first { $0.text == "太字" }?.formatting.fontSize == 14)
        #expect(emphasized.runs.first { $0.text == "斜体" }?.formatting.italic == true)
        let images = doc.paragraphs.flatMap(\.inlines).compactMap { if case .image(let image) = $0 { image } else { nil } }
        let image = try #require(images.first)
        #expect(image.width == 18 && images.count == 1)
        #expect(try doc.asset(at: image.assetPath!).starts(with: [137, 80, 78, 71]))
        var scanned: [String] = []
        let scan = try Document.scan(fixture("libreoffice.odt")) { scanned.append($0.plainText) }
        #expect(scan.warnings == result.warnings && scanned == doc.blocks.map(\.plainText))
    }
    @Test func odtUnknownNamespacesAndCallbacksRemainVisible() throws {
        let data = odtPackage("<x:p>Foreign</x:p><text:p>A<text:unknown>B</text:unknown></text:p>")
        let result = try Document.read(data)
        #expect(result.document.plainText == "\nAB" && result.warnings.count == 2)
        enum Stop: Error { case consumer }
        #expect(throws: Stop.consumer) { try Document.scan(data) { _ in throw Stop.consumer } }
        #expect(throws: DocumentError.self) { try Document.read(fixture("minimal.docx"), format: .odt) }
    }
}
