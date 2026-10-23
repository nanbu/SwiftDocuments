import Foundation
import DocumentCore

extension PagesCodec {
    /// Generate a modern Pages document using the producer-created blank template.
    /// The basic writer supports body text; rich semantics produce loss warnings.
    public func write(_ document: Document, options: WriteOptions = .init()) throws -> WriteResult {
        let context = BasicWriting(richText: false), model = try context.project(document)
        var paragraphs: [String] = []
        for block in model.blocks {
            try Task.checkCancellation()
            guard case .paragraph(let p) = block else { throw DocumentError.invalidModel("invalid Pages text projection") }
            var text = ""
            for inline in p.inlines {
                switch inline {
                case .lineBreak(.page): text += "\u{5}"
                case .lineBreak(let kind):
                    if kind == .column { context.warn(.flattenedContent, "columnBreak", "Column break is written as a line break.") }
                    text += "\u{2028}"
                default:
                    text += inline.plainText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\u{2028}")
                }
            }
            paragraphs.append(text)
        }
        let text = paragraphs.isEmpty ? "" : paragraphs.joined(separator: "\n") + "\n"
        guard text.utf8.count <= PackageLimits().maxPartBytes else { throw DocumentError.invalidModel("Pages body exceeds the basic writer byte limit") }
        guard let url = Bundle.module.url(forResource: "Blank", withExtension: "pages", subdirectory: "Resources") else { throw DocumentError.missingPart("Blank.pages writing template") }
        let archive = try PackageArchive(Data(contentsOf: url), limits: .init())
        var parts: [String: Data] = [:]
        for path in archive.paths { parts[path] = try archive.read(path) }
        let budget = IWABudget(.init()), part = "Index/Document.iwa"
        guard let original = parts[part], let root = try iwaObjects(original, part: part, budget: budget, firstOnly: true).first,
              let body = try Proto(root.bytes, budget: budget).reference(4, budget: budget) else { throw DocumentError.corruptedPackage("Pages template has no body") }
        parts[part] = try rewritePagesBody(original, bodyID: body, text: text)
        return try context.finish(ZIPWriter.write(parts, compress: options.compress), options: options)
    }
}
private func varintBytes(_ number: UInt64) -> Data {
    var n = number, data = Data()
    while n >= 128 { data.append(UInt8(n & 127) | 128); n >>= 7 }
    data.append(UInt8(n)); return data
}
private func encode(_ message: Proto) -> Data {
    var result = Data()
    for key in message.fields.keys.sorted() {
        for value in message.fields[key]! {
            let wire: UInt64
            switch value { case .integer: wire = 0; case .fixed64: wire = 1; case .bytes: wire = 2; case .fixed32: wire = 5 }
            result += varintBytes(UInt64(key) << 3 | wire)
            switch value {
            case .integer(let n): result += varintBytes(n)
            case .bytes(let b): result += varintBytes(UInt64(b.count)); result.append(contentsOf: b)
            case .fixed32(let n): for i in 0..<4 { result.append(UInt8(truncatingIfNeeded: n >> (8 * i))) }
            case .fixed64(let n): for i in 0..<8 { result.append(UInt8(truncatingIfNeeded: n >> (8 * i))) }
            }
        }
    }
    return result
}
private func rewritePagesBody(_ data: Data, bodyID: UInt64, text: String) throws -> Data {
    let budget = IWABudget(.init()), bytes = try IWorkProbe.decodeChunks(data, limits: .init())
    var cursor = 0, rebuilt = Data(), found = false
    while cursor < bytes.count {
        try Task.checkCancellation()
        let length = try IWorkProbe.varint(bytes, &cursor)
        guard length <= UInt64(bytes.count - cursor) else { throw DocumentError.corruptedPackage("template header length") }
        var header = try Proto(Array(bytes[cursor..<cursor + Int(length)]), budget: budget); cursor += Int(length)
        let id = try header.integer(1)
        var infos: [Proto.Value] = [], payloads = Data()
        for original in try header.allData(2) {
            var info = try Proto(original, budget: budget)
            guard let length = try info.integer(3), length <= UInt64(bytes.count - cursor) else { throw DocumentError.corruptedPackage("template payload length") }
            var payload = Data(bytes[cursor..<cursor + Int(length)]); cursor += Int(length)
            if id == bodyID, try info.integer(1) == 2001 {
                var storage = try Proto(Array(payload), budget: budget)
                guard try storage.integer(1) == 0, !found else { throw DocumentError.corruptedPackage("invalid template body") }
                storage.fields[3] = [.bytes(Array(text.utf8))]
                // All blank-template style/section boundaries are at UTF-16 offset zero.
                payload = encode(storage); found = true
                info.fields[3] = [.integer(UInt64(payload.count))]
            }
            infos.append(.bytes(Array(encode(info)))); payloads += payload
        }
        header.fields[2] = infos
        let encoded = encode(header); rebuilt += varintBytes(UInt64(encoded.count)); rebuilt += encoded; rebuilt += payloads
    }
    guard found else { throw DocumentError.corruptedPackage("missing template BODY storage") }
    var framed = Data()
    for start in stride(from: 0, to: rebuilt.count, by: 65536) {
        try Task.checkCancellation()
        let chunk = Data(rebuilt[start..<min(rebuilt.count, start + 65536)])
        var compressed = varintBytes(UInt64(chunk.count))
        if chunk.count <= 60 { compressed.append(UInt8((chunk.count - 1) << 2)) }
        else { compressed.append(244); compressed.append(UInt8(truncatingIfNeeded: chunk.count - 1)); compressed.append(UInt8(truncatingIfNeeded: (chunk.count - 1) >> 8)) }
        compressed += chunk; framed.append(0)
        for i in 0..<3 { framed.append(UInt8(truncatingIfNeeded: compressed.count >> (8 * i))) }; framed += compressed
    }
    return framed
}
