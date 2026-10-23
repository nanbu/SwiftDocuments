import Foundation
import DocumentCore

enum PagesAttachment {
    case table(Table)
    case inline(Inline)
}

extension PagesReader {
    func attachment(_ id: UInt64, allowTable: Bool) throws -> PagesAttachment {
        let value = try object(id), record = objects[id]!
        if record.type == 2003 {
            unknown(value, known: [1], record: record)
            guard let drawable = try reference(value, 1, record: record) else { throw DocumentError.corruptedPackage("missing Pages drawable reference") }
            let target = try object(drawable)
            switch objects[drawable]!.type {
            case 6000 where allowTable: return .table(try table(drawable))
            case 3005: return .inline(.image(try image(drawable, value: target)))
            default: break
            }
        }
        warnings.add(.unsupportedContent, part: record.part, element: "Pages.attachment", message: "Unsupported drawable or mixed text/table anchor retained in original IWA part.")
        return .inline(.unsupported(UnsupportedContent(name: "IWA.attachment.\(id)", sourcePart: record.part, rawXML: "", text: "\u{FFFC}")))
    }

    func drawableSize(_ value: Proto, record: IWAObject) throws -> (Double?, Double?) {
        guard let drawable = try value.message(1, budget: budget) else { return (nil, nil) }
        unknown(drawable, known: [1, 8], record: record, path: ".field1")
        guard let geometry = try drawable.message(1, budget: budget) else { return (nil, nil) }
        unknown(geometry, known: [2], record: record, path: ".field1.field1")
        guard let size = try geometry.message(2, budget: budget) else { return (nil, nil) }
        unknown(size, known: [1, 2], record: record, path: ".field1.field1.field2")
        let width = try size.float(1), height = try size.float(2)
        guard width.map({ $0 >= 0 }) ?? true, height.map({ $0 >= 0 }) ?? true else { throw DocumentError.corruptedPackage("negative Pages drawable size") }
        return (width, height)
    }

    func image(_ id: UInt64, value: Proto) throws -> DocumentImage {
        let record = objects[id]!
        unknown(value, known: [1, 11], record: record)
        let size = try drawableSize(value, record: record)
        guard let resource = try reference(value, 11, record: record) else { throw DocumentError.corruptedPackage("missing Pages image resource") }
        if imageResources == nil { imageResources = try resources() }
        guard let entry = imageResources?[resource], archive.entries[entry.path] != nil else { throw DocumentError.corruptedPackage("missing Pages image asset") }
        let drawable = try value.message(1, budget: budget)
        var result = DocumentImage(assetPath: entry.path, name: entry.name, alternativeText: try drawable?.string(8), width: size.0, height: size.1)
        switch (entry.path as NSString).pathExtension.lowercased() {
        case "png": result.contentType = "image/png"
        case "jpg", "jpeg": result.contentType = "image/jpeg"
        case "gif": result.contentType = "image/gif"
        case "svg": result.contentType = "image/svg+xml"
        case "tif", "tiff": result.contentType = "image/tiff"
        default: break
        }
        return result
    }

    func resources() throws -> [UInt64: (path: String, name: String)] {
        var result: [UInt64: (path: String, name: String)] = [:], identifiers = Set<UInt64>()
        guard let record = objects[2], record.type == 11006 else { throw DocumentError.corruptedPackage("missing Pages resource metadata") }
        let metadata = try object(2, type: 11006)
        unknown(metadata, known: [4], record: record)
        for bytes in try metadata.allData(4) {
            let entry = try Proto(bytes, budget: budget)
            unknown(entry, known: [1, 3, 4], record: record, path: ".field4")
            guard let id = try entry.integer(1), id > 0, identifiers.insert(id).inserted else { throw DocumentError.corruptedPackage("duplicate / invalid Pages resource ID") }
            guard let filename = try entry.string(4), !filename.isEmpty else { continue } // Bundled resources have no package file.
            guard !filename.contains("/"), !filename.contains("\\"), !filename.contains(":"), filename != ".", filename != "..", !filename.contains("\0") else { throw DocumentError.corruptedPackage("unsafe Pages image resource path") }
            result[id] = ("Data/" + filename, try entry.string(3) ?? filename)
        }
        return result
    }
}
