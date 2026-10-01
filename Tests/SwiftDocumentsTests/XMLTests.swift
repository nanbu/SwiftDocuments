import Foundation
import Testing
import SwiftDocuments
@testable import DocumentCore

@Suite struct XMLTests {
    @Test(arguments: [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian])
    func encodings(_ encoding: String.Encoding) throws {
        var parts = documentParts(paragraph("日本語 📄"))
        let source = String(decoding: parts["word/document.xml"]!, as: UTF8.self)
        if encoding == .utf8 { parts["word/document.xml"] = Data(source.utf8) }
        else {
            var data = Data(encoding == .utf16LittleEndian ? [0xff, 0xfe] : [0xfe, 0xff])
            data.append(source.data(using: encoding)!); parts["word/document.xml"] = data
        }
        #expect(try Document(data: makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })).plainText == "日本語 📄")
    }
    @Test(arguments: [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian])
    func dtdIsRejected(_ encoding: String.Encoding) throws {
        var parts = documentParts("")
        let source = "<!DOCTYPE doc [<!ENTITY external SYSTEM 'file:///etc/passwd'>]><w:document xmlns:w=\"\(wordNS)\"><w:body><w:p><w:r><w:t>&external;</w:t></w:r></w:p></w:body></w:document>"
        var data = encoding == .utf8 ? Data() : Data(encoding == .utf16LittleEndian ? [0xff, 0xfe] : [0xfe, 0xff])
        data.append(source.data(using: encoding)!); parts["word/document.xml"] = data
        #expect(throws: DocumentError.self) { try Document.read(makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })) }
    }
    @Test func malformedXMLThrows() {
        #expect(throws: DocumentError.self) { try Document.read(makeDocument("<w:p><w:r>")) }
    }
    @Test(arguments: ["<root><child></root>", "<root>", "<root/><other/>", "<root a='1' a='2'/>", "<root>&missing;</root>"])
    func parserRecoveryIsRejected(_ xml: String) {
        #expect(throws: DocumentError.self) { try XMLTree.parse(Data(xml.utf8), part: "malformed", limits: .init()) }
    }
    @Test func excessiveDepthThrows() {
        let body = String(repeating: "<x:wrapper>", count: 20) + String(repeating: "</x:wrapper>", count: 20)
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(body), options: ReadOptions(limits: PackageLimits(maxXMLDepth: 10))) }
    }
    @Test func nodeLimitThrows() {
        let body = (0..<50).map { _ in paragraph("A") }.joined()
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(body), options: ReadOptions(limits: PackageLimits(maxXMLNodes: 20))) }
    }
    @Test func prefixesDoNotDetermineMeaning() throws {
        var parts = documentParts(paragraph("Alias"))
        let xml = String(decoding: parts["word/document.xml"]!, as: UTF8.self).replacingOccurrences(of: "w:", with: "z:").replacingOccurrences(of: "xmlns:w", with: "xmlns:z")
        parts["word/document.xml"] = Data(xml.utf8)
        #expect(try Document(data: makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })).plainText == "Alias")
    }
    @Test func foreignElementsCannotImpersonateWord() throws {
        let d = try Document(data: makeDocument("<x:p><x:r><x:t>Foreign</x:t></x:r></x:p>"))
        #expect(d.paragraphs.isEmpty)
        #expect(d.blocks.count == 1)
        #expect(d.readWarnings.contains { $0.code == .unsupportedContent })
    }
    @Test func rawXMLKeepsNamespacesAndOrder() throws {
        let xml = "<u:unknown xmlns:u=\"urn:u\" xmlns:q=\"urn:q\" q:attr=\"a&amp;b\">left<q:t>mid</q:t>right</u:unknown>"
        let root = try XMLTree.parse(Data(xml.utf8), part: "test", limits: .init())
        let reparsed = try XMLTree.parse(Data(root.xml.utf8), part: "raw", limits: .init())
        #expect(reparsed.namespace == "urn:u")
        #expect(reparsed.attributes["urn:q|attr"] == "a&b")
        #expect(reparsed.text == "leftmidright")
    }
    @Test func whitespaceAndEntitiesArePreserved() throws {
        let d = try Document(data: makeDocument("<w:p><w:r><w:t xml:space=\"preserve\">  A &lt; B &amp; C  </w:t></w:r></w:p>"))
        #expect(d.plainText == "  A < B & C  ")
    }
    @Test func scanReleasesBodyNodes() throws {
        let body = (0..<5000).map { _ in paragraph("A") }.joined()
        let xml = documentParts(body)["word/document.xml"]!
        var count = 0
        let root = try XMLTree.parse(xml, part: "body", limits: .init()) { _ in count += 1 }
        #expect(count == 5000)
        #expect(root.child("body")?.children.isEmpty == true)
    }
}
