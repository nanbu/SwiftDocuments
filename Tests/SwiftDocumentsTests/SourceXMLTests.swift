import Foundation
import Testing
import SwiftDocuments

@Suite struct SourceXMLTests {
    @Test func originalQualifiedNamesNamespacesAndMixedContentSurvive() throws {
        let xml = "<u:root xmlns:u=\"urn:source\" xmlns:q=\"urn:attribute\" q:kind=\"u:Value\">before<u:child/> after</u:root>"
        let d = try Document(data: makeDocument(paragraph("Body"), extra: ["word/source.xml": xml]))
        let source = try d.readSourceXML(at: "word/source.xml")
        #expect(source.root.qualifiedName == "u:root" && source.root.namespaceBindings["q"] == "urn:attribute")
        #expect(source.root.attributeNames["urn:attribute|kind"] == "q:kind")
        #expect(source.root.attributes["urn:attribute|kind"] == "u:Value")
        #expect(source.root.text == "before after")
        #expect(source.root.descendants(named: "child", namespace: "urn:source").count == 1)
        #expect(source.root.content.count == 3)
        #expect(try d.asset(at: "word/source.xml") == Data(xml.utf8))
    }
    @Test func sourceReadingUsesTheOriginalXMLNodeBudget() throws {
        let xml = "<root>" + String(repeating: "<child/>", count: 30) + "</root>"
        let d = try Document(data: makeDocument(paragraph("Body"), extra: ["word/source.xml": xml]), options: .init(limits: .init(maxXMLNodes: 20)))
        #expect(throws: DocumentError.self) { try d.readSourceXML(at: "word/source.xml") }
    }
    @Test func sourceReadingRejectsDTDWithoutFetchingEntities() throws {
        let xml = "<!DOCTYPE root [<!ENTITY x SYSTEM 'https://example.invalid/never'>]><root>&x;</root>"
        let d = try Document(data: makeDocument(paragraph("Body"), extra: ["word/source.xml": xml]))
        #expect(throws: DocumentError.self) { try d.readSourceXML(at: "word/source.xml") }
    }
    @MainActor @Test func asyncSourceReadingMatchesSynchronousStructure() async throws {
        let d = try Document(data: makeDocument(paragraph("日本語")))
        let expected = try { try d.readSourceXML(at: "word/document.xml") }()
        let result = try await d.readSourceXML(at: "word/document.xml")
        #expect(result.root == expected.root)
        #expect(result.root.qualifiedName == "w:document")
        #expect(result.root.descendants(named: "t", namespace: wordNS).first?.text == "日本語")
    }
}
