import Foundation
import SwiftDocuments

let wordNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
let relNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
func fixtureURL(_ name: String) -> URL { Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")! }
func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtureURL(name)) }
func paragraph(_ text: String) -> String { "<w:p><w:r><w:t>\(text)</w:t></w:r></w:p>" }
func relationships(_ items: [(String, String, String, Bool)]) -> String {
    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + items.map { id, kind, target, external in
        "<Relationship Id=\"\(id)\" Type=\"\(relNS)/\(kind)\" Target=\"\(target)\"\(external ? " TargetMode=\"External\"" : "")/>"
    }.joined() + "</Relationships>"
}
func documentParts(_ body: String, extra: [String: String] = [:], relations: [(String, String, String, Bool)] = []) -> [String: Data] {
    var parts = [
        "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>",
        "_rels/.rels": relationships([("main", "officeDocument", "word/document.xml", false)]),
        "word/document.xml": "<w:document xmlns:w=\"\(wordNS)\" xmlns:r=\"\(relNS)\" xmlns:x=\"urn:foreign\" xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><w:body>\(body)</w:body></w:document>"
    ].merging(extra) { _, new in new }
    if !relations.isEmpty { parts["word/_rels/document.xml.rels"] = relationships(relations) }
    return parts.mapValues { Data($0.utf8) }
}
func makeDocument(_ body: String, extra: [String: String] = [:], relations: [(String, String, String, Bool)] = []) -> Data {
    makeZIP(documentParts(body, extra: extra, relations: relations).sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
}
func checksum(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) } }
    return ~crc
}
extension Data {
    mutating func append16(_ n: UInt16) { append(UInt8(n & 255)); append(UInt8(n >> 8)) }
    mutating func append32(_ n: UInt32) { append16(UInt16(n & 65535)); append16(UInt16(n >> 16)) }
    mutating func append64(_ n: UInt64) { append32(UInt32(n & 0xffffffff)); append32(UInt32(n >> 32)) }
    mutating func set16(_ n: UInt16, at i: Int) { self[i] = UInt8(n & 255); self[i + 1] = UInt8(n >> 8) }
    mutating func set32(_ n: UInt32, at i: Int) { set16(UInt16(n & 65535), at: i); set16(UInt16(n >> 16), at: i + 2) }
}
/// Deliberately independent stored-ZIP writer for adversarial tests.
func makeZIP(_ entries: [(String, Data)], zip64: Bool = false, descriptors: Bool = false, comment: Data = Data()) -> Data {
    var data = Data(), directory = Data()
    for (name, body) in entries {
        let filename = Data(name.utf8), offset = UInt64(data.count), crc = checksum(body), size = UInt32(body.count)
        var extra = Data()
        if zip64 { extra.append16(1); extra.append16(16); extra.append64(UInt64(size)); extra.append64(UInt64(size)) }
        data.append32(0x04034b50); data.append16(zip64 ? 45 : 20); data.append16(descriptors ? 8 : 0); data.append16(0)
        data.append32(0); data.append32(descriptors ? 0 : crc)
        data.append32(zip64 ? .max : (descriptors ? 0 : size)); data.append32(zip64 ? .max : (descriptors ? 0 : size))
        data.append16(UInt16(filename.count)); data.append16(UInt16(extra.count)); data.append(filename); data.append(extra); data.append(body)
        if descriptors {
            data.append32(0x08074b50); data.append32(crc)
            if zip64 { data.append64(UInt64(size)); data.append64(UInt64(size)) } else { data.append32(size); data.append32(size) }
        }
        if zip64 { extra = Data(); extra.append16(1); extra.append16(24); extra.append64(UInt64(size)); extra.append64(UInt64(size)); extra.append64(offset) }
        directory.append32(0x02014b50); directory.append16(45); directory.append16(zip64 ? 45 : 20)
        directory.append16(descriptors ? 8 : 0); directory.append16(0); directory.append32(0); directory.append32(crc)
        directory.append32(zip64 ? .max : size); directory.append32(zip64 ? .max : size)
        directory.append16(UInt16(filename.count)); directory.append16(UInt16(extra.count)); directory.append16(0)
        directory.append16(0); directory.append16(0); directory.append32(0); directory.append32(zip64 ? .max : UInt32(offset))
        directory.append(filename); directory.append(extra)
    }
    let directoryOffset = UInt64(data.count), directorySize = UInt64(directory.count); data.append(directory)
    if zip64 {
        let endOffset = UInt64(data.count)
        data.append32(0x06064b50); data.append64(44); data.append16(45); data.append16(45)
        data.append32(0); data.append32(0); data.append64(UInt64(entries.count)); data.append64(UInt64(entries.count))
        data.append64(directorySize); data.append64(directoryOffset)
        data.append32(0x07064b50); data.append32(0); data.append64(endOffset); data.append32(1)
    }
    data.append32(0x06054b50); data.append16(0); data.append16(0)
    data.append16(zip64 ? .max : UInt16(entries.count)); data.append16(zip64 ? .max : UInt16(entries.count))
    data.append32(zip64 ? .max : UInt32(directorySize)); data.append32(zip64 ? .max : UInt32(directoryOffset))
    data.append16(UInt16(comment.count)); data.append(comment); return data
}
