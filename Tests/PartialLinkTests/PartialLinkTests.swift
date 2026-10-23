import Foundation
import Testing
import DocumentCore
import DocumentDOCX

@Test func facadeWithoutUmbrella() throws {
    let codecs = CodecSet([.docx, .docm])
    #expect(codecs.formats == [.docx, .docm])
    #expect(codecs.contains(.docx) && !codecs.contains(.pages))
    #expect(try codecs.codec(for: .docx).format == .docx)
    #expect(throws: DocumentError.unknownFormat) { try codecs.read(Data("not a document".utf8)) }
    let codec: any DocumentCodec = DOCXCodec()
    #expect(codec.format == .docx)
    #expect(DocumentFormat.odt.productName == "DocumentODT")
    #expect(DocumentFormat.pages.productName == "DocumentPages")
}

@Test func asyncEntryPointsWithoutUmbrella() async throws {
    let codecs = CodecSet([.docx])
    #expect(try await codecs.readAll(contentsOf: []).isEmpty)
    await #expect(throws: DocumentError.noCodec(.odt)) { try await codecs.read(Data(), format: .odt) }
    await #expect(throws: DocumentError.unknownFormat) { try await codecs.inspect(Data()) }
    #expect(DocumentFormat(fileExtension: "DOCX") == .docx)
}
