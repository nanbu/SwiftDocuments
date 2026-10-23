import Foundation
import Testing
import SwiftDocuments

func pbVarint(_ number: UInt64) -> Data {
    var number = number, result = Data()
    while number >= 128 { result.append(UInt8(number & 127) | 128); number >>= 7 }
    result.append(UInt8(number)); return result
}
func pbInt(_ field: Int, _ value: UInt64) -> Data { pbVarint(UInt64(field << 3)) + pbVarint(value) }
func pbBytes(_ field: Int, _ value: Data) -> Data { pbVarint(UInt64(field << 3 | 2)) + pbVarint(UInt64(value.count)) + value }
func pbText(_ field: Int, _ value: String) -> Data { pbBytes(field, Data(value.utf8)) }
func pbFloat(_ field: Int, _ value: Float) -> Data { var result = pbVarint(UInt64(field << 3 | 5)); result.append32(value.bitPattern); return result }
func pbRef(_ field: Int, _ id: UInt64) -> Data { pbBytes(field, pbInt(1, id)) }
func iwaArchive(_ id: UInt64, _ type: UInt64, _ payload: Data) -> Data {
    let info = pbInt(1, type) + pbInt(3, UInt64(payload.count))
    let header = pbInt(1, id) + pbBytes(2, info)
    return pbVarint(UInt64(header.count)) + header + payload
}
func iwaFrames(_ bytes: Data, chunkSize: Int = 65536) -> Data {
    var result = Data(), position = 0
    while position < bytes.count {
        let chunk = Data(bytes[position..<min(bytes.count, position + chunkSize)]), count = chunk.count
        var compressed = pbVarint(UInt64(count))
        if count <= 60 { compressed.append(UInt8((count - 1) << 2)) }
        else { compressed.append(244); compressed.append16(UInt16(count - 1)) }
        compressed += chunk
        result.append(0); result.append(UInt8(compressed.count & 255)); result.append(UInt8((compressed.count >> 8) & 255)); result.append(UInt8((compressed.count >> 16) & 255)); result += compressed
        position += count
    }
    return result
}
func pagesPackage(_ records: Data, otherParts: [(String, Data)] = [], chunkSize: Int = 65536) -> Data {
    makeZIP([("Index/Document.iwa", iwaFrames(records, chunkSize: chunkSize))] + otherParts)
}
private func attributeTable(_ boundaries: [(UInt64, UInt64?)]) -> Data {
    boundaries.reduce(into: Data()) { result, entry in
        var value = pbInt(1, entry.0)
        if let id = entry.1 { value += pbRef(2, id) }
        result += pbBytes(1, value)
    }
}
@Suite struct PagesTests {
    @Test func pagesNestedExtensionsAndUnsupportedValuesRemainDiagnosed() throws {
        let color = pbInt(1, 1) + pbFloat(3, 1) + pbFloat(4, 0) + pbFloat(5, 0) + pbInt(99, 7)
        let style = iwaArchive(20, 2022, pbBytes(1, pbText(1, "Body") + pbInt(99, 1)) + pbInt(10, 1)
            + pbBytes(11, pbBytes(7, color) + pbInt(98, 1))
            + pbBytes(12, pbInt(1, 99) + pbBytes(13, pbInt(1, 0) + pbFloat(2, 1.5) + pbInt(99, 1)) + pbInt(97, 1)))
        let boundary = pbBytes(1, pbInt(1, 0) + pbRef(2, 20) + pbInt(99, 1)) + pbBytes(1, pbInt(1, 4) + pbInt(99, 1)) + pbInt(98, 1)
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbInt(2, 1) + pbText(3, "Text") + pbBytes(5, boundary))
        let data = pagesPackage(root + style + body), result = try Document.read(data)
        let elements = Set(result.warnings.compactMap(\.element))
        #expect(elements.isSuperset(of: ["IWA.2022.field1.field99", "IWA.2022.field10", "IWA.2022.field11.field7.field99", "IWA.2022.field11.field98", "IWA.2022.field12.field13.field99", "IWA.2022.field12.field97", "IWA.2001.field2", "IWA.2001.field5.field98", "IWA.2001.field5.field1.field99", "Pages.alignment"]))
        #expect(result.document.paragraphs[0].formatting.alignment == nil)
        #expect(result.document.paragraphs[0].formatting.lineSpacing == 1.5)
        #expect(result.document.paragraphs[0].runs[0].formatting.color == "FF0000")
        #expect(result.warnings.first { $0.element == "IWA.2001.field5.field1.field99" }?.count == 2)
        var blocks: [Block] = []
        let scan = try Document.scan(data) { blocks.append($0) }
        #expect(blocks.map(\.plainText) == result.document.blocks.map(\.plainText) && scan.warnings == result.warnings)
    }
    @Test func pagesTerminalStyleReferencesAreValidatedWithoutDisplayText() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        for field in [5, 8] {
            for text in ["", "X"] {
                let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, text) + pbBytes(field, attributeTable([(UInt64(text.utf16.count), 99)])))
                #expect(throws: DocumentError.self) { try Document.read(pagesPackage(root + body)) }
                let wrongStyle = iwaArchive(99, field == 5 ? 2021 : 2022, Data())
                #expect(throws: DocumentError.self) { try Document.read(pagesPackage(root + body + wrongStyle)) }
            }
        }
    }
    @Test func pagesOmittedHeadersStillValidateReferenceTargetsAndPreserveBothRoles() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10) + pbRef(5, 30))
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "Body"))
        let section = iwaArchive(30, 10011, pbRef(23, 31) + pbRef(25, 31)), template = iwaArchive(31, 10143, pbRef(1, 40) + pbRef(2, 40) + pbInt(99, 1))
        for target in [Data(), iwaArchive(40, 2021, Data())] {
            let data = pagesPackage(root + body + section + template + target)
            for include in [true, false] {
                #expect(throws: DocumentError.self) { try Document.read(data, options: .init(includeRelatedStories: include)) }
            }
        }
        let storage = iwaArchive(40, 2001, pbInt(1, 1) + pbText(3, "Shared") + pbInt(99, 1) + pbInt(99, 2))
        let result = try Document.read(pagesPackage(root + body + section + template + storage))
        #expect(result.document.stories.map(\.kind) == [.header, .footer])
        #expect(result.document.stories.map(\.plainText) == ["Shared", "Shared"])
        #expect(!result.warnings.contains { $0.element == "IWA.10000.field5" })
        #expect(result.warnings.first { $0.element == "IWA.2001.field99" }?.count == 2)
        #expect(result.warnings.first { $0.element == "IWA.10143.field99" }?.count == 1)
    }
    @Test func pagesReadsReferencedBodyStylesAndUTF16RangesAcrossChunks() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10) + pbFloat(30, 612) + pbFloat(31, 792))
        let paragraphStyle = iwaArchive(20, 2022, pbBytes(1, pbText(1, "Body")) + pbBytes(11, pbFloat(3, 12)) + pbBytes(12, pbInt(1, 2) + pbFloat(21, 6)))
        let characterStyle = iwaArchive(21, 2021, pbBytes(1, pbText(1, "Strong")) + pbBytes(11, pbInt(1, 1) + pbText(5, "Sample Serif")))
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "A😀B\n") + pbText(3, "Second\tLine\u{2028}X\u{5}Z\n") + pbBytes(5, attributeTable([(0, 20)])) + pbBytes(8, attributeTable([(1, 21), (3, nil)])))
        let orphan = iwaArchive(99, 2001, pbInt(1, 3) + pbText(3, "Unrelated"))
        let data = pagesPackage(root + paragraphStyle + body + characterStyle + orphan, chunkSize: 31)
        let result = try Document.read(data), doc = result.document
        #expect(doc.sourceFormat == .pages && doc.paragraphs.count == 2)
        #expect(doc.plainText == "A😀B\nSecond\tLine\nX\u{c}Z")
        #expect(doc.paragraphs[0].formatting.alignment == .center && doc.paragraphs[0].formatting.spacingBefore == 6)
        #expect(doc.paragraphs[0].runs.map(\.text) == ["A", "😀", "B"])
        #expect(doc.paragraphs[0].runs[1].formatting.bold == true && doc.paragraphs[0].runs[0].formatting.bold == nil)
        #expect(doc.sections[0].pageWidth == 612 && doc.styles["20"]?.name == "Body")
        #expect(doc.stories.isEmpty && result.warnings.contains { $0.element == "IWA.2001" })
        #expect(try doc.asset(at: "Index/Document.iwa") == iwaFrames(root + paragraphStyle + body + characterStyle + orphan, chunkSize: 31))
        var blocks: [String] = []
        let scan = try Document.scan(data) { blocks.append($0.plainText) }
        #expect(blocks == doc.blocks.map(\.plainText) && scan.blocksRead == 2 && scan.document.blocks.isEmpty && scan.warnings == result.warnings)
    }
    @Test func pagesHeadersAndUnsupportedAttachmentsRemainSeparate() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10) + pbRef(5, 30))
        let body = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "Body\n") + pbBytes(9, attributeTable([(0, 88)])))
        let section = iwaArchive(30, 10011, pbRef(25, 31)), template = iwaArchive(31, 10143, pbRef(1, 40))
        let header = iwaArchive(40, 2001, pbInt(1, 1) + pbText(3, "Header\n")), attachment = iwaArchive(88, 2003, pbRef(1, 89))
        let data = pagesPackage(root + body + section + template + header + attachment)
        let result = try Document.read(data)
        #expect(result.document.plainText == "Body" && result.document.stories[0].plainText == "Header")
        #expect(result.warnings.contains { $0.element == "IWA.2001.field9" })
        let omitted = try Document.read(data, options: .init(includeRelatedStories: false))
        #expect(omitted.document.stories.isEmpty && omitted.warnings.contains { $0.code == .storiesOmitted })
        enum Consumer: Error { case stop }
        #expect(throws: Consumer.stop) { try Document.scan(data) { _ in throw Consumer.stop } }
    }
    @Test func pagesRejectsDanglingReferencesSurrogatesCyclesAndDuplicates() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        #expect(throws: DocumentError.corruptedPackage("Pages document has neither body nor positioned content")) { try Document.read(pagesPackage(iwaArchive(1, 10000, Data()))) }
        #expect(throws: DocumentError.self) { try Document.read(pagesPackage(root)) }
        for offset: UInt64 in [2, 99] {
            let storage = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "A😀B") + pbBytes(8, attributeTable([(offset, nil)])))
            #expect(throws: DocumentError.self) { try Document.read(pagesPackage(root + storage)) }
        }
        let storage = iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "X"))
        #expect(throws: DocumentError.corruptedPackage("duplicate IWA object ID")) { try Document.read(pagesPackage(root + storage + storage)) }
        let invalidBoolean = iwaArchive(22, 2022, pbBytes(12, pbInt(9, 2)))
        #expect(throws: DocumentError.corruptedPackage("invalid Pages boolean")) { try Document.read(pagesPackage(root + storage + invalidBoolean)) }
        let a = iwaArchive(20, 2021, pbBytes(1, pbRef(3, 21))), b = iwaArchive(21, 2021, pbBytes(1, pbRef(3, 20)))
        #expect(throws: DocumentError.corruptedPackage("Pages style inheritance cycle")) { try Document.read(pagesPackage(root + storage + a + b)) }
        #expect(throws: DocumentError.self) { try Document.read(pagesPackage(iwaArchive(1, 1, Data())), format: .pages) }
        #expect(throws: DocumentError.self) { try Document.read(fixture("minimal.docx"), format: .pages) }
    }
    @Test func pagesInspectLimitsMalformedFramingAndLayoutRecovery() throws {
        let root = iwaArchive(1, 10000, pbRef(4, 10))
        let malformedStorage = iwaArchive(10, 2001, Data([255]))
        let data = pagesPackage(root + malformedStorage)
        let tinyChunks = pagesPackage(root + iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, "Across headers")), chunkSize: 1)
        #expect(try Document.read(tinyChunks).document.plainText == "Across headers")
        #expect(try Document.inspect(data).format == .pages)
        #expect(throws: DocumentError.self) { try Document.read(data) }
        let layout = try Document.read(pagesPackage(iwaArchive(1, 10000, pbRef(3, 50)) + iwaArchive(50, 12345, Data())))
        #expect(layout.document.blocks.isEmpty && layout.warnings.contains { $0.element == "Pages.positionedContent" })
        #expect(throws: DocumentError.self) { try Document.read(pagesPackage(root + iwaArchive(10, 2001, pbInt(1, 0) + pbText(3, String(repeating: "A", count: 1000)))), options: .init(limits: .init(maxPartBytes: 500))) }
        var truncated = iwaFrames(root); truncated.removeLast()
        #expect(throws: DocumentError.self) { try Document.read(makeZIP([("Index/Document.iwa", truncated)])) }
        let overlong = Data([0, 3, 0, 0, 255, 255, 127])
        #expect(throws: DocumentError.self) { try Document.read(makeZIP([("Index/Document.iwa", overlong)])) }
    }
}
