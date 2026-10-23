import Foundation
import Testing
import SwiftDocuments

private let equationNS = "http://schemas.openxmlformats.org/officeDocument/2006/math"
private func math(_ content: String, strict: Bool = false) -> String {
    "<m:oMath xmlns:m=\"\(strict ? "http://purl.oclc.org/ooxml/officeDocument/math" : equationNS)\">\(content)</m:oMath>"
}
private func mathText(_ text: String) -> String { "<m:r><m:t>\(text)</m:t></m:r>" }

@Suite struct EquationTests {
    @Test func supportedMathChoiceTakesPrecedenceOverFallbackText() throws {
        let choice = "<mc:AlternateContent xmlns:m=\"\(equationNS)\"><mc:Choice Requires=\"m\"><m:oMath>\(mathText("x"))</m:oMath></mc:Choice><mc:Fallback><w:r><w:t>fallback</w:t></w:r></mc:Fallback></mc:AlternateContent>"
        let read = try Document.read(makeDocument("<w:p>\(choice)</w:p>"))
        #expect(read.document.plainText == "x")
        guard case .equation = read.document.paragraphs[0].inlines[0] else { Issue.record("Expected supported math choice"); return }
    }
    @Test(arguments: [false, true])
    func fractionsRootsAndScriptsRetainTheirArgumentStructure(_ strict: Bool) throws {
        let content = "<m:f><m:fPr><m:type m:val=\"lin\"/></m:fPr><m:num>\(mathText("x"))</m:num><m:den><m:rad><m:deg>\(mathText("3"))</m:deg><m:e><m:sSup><m:e>\(mathText("y"))</m:e><m:sup>\(mathText("2"))</m:sup></m:sSup></m:e></m:rad></m:den></m:f>"
        let result = try Document.read(makeDocument("<w:p><w:r><w:t>式：</w:t></w:r>\(math(content, strict: strict))</w:p>"))
        guard case .equation(let value) = result.document.paragraphs[0].inlines[1] else { Issue.record("Expected equation"); return }
        #expect(value.dialect == .omml && value.part == "word/document.xml")
        #expect(value.root.kind == .math && value.root.children[0].kind == .fraction)
        let fraction = value.root.children[0]
        #expect(fraction.children.map(\.kind) == [.properties, .numerator, .denominator])
        #expect(fraction.children[0].children[0].kind == .property)
        #expect(fraction.children[2].children[0].kind == .radical)
        #expect(value.lexicalText == "x3y2" && result.document.plainText == "式：x3y2")
        #expect(result.warnings.isEmpty)
        #expect(value.source.namespace == (strict ? "http://purl.oclc.org/ooxml/officeDocument/math" : equationNS))
        let encoded = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(Equation.self, from: encoded) == value)
    }
    @Test func matricesDelimitersAndNaryPropertiesDoNotInventLinearNotation() throws {
        let matrix = "<m:d><m:dPr><m:begChr m:val=\"[\"/><m:endChr m:val=\"]\"/></m:dPr><m:e><m:m><m:mr><m:e>\(mathText("a"))</m:e><m:e>\(mathText("b"))</m:e></m:mr><m:mr><m:e>\(mathText("c"))</m:e><m:e>\(mathText("d"))</m:e></m:mr></m:m></m:e></m:d>"
        let nary = "<m:nary><m:naryPr><m:chr m:val=\"∑\"/></m:naryPr><m:sub>\(mathText("i=1"))</m:sub><m:sup>\(mathText("n"))</m:sup><m:e>\(mathText("i"))</m:e></m:nary>"
        let d = try Document(data: makeDocument("<w:p>\(math(matrix + nary))</w:p>"))
        guard case .equation(let value) = d.paragraphs[0].inlines[0] else { Issue.record("Expected equation"); return }
        #expect(value.root.children.map(\.kind) == [.delimiter, .nary])
        #expect(value.source.descendants(named: "mr").count == 2)
        #expect(value.lexicalText == "abcdi=1ni")
        #expect(d.readWarnings.isEmpty)
    }
    @Test func equationParagraphsAndRelatedStoriesMatchScan() throws {
        let standalone = "<m:oMathPara xmlns:m=\"\(equationNS)\"><m:oMath>\(mathText("α"))</m:oMath></m:oMathPara>"
        let header = "<w:hdr xmlns:w=\"\(wordNS)\"><w:p>\(math(mathText("β")))</w:p></w:hdr>"
        let data = makeDocument(standalone + paragraph("after"), extra: ["word/header.xml": header], relations: [("hdr", "header", "header.xml", false)])
        let read = try Document.read(data)
        var blocks: [Block] = []
        let scan = try Document.scan(data) { blocks.append($0) }
        #expect(read.document.plainText == "α\nafter")
        #expect(blocks.map(\.plainText) == read.document.blocks.map(\.plainText))
        #expect(scan.warnings == read.warnings && scan.blocksRead == 2)
        #expect(read.document.stories[0].plainText == "β")
    }
    @Test(arguments: [
        "<m:f><m:num/></m:f>",
        "<m:f><m:num/><m:den/><m:den/></m:f>",
        "<m:sSup><m:e/></m:sSup>",
        "<m:rad><m:e/></m:rad>",
        "<m:f><x:num xmlns:x=\"urn:foreign\"/><m:den/></m:f>"
    ])
    func missingDuplicateAndForeignArgumentsAreRejected(_ content: String) throws {
        #expect(throws: DocumentError.self) { try Document.read(makeDocument("<w:p>\(math(content))</w:p>")) }
    }
    @Test func unknownEquationNodesKeepMixedContentAndWarn() throws {
        let content = "<x:future xmlns:x=\"urn:future\" x:mode=\"opaque\">before<m:r><m:t>x</m:t></m:r> after</x:future>"
        let read = try Document.read(makeDocument("<w:p>\(math(content))</w:p>"))
        guard case .equation(let value) = read.document.paragraphs[0].inlines[0] else { Issue.record("Expected equation"); return }
        #expect(value.root.children[0].kind == .native)
        #expect(value.source.children[0].text == "beforex after")
        #expect(value.source.children[0].attributes["urn:future|mode"] == "opaque")
        #expect(read.warnings.contains { $0.element == "{urn:future}future" && $0.code == .unsupportedContent })
    }
}
