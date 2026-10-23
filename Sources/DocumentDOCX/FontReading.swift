import Foundation
import DocumentCore

func loadFontTable(_ path: String?, package: OPCPackage, warnings: WarningCollector) throws -> [DocumentFont] {
    guard let path else { return [] }
    let root = try XMLTree.parse(package.archive.read(path), part: path, limits: package.limits)
    guard root.isWord, root.name == "fonts" else { throw DocumentError.invalidXML(part: path, detail: "expected font table") }
    let relationships = try package.relationships(from: path)
    let properties = Properties(warnings)
    var result: [DocumentFont] = []
    for n in root.wordChildren("font") {
        try Task.checkCancellation()
        guard let name = n.attr("name"), !name.isEmpty else { throw DocumentError.corruptedPackage("missing font name") }
        var font = DocumentFont(name: name)
        font.alternateName = n.child("altName")?.value; font.family = n.child("family")?.value
        font.charset = n.child("charset")?.value; font.pitch = n.child("pitch")?.value; font.panose = n.child("panose1")?.value
        let faces = ["embedRegular": "regular", "embedBold": "bold", "embedItalic": "italic", "embedBoldItalic": "boldItalic"]
        if properties.hasExtraAttributes(n, allowed: ["name"]) { properties.unparsed(n, part: path) }
        var seen = Set<String>()
        for child in n.children {
            guard child.isWord else { properties.unparsed(child, part: path); continue }
            guard seen.insert(child.name).inserted else { throw DocumentError.invalidXML(part: path, detail: "duplicate font property") }
            if let face = faces[child.name] {
                guard let id = child.rel("id") else { throw DocumentError.invalidRelationship(part: path, detail: "missing embedded font relationship") }
                guard let relationship = relationships[id], relationship.type == "font", let asset = relationship.path else { throw DocumentError.invalidRelationship(part: path, detail: "invalid embedded font relationship") }
                font.embeddedFaces.append(EmbeddedFont(assetPath: asset, key: child.attr("fontKey"), face: face, isSubset: ["1", "true"].contains(child.attr("subsetted") ?? "0")))
                let allowed = [XMLNamespace.relationship + "|id", XMLNamespace.strictRelationship + "|id", XMLNamespace.word + "|fontKey", XMLNamespace.strictWord + "|fontKey", XMLNamespace.word + "|subsetted", XMLNamespace.strictWord + "|subsetted"]
                if child.attributes.keys.contains(where: { !allowed.contains($0) }) || !child.children.isEmpty { properties.unparsed(child, part: path) }
            } else if !["altName", "family", "charset", "pitch", "panose1"].contains(child.name) || properties.hasExtraAttributes(child, allowed: ["val"]) || !child.children.isEmpty {
                properties.unparsed(child, part: path)
            }
        }
        result.append(font)
    }
    for child in root.children where !child.isWord || child.name != "font" { properties.unparsed(child, part: path) }
    return result
}

func loadTheme(_ path: String?, package: OPCPackage, warnings: WarningCollector) throws -> DocumentTheme? {
    guard let path else { return nil }
    let root = try XMLTree.parse(package.archive.read(path), part: path, limits: package.limits)
    guard root.name == "theme", root.drawingVocabulary else { throw DocumentError.invalidXML(part: path, detail: "expected drawing theme") }
    var theme = DocumentTheme()
    let elements = root.drawingChild("themeElements")
    for slot in elements?.drawingChild("clrScheme")?.children ?? [] {
        if slot.drawingVocabulary, let color = slot.children.first, color.drawingVocabulary,
           ["srgbClr", "sysClr"].contains(color.name),
           let hex = color.attr(color.name == "sysClr" ? "lastClr" : "val"), hex.count == 6, UInt32(hex, radix: 16) != nil, color.children.isEmpty {
            theme.colors[slot.name] = hex.uppercased()
        } else { warnings.add(.uninterpretedFormatting, part: path, element: slot.name, message: "Unsupported theme color source retained in the original part.") }
    }
    func fonts(_ name: String) -> [String: String] {
        var result: [String: String] = [:]
        for font in elements?.drawingChild("fontScheme")?.drawingChild(name)?.children ?? [] {
            if font.drawingVocabulary, let typeface = font.attr("typeface"), !typeface.isEmpty { result[font.attr("script") ?? font.name] = typeface }
        }
        return result
    }
    theme.majorFonts = fonts("majorFont"); theme.minorFonts = fonts("minorFont")
    return theme
}
