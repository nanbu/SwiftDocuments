import Foundation
import Testing
import SwiftDocuments

@Suite struct PackageTests {
    @Test(arguments: [false, true])
    func zip64AndDescriptors(_ zip64: Bool) throws {
        let entries = documentParts(paragraph("ZIP64" )).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        for descriptors in [false, true] {
            #expect(try Document(data: makeZIP(entries, zip64: zip64, descriptors: descriptors)).plainText == "ZIP64")
        }
    }
    @Test func endSignatureInsideComment() throws {
        var comment = Data(repeating: 0, count: 30); comment.set32(0x06054b50, at: 4)
        let entries = documentParts(paragraph("Comment")).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        #expect(try Document(data: makeZIP(entries, comment: comment)).plainText == "Comment")
    }
    @Test(arguments: ["../escape", "/absolute", "a/../b", "a/./b", "a\\b", "a//b", "C:part"])
    func unsafePaths(_ path: String) {
        #expect(throws: DocumentError.self) { try Document.read(makeZIP([(path, Data("x".utf8))])) }
    }
    @Test func duplicateParts() {
        #expect(throws: DocumentError.self) { try Document.read(makeZIP([("a", Data()), ("a", Data())])) }
    }
    @Test func crcMismatch() throws {
        var data = makeDocument(paragraph("CRC"))
        let location = try #require(data.range(of: Data("CRC".utf8)))
        data[location.lowerBound] = 0x58
        #expect(throws: DocumentError.corruptedPackage("CRC mismatch in word/document.xml")) { try Document.read(data) }
    }
    @Test func lazyAssetsValidateCRC() throws {
        var data = makeDocument(paragraph("A"), extra: ["word/asset.bin": "ASSET"])
        let location = try #require(data.range(of: Data("ASSET".utf8)))
        data[location.lowerBound] = 0x58
        let d = try Document(data: data)
        #expect(throws: DocumentError.corruptedPackage("CRC mismatch in word/asset.bin")) { try d.asset(at: "word/asset.bin") }
    }
    @Test(arguments: [0, 1, 2, 10, 21, 22, 45, 100])
    func truncationIsRejected(_ length: Int) {
        let data = makeDocument(paragraph("A"))
        #expect(throws: DocumentError.self) { try Document.read(Data(data.prefix(length))) }
    }
    @Test func localNameMismatch() {
        var data = makeDocument(paragraph("A")); data[30] ^= 1
        #expect(throws: DocumentError.corruptedPackage("local ZIP name mismatch")) { try Document.read(data) }
    }
    @Test func sizeMismatch() {
        var data = makeDocument(paragraph("A")); data.set32(1, at: 18)
        #expect(throws: DocumentError.corruptedPackage("local ZIP size or CRC mismatch")) { try Document.read(data) }
    }
    @Test func overlappingEntries() throws {
        var data = makeZIP([("a", Data("A".utf8)), ("b", Data("B".utf8))])
        let first = try #require(data.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        let second = first.lowerBound + 47
        data.set32(0, at: second + 42)
        data[second + 46] = UInt8(ascii: "a")
        #expect(throws: DocumentError.self) { try Document.read(data) }
    }
    @Test func splitZIP() {
        var data = makeDocument(paragraph("A")); data.set16(1, at: data.count - 18)
        #expect(throws: DocumentError.corruptedPackage("split ZIP is unsupported")) { try Document.read(data) }
    }
    @Test func encryptedZIP() throws {
        var data = makeDocument(paragraph("A"))
        let first = try #require(data.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        data.set16(1, at: first.lowerBound + 8)
        #expect(throws: DocumentError.unsupportedContainer("encrypted ZIP")) { try Document.read(data) }
    }
    @Test(arguments: [PackageLimits(maxEntries: 1), PackageLimits(maxExpandedBytes: 100), PackageLimits(maxPartBytes: 100)])
    func expansionLimits(_ limits: PackageLimits) {
        #expect(throws: DocumentError.self) { try Document.read(makeDocument(paragraph("A")), options: ReadOptions(limits: limits)) }
    }
    @Test func dataSliceUsesRelativeOffsets() throws {
        var padded = Data(repeating: 0, count: 17); padded.append(makeDocument(paragraph("Slice")))
        #expect(try Document(data: padded[17...]).plainText == "Slice")
    }
    @Test(arguments: ["writer.odt", "design.pages"])
    func futureCodecsAreNamed(_ name: String) throws {
        let data = try fixture(name), format: DocumentFormat = name.hasSuffix("odt") ? .odt : .pages
        #expect(try DocumentFormat.detect(data) == format)
        #expect(throws: DocumentError.noCodec(format)) { try Document.read(data) }
    }
    @Test func absentLinkedCodecIsLoud() throws {
        #expect(throws: DocumentError.noCodec(.docm)) { try CodecSet([.docx]).read(fixture("macro.docm")) }
    }
    @Test func explicitCodecDoesNotMisreadMIME() throws {
        #expect(throws: DocumentError.corruptedPackage("codec / MIME mismatch")) { try Document.read(fixture("macro.docm"), format: .docx) }
    }
    @Test func unrelatedZIPIsUnknown() {
        #expect(throws: DocumentError.unknownFormat) { try Document.read(makeZIP([("readme.txt", Data("x".utf8))])) }
    }
    @Test func iWorkSpreadsheetIsNotPages() throws {
        #expect(throws: DocumentError.unknownFormat) { try DocumentFormat.detect(fixture("spreadsheet.iwork")) }
    }
    @Test func oleContainerIsRefused() {
        let data = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        #expect(throws: DocumentError.unsupportedContainer("OLE: legacy DOC または暗号化された Office 文書")) { try Document.read(data) }
    }
    @Test(arguments: ["../../../escape.xml", "https://example.com/file.xml", "..%2f..%2f..%2fescape", "..%5Cescape", "missing.xml"])
    func badInternalRelationships(_ target: String) {
        let data = makeDocument(paragraph("A"), relations: [("bad", "image", target, false)])
        #expect(throws: DocumentError.self) { try Document.read(data) }
    }
    @Test func duplicateRelationshipIDs() {
        let data = makeDocument(paragraph("A"), relations: [("x", "hyperlink", "https://example.com/a", true), ("x", "hyperlink", "https://example.com/b", true)])
        #expect(throws: DocumentError.self) { try Document.read(data) }
    }
    @Test func externalRelationshipNeverFetches() throws {
        let data = makeDocument("<w:p><w:hyperlink r:id=\"x\"><w:r><w:t>Link</w:t></w:r></w:hyperlink></w:p>", relations: [("x", "hyperlink", "https://does-not-exist.invalid/", true)])
        #expect(try Document(data: data).plainText == "Link")
    }
    @Test func missingInlineRelationship() {
        #expect(throws: DocumentError.self) { try Document.read(makeDocument("<w:p><w:hyperlink r:id=\"missing\"/></w:p>")) }
    }
    @Test func styleCycleIsRejected() {
        let styles = "<w:styles xmlns:w=\"\(wordNS)\"><w:style w:styleId=\"A\"><w:basedOn w:val=\"B\"/></w:style><w:style w:styleId=\"B\"><w:basedOn w:val=\"A\"/></w:style></w:styles>"
        let data = makeDocument(paragraph("A"), extra: ["word/styles.xml": styles], relations: [("styles", "styles", "styles.xml", false)])
        #expect(throws: DocumentError.self) { try Document.read(data) }
    }
    @Test func malformedNumberingIsRejected() {
        let numbers = "<w:numbering xmlns:w=\"\(wordNS)\"><w:num w:numId=\"1\"><w:abstractNumId w:val=\"absent\"/></w:num></w:numbering>"
        let data = makeDocument(paragraph("A"), extra: ["word/numbering.xml": numbers], relations: [("num", "numbering", "numbering.xml", false)])
        #expect(throws: DocumentError.self) { try Document.read(data) }
    }
}
