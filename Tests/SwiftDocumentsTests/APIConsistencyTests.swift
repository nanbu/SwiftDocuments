import Foundation
import Testing
import SwiftDocuments

private struct APIProbeCodec: DocumentCodec {
    let format: DocumentFormat
    let marker: String
    func read(_ data: Data, options: ReadOptions) throws -> ReadResult {
        var document = Document()
        document.metadata.title = marker
        document.metadata.subject = options.revisions.rawValue
        document.metadata.description = String(options.includeRelatedStories)
        return .init(document: document)
    }
    func inspect(_ data: Data, limits: PackageLimits) throws -> DocumentSummary {
        var metadata = DocumentMetadata()
        metadata.title = marker; metadata.subject = String(limits.maxPartBytes)
        return .init(format: format, metadata: metadata, parts: [])
    }
    func scan(_ data: Data, options: ReadOptions, onBlock: (Block) throws -> Void) throws -> ScanResult {
        var paragraph = Paragraph(); paragraph.inlines = [.text(.init(marker))]
        try onBlock(.paragraph(paragraph))
        return .init(document: try read(data, options: options).document, blocksRead: 1)
    }
}

@Suite struct APIConsistencyTests {
    @Test func codecRegistrationOrderAndReplacement() throws {
        let set = CodecSet([Codec(APIProbeCodec(format: .pages, marker: "first")), .docx,
                            Codec(APIProbeCodec(format: .pages, marker: "last"))])
        #expect(Codec.docx.format == .docx && Codec.docm.format == .docm)
        #expect(set.formats == [.pages, .docx])
        #expect(set.contains(.pages) && !set.contains(.odt))
        #expect(try set.read(Data(), format: .pages).document.metadata.title == "last")
        let selected = try set.codec(for: .pages)
        #expect(selected.format == .pages)
        #expect(try CodecSet([selected]).inspect(Data(), format: .pages).metadata.title == "last")
        #expect(CodecSet([]).formats.isEmpty)
        #expect(throws: DocumentError.noCodec(.odt)) { try set.codec(for: .odt) }
        #expect(CodecSet.all.formats == [.docx, .docm, .odt, .pages, .markdown])
    }

    @Test func explicitDataFormatAndOptionsReachEveryOperation() throws {
        let set = CodecSet([Codec(APIProbeCodec(format: .pages, marker: "selected"))])
        let options = ReadOptions(limits: .init(maxPartBytes: 73), revisions: .original, includeRelatedStories: false)
        let read = try set.read(Data(), format: .pages, options: options)
        #expect(read.document.metadata.subject == "original")
        #expect(read.document.metadata.description == "false")
        #expect(try set.inspect(Data(), format: .pages, limits: options.limits).metadata.subject == "73")
        var texts: [String] = []
        let scanned = try set.scan(Data(), format: .pages, options: options) { texts.append($0.plainText) }
        #expect(texts == ["selected"] && scanned.blocksRead == 1)
        #expect(scanned.document.metadata.description == "false")
        #expect(throws: DocumentError.unknownFormat) { try set.inspect(Data()) }
        #expect(throws: DocumentError.noCodec(.pages)) { try CodecSet([.docx]).inspect(Data(), format: .pages) }
        #expect(throws: DocumentError.noCodec(.pages)) { try CodecSet([.docx]).scan(Data(), format: .pages) { _ in } }
    }

    @Test func customReadingOnlyCodecRetainsDefaultWritingFailure() throws {
        let set = CodecSet([Codec(APIProbeCodec(format: .pages, marker: "read-only"))])
        #expect(throws: DocumentError.writingNotSupported(.pages)) { try set.write(Document(), as: .pages) }
    }
    @Test func facadeFormatOverrideValidatesMIME() throws {
        let macro = try fixture("macro.docm")
        let error = DocumentError.corruptedPackage("codec / MIME mismatch")
        #expect(throws: error) { try Document(data: macro, format: .docx) }
        #expect(throws: error) { try Document.read(macro, format: .docx) }
        #expect(throws: error) { try Document.inspect(macro, format: .docx) }
        var calls = 0
        #expect(throws: error) { try Document.scan(macro, format: .docx) { _ in calls += 1 } }
        #expect(calls == 0)
        #expect(try Document.inspect(macro, format: .docm).format == .docm)
        let scanned = try Document.scan(macro, format: .docm) { _ in calls += 1 }
        #expect(calls == scanned.blocksRead && calls > 0)
    }

    @Test func formatExtensionsDoNotChangeContentDetection() throws {
        for format in DocumentFormat.allCases {
            #expect(DocumentFormat(fileExtension: format.fileExtension.uppercased()) == format)
        }
        #expect(DocumentFormat(fileExtension: "doc") == nil)
        #expect(DocumentFormat(fileExtension: ".docx") == nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pages")
        try fixture("minimal.docx").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Document(contentsOf: url).sourceFormat == .docx)
        #expect(try Document.inspect(contentsOf: url).format == .docx)
        #expect(try DocumentFormat.detect(contentsOf: url) == .docx)
    }

    @Test func explicitURLFormatMatchesBytesAcrossEntryPoints() throws {
        let url = fixtureURL("macro.docm")
        let error = DocumentError.corruptedPackage("codec / MIME mismatch")
        #expect(throws: error) { try Document(contentsOf: url, format: .docx) }
        #expect(throws: error) { try Document.read(contentsOf: url, format: .docx) }
        #expect(throws: error) { try Document.inspect(contentsOf: url, format: .docx) }
        var calls = 0
        #expect(throws: error) { try Document.scan(contentsOf: url, format: .docx) { _ in calls += 1 } }
        #expect(calls == 0)
        let options = ReadOptions(revisions: .original, includeRelatedStories: false)
        let bytes = try Document.read(fixture("macro.docm"), format: .docm, options: options)
        let file = try Document(contentsOf: url, format: .docm, options: options)
        #expect(file.plainText == bytes.document.plainText && file.readWarnings == bytes.warnings)
        let set = CodecSet([Codec(APIProbeCodec(format: .pages, marker: "explicit URL"))])
        let custom = try set.read(contentsOf: url, format: .pages, options: options)
        #expect(custom.document.metadata.title == "explicit URL")
        #expect(custom.document.metadata.subject == "original")
        #expect(try set.inspect(contentsOf: url, format: .pages, limits: .init(maxPartBytes: 73)).metadata.subject == "73")
        let scan = try set.scan(contentsOf: url, format: .pages, options: options) { _ in calls += 1 }
        #expect(calls == 1 && scan.blocksRead == 1 && scan.document.metadata.description == "false")
        #expect(throws: DocumentError.noCodec(.docm)) { try CodecSet([.docx]).inspect(contentsOf: url, format: .docm) }
    }
}
