import Foundation

package struct Relationship: Sendable {
    package let id: String
    package let type: String
    package let target: String
    package let path: String?
    package var isExternal: Bool { path == nil }
}
package struct OPCPackage: Sendable {
    package let archive: PackageArchive
    package let contentTypes: [String: String]
    package let defaults: [String: String]
    package let mainPart: String
    package let format: DocumentFormat
    package let limits: PackageLimits

    package init(_ data: Data, limits: PackageLimits) throws {
        archive = try PackageArchive(data, limits: limits); self.limits = limits
        let types = try XMLTree.parse(archive.read("[Content_Types].xml"), part: "[Content_Types].xml", limits: limits)
        guard types.name == "Types", types.namespace == XMLNamespace.contentTypes else { throw DocumentError.corruptedPackage("invalid content types root") }
        var overrides: [String: String] = [:], defs: [String: String] = [:]
        for child in types.children {
            guard child.namespace == XMLNamespace.contentTypes else { throw DocumentError.corruptedPackage("invalid content type namespace") }
            if child.name == "Override", let part = child.attr("PartName"), part.hasPrefix("/"), let mime = child.attr("ContentType") {
                let path = try Self.resolve(String(part.dropFirst()), from: "")
                guard overrides[path] == nil else { throw DocumentError.corruptedPackage("duplicate content type override") }
                overrides[path] = mime
            } else if child.name == "Default", let ext = child.attr("Extension"), let mime = child.attr("ContentType") {
                let key = ext.lowercased()
                guard defs[key] == nil else { throw DocumentError.corruptedPackage("duplicate default content type") }; defs[key] = mime
            } else { throw DocumentError.corruptedPackage("invalid content type entry") }
        }
        contentTypes = overrides; defaults = defs
        let roots = try Self.relationships(archive: archive, source: "", limits: limits, required: true)
        let mains = roots.values.filter { $0.type == "officeDocument" }
        guard mains.count == 1, let main = mains.first?.path else { throw DocumentError.corruptedPackage("expected one internal officeDocument relationship") }
        guard archive.entries[main] != nil else { throw DocumentError.missingPart(main) }
        mainPart = main
        let mime = overrides[main] ?? defs[(main as NSString).pathExtension.lowercased()]
        switch mime {
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml": format = .docx
        case "application/vnd.ms-word.document.macroEnabled.main+xml": format = .docm
        default: throw DocumentError.unknownFormat
        }
    }
    package func type(of path: String) -> String? { contentTypes[path] ?? defaults[(path as NSString).pathExtension.lowercased()] }
    package var parts: [PackagePart] {
        archive.paths.filter { !$0.hasSuffix("/") }.map { p in
            let entry = archive.entries[p]!
            return PackagePart(path: p, contentType: type(of: p), compressedSize: entry.compressedSize, expandedSize: entry.expandedSize)
        }
    }
    package func relationships(from source: String) throws -> [String: Relationship] {
        try Self.relationships(archive: archive, source: source, limits: limits, required: source.isEmpty)
    }
    package static func resolve(_ target: String, from source: String) throws -> String {
        guard !target.contains("\\"), !target.contains("\0"), !target.contains("?"), !target.contains(":") else { throw DocumentError.invalidRelationship(part: source, detail: "invalid internal URI") }
        let uri = String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        guard let decoded = uri.removingPercentEncoding, !decoded.contains("\\"), !decoded.contains("\0") else { throw DocumentError.invalidRelationship(part: source, detail: "invalid URI encoding") }
        var segments = target.hasPrefix("/") ? [] : source.split(separator: "/").dropLast().map(String.init)
        for segment in decoded.split(separator: "/") {
            if segment == "." { continue }
            if segment == ".." {
                guard !segments.isEmpty else { throw DocumentError.invalidRelationship(part: source, detail: "target escapes package") }; segments.removeLast()
            } else { segments.append(String(segment)) }
        }
        guard !segments.isEmpty else { throw DocumentError.invalidRelationship(part: source, detail: "empty part URI") }
        return segments.joined(separator: "/")
    }
    private static func relationships(archive: PackageArchive, source: String, limits: PackageLimits, required: Bool) throws -> [String: Relationship] {
        let part: String
        if source.isEmpty { part = "_rels/.rels" }
        else {
            let components = source.split(separator: "/").map(String.init)
            part = (components.dropLast() + ["_rels", components.last! + ".rels"]).joined(separator: "/")
        }
        guard archive.entries[part] != nil else { if required { throw DocumentError.missingPart(part) }; return [:] }
        let root = try XMLTree.parse(archive.read(part), part: part, limits: limits)
        guard root.name == "Relationships", root.namespace == XMLNamespace.packageRelationship else { throw DocumentError.invalidRelationship(part: part, detail: "invalid root") }
        var result: [String: Relationship] = [:]
        for child in root.children {
            guard child.name == "Relationship", child.namespace == XMLNamespace.packageRelationship,
                  let id = child.attr("Id"), !id.isEmpty, let uri = child.attr("Type"), let target = child.attr("Target"), !target.isEmpty,
                  result[id] == nil else { throw DocumentError.invalidRelationship(part: part, detail: "malformed or duplicate relationship") }
            let mode = child.attr("TargetMode")
            guard mode == nil || mode == "Internal" || mode == "External" else { throw DocumentError.invalidRelationship(part: part, detail: "invalid TargetMode") }
            let path = mode == "External" ? nil : try resolve(target, from: source)
            if let path, archive.entries[path] == nil { throw DocumentError.missingPart(path) }
            // Keep foreign relationship URIs distinct; their last path component has no Word meaning.
            let known = uri.hasPrefix(XMLNamespace.relationship + "/") || uri.hasPrefix(XMLNamespace.strictRelationship + "/") || uri.hasPrefix(XMLNamespace.packageRelationship + "/")
            result[id] = Relationship(id: id, type: known ? String(uri.split(separator: "/").last!) : uri, target: target, path: path)
        }
        return result
    }
}
extension DocumentFormat {
    public static func detect(_ data: Data, limits: PackageLimits = .init()) throws -> Self {
        if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
            throw DocumentError.unsupportedContainer("OLE: legacy DOC または暗号化された Office 文書")
        }
        guard data.starts(with: [0x50, 0x4B]) else { throw DocumentError.unknownFormat }
        let archive = try PackageArchive(data, limits: limits)
        if archive.entries["mimetype"] != nil, String(data: try archive.read("mimetype"), encoding: .utf8) == "application/vnd.oasis.opendocument.text" { return .odt }
        if archive.entries["Index/Document.iwa"] != nil {
            guard try IWorkProbe.isPages(archive.read("Index/Document.iwa")) else { throw DocumentError.unknownFormat }
            return .pages
        }
        guard archive.entries["[Content_Types].xml"] != nil else { throw DocumentError.unknownFormat }
        return try OPCPackage(data, limits: limits).format
    }
    public static func detect(contentsOf url: URL, limits: PackageLimits = .init()) throws -> Self {
        try detect(Data(contentsOf: url, options: .mappedIfSafe), limits: limits)
    }
}
