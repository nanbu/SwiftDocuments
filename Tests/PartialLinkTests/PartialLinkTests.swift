import Foundation
import Testing
import DocumentCore
import DocumentDOCX

@Test func facadeWithoutUmbrella() throws {
    let codecs = CodecSet([.docx, .docm])
    #expect(throws: DocumentError.unknownFormat) { try codecs.read(Data("not a document".utf8)) }
    let codec: any DocumentCodec = DOCXCodec()
    #expect(codec.format == .docx)
    #expect(DocumentFormat.odt.productName == "DocumentODT")
    #expect(DocumentFormat.pages.productName == "DocumentPages")
}
