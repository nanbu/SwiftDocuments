import Foundation
import Testing
import SwiftDocuments

private func metadataDocument(_ xml: String) -> Data {
    var parts = documentParts(paragraph("Body"), extra: ["docProps/core.xml": xml])
    parts["_rels/.rels"] = Data(relationships([("main", "officeDocument", "word/document.xml", false), ("core", "metadata/core-properties", "docProps/core.xml", false)]).utf8)
    return makeZIP(parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
}

@Suite struct MetadataTests {
    @Test func foreignMetadataCannotImpersonateStandardFields() throws {
        let xml = "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:x=\"urn:foreign\"><x:creator>Foreign value</x:creator><dc:title>Source title</dc:title></cp:coreProperties>"
        let bytes = metadataDocument(xml), read = try Document.read(bytes)
        #expect(read.document.metadata.creator == nil && read.document.metadata.title == "Source title")
        #expect(read.warnings.contains { $0.element == "{urn:foreign}creator" && $0.part == "docProps/core.xml" })
        #expect(try Document.scan(bytes) { _ in }.warnings == read.warnings)
        #expect(try read.document.asset(at: "docProps/core.xml") == Data(xml.utf8))
    }
    @Test func metadataRootMustMatchItsRelationshipType() throws {
        let bytes = metadataDocument("<x:coreProperties xmlns:x=\"urn:foreign\"><x:title>Unknown</x:title></x:coreProperties>")
        #expect(throws: DocumentError.self) { try Document.read(bytes) }
        #expect(throws: DocumentError.self) { try Document.inspect(bytes) }
    }
}
