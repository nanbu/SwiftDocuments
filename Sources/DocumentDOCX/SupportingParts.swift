import Foundation
import DocumentCore

func metadata(in package: OPCPackage, warnings: WarningCollector? = nil) throws -> DocumentMetadata {
    var result = DocumentMetadata()
    let core = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
    let dc = "http://purl.org/dc/elements/1.1/", terms = "http://purl.org/dc/terms/"
    let extended: Set<String> = ["http://schemas.openxmlformats.org/officeDocument/2006/extended-properties", "http://purl.oclc.org/ooxml/officeDocument/extendedProperties"]
    let custom: Set<String> = ["http://schemas.openxmlformats.org/officeDocument/2006/custom-properties", "http://purl.oclc.org/ooxml/officeDocument/customProperties"]
    let types: Set<String> = ["http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes", "http://purl.oclc.org/ooxml/officeDocument/docPropsVTypes"]
    for reference in try package.relationships(from: "").values.sorted(by: { $0.id < $1.id }) {
        try Task.checkCancellation()
        guard let path = reference.path, ["core-properties", "extended-properties", "custom-properties"].contains(reference.type) else { continue }
        let root = try XMLTree.parse(package.archive.read(path), part: path, limits: package.limits)
        let valid = reference.type == "core-properties" ? root.name == "coreProperties" && root.namespace == core :
            root.name == "Properties" && (reference.type == "extended-properties" ? extended : custom).contains(root.namespace)
        guard valid else { throw DocumentError.invalidXML(part: path, detail: "metadata root does not match relationship type") }
        var propertyNames = Set<String>()
        for node in root.children {
            var interpreted = false
            if reference.type == "core-properties" {
                switch (node.namespace, node.name) {
                case (dc, "title"): result.title = node.text; interpreted = true
                case (dc, "subject"): result.subject = node.text; interpreted = true
                case (dc, "creator"): result.creator = node.text; interpreted = true
                case (dc, "description"): result.description = node.text; interpreted = true
                case (core, "lastModifiedBy"): result.lastModifiedBy = node.text; interpreted = true
                case (core, "keywords"): result.keywords = node.text; interpreted = true
                case (terms, "created"): result.created = node.text; interpreted = true
                case (terms, "modified"): result.modified = node.text; interpreted = true
                default: break
                }
            } else if reference.type == "extended-properties", node.namespace == root.namespace {
                switch node.name {
                case "Application": result.application = node.text; interpreted = true
                case "Pages": result.declaredPages = integer(node.text); interpreted = result.declaredPages != nil
                case "Words": result.declaredWords = integer(node.text); interpreted = result.declaredWords != nil
                default: break
                }
            } else if reference.type == "custom-properties", node.namespace == root.namespace, node.name == "property" {
                guard let name = node.attr("name"), !name.isEmpty, propertyNames.insert(name).inserted else {
                    throw DocumentError.invalidXML(part: path, detail: "missing / duplicate custom property name")
                }
                result.custom[name] = node.text
                interpreted = node.children.count == 1 && node.children.allSatisfy { types.contains($0.namespace) && $0.children.isEmpty }
            }
            if !interpreted || !node.children.isEmpty && reference.type != "custom-properties" {
                warnings?.add(.unsupportedContent, part: path, element: "{\(node.namespace)}\(node.name)", message: "Uninterpreted metadata structure retained in the original part.")
            }
        }
    }
    return result
}

func loadStyles(_ path: String?, package: OPCPackage, properties: Properties, warnings: WarningCollector) throws -> StyleResolver {
    let resolver = StyleResolver(part: path ?? package.mainPart)
    resolver.properties = properties
    guard let path else { return resolver }
    let root = try XMLTree.parse(package.archive.read(path), part: path, limits: package.limits)
    guard root.isWord, root.name == "styles" else { throw DocumentError.invalidXML(part: path, detail: "expected styles root") }
    if let defaults = root.child("docDefaults") {
        resolver.defaults.paragraph = properties.paragraph(defaults.child("pPrDefault")?.child("pPr"), part: path)
        resolver.defaults.text = properties.text(defaults.child("rPrDefault")?.child("rPr"), part: path)
    }
    for n in root.wordChildren("style") {
        try Task.checkCancellation()
        guard let id = n.attr("styleId"), resolver.styles[id] == nil else { throw DocumentError.corruptedPackage("missing / duplicate style ID") }
        let kind = n.attr("type") ?? "paragraph"
        let isDefault = n.attr("default").map { ["1", "true", "on"].contains($0) } ?? false
        resolver.styles[id] = DocumentStyle(id: id, name: n.child("name")?.value ?? id, kind: kind, basedOn: n.child("basedOn")?.value,
            isDefault: isDefault, paragraph: properties.paragraph(n.child("pPr"), part: path), text: properties.text(n.child("rPr"), part: path), list: try properties.list(n.child("pPr"), part: path))
        if isDefault && kind == "paragraph" { resolver.defaultParagraphStyle = id }
        if isDefault && kind == "character" { resolver.defaultCharacterStyle = id }
        if kind == "table" {
            if isDefault { resolver.defaultTableStyle = id }
            var style = resolver.styles[id]!
            style.tableRules = try tableStyleRules(n, properties: properties, part: path)
            style.rowBandSize = try tableBandSize(n.child("tblPr")?.child("tblStyleRowBandSize"), part: path)
            style.columnBandSize = try tableBandSize(n.child("tblPr")?.child("tblStyleColBandSize"), part: path)
            resolver.styles[id] = style
        }
        for child in n.children where !child.isWord || (!["name", "basedOn", "pPr", "rPr", "next", "link", "uiPriority", "qFormat", "hidden", "semiHidden", "unhideWhenUsed", "rsid", "aliases", "autoRedefine", "locked", "personal", "personalCompose", "personalReply", "tblPr", "trPr", "tcPr"].contains(child.name) && child.name != "tblStylePr") {
            properties.unparsed(child, part: path)
        }
    }
    // Validate every chain, including styles not used in the main story.
    for id in resolver.styles.keys.sorted() {
        try Task.checkCancellation()
        if let base = resolver.styles[id]?.basedOn, resolver.styles[base] == nil {
            warnings.add(.invalidReference, part: path, element: "basedOn", message: "The base style is missing; the source ID and available formatting are retained.")
        }
        _ = try resolver.chain(id)
    }
    return resolver
}

func loadNumbering(_ path: String?, package: OPCPackage, properties: Properties) throws -> [String: NumberingDefinition] {
    guard let path else { return [:] }
    let root = try XMLTree.parse(package.archive.read(path), part: path, limits: package.limits)
    guard root.isWord, root.name == "numbering" else { throw DocumentError.invalidXML(part: path, detail: "expected numbering root") }
    let relationships = try package.relationships(from: path)
    var pictures: [String: DocumentImage] = [:], pictureIDs = Set<String>()
    for node in root.wordChildren("numPicBullet") {
        guard let pictureID = node.attr("numPicBulletId"), !pictureID.isEmpty, pictureIDs.insert(pictureID).inserted else {
            throw DocumentError.corruptedPackage("missing / duplicate picture bullet ID")
        }
        let images = node.descendants("imagedata", namespaceSuffix: "vml")
        guard let image = images.first else { properties.unparsed(node, part: path); continue }
        guard let id = image.rel("id"), let target = relationships[id], target.type == "image" else {
            throw DocumentError.invalidRelationship(part: path, detail: "missing / wrong-type picture bullet image")
        }
        var picture = DocumentImage(assetPath: target.path, externalURL: target.isExternal ? target.target : nil,
                                    alternativeText: image.attr("title"), rawXML: node.xml)
        picture.contentType = target.path.flatMap { package.type(of: $0) }
        pictures[pictureID] = picture
        // VML sizing, cropping and additional shapes remain visible to the downstream renderer.
        properties.unparsed(node, part: path)
    }
    func index(_ value: String?) throws -> Int {
        guard let value, let result = Int(value), (0...8).contains(result) else {
            throw DocumentError.corruptedPackage("invalid numbering level")
        }
        return result
    }
    func level(_ n: MarkupNode) throws -> NumberingLevel {
        let levelIndex = try index(n.attr("ilvl"))
        if let value = n.child("start")?.value, Int(value) == nil {
            throw DocumentError.corruptedPackage("invalid numbering start")
        }
        if let value = n.child("lvlRestart")?.value, Int(value).map({ (0...9).contains($0) }) != true {
            throw DocumentError.corruptedPackage("invalid numbering restart")
        }
        var result = NumberingLevel(level: levelIndex, start: integer(n.child("start")?.value) ?? 1,
            format: n.child("numFmt")?.value ?? "decimal", text: n.child("lvlText")?.value ?? "%1.",
            paragraph: properties.paragraph(n.child("pPr"), part: path), formatting: properties.text(n.child("rPr"), part: path),
            restartAfterLevel: integer(n.child("lvlRestart")?.value))
        result.suffix = n.child("suff")?.value ?? "tab"
        result.isLegal = n.child("isLgl")?.on ?? false
        if let legal = n.child("isLgl"), legal.onOffValue == nil { properties.unparsed(legal, part: path) }
        if let reference = n.child("lvlPicBulletId")?.value {
            result.picture = pictures[reference]
            if result.picture == nil {
                properties.warnings.add(.invalidReference, part: path, element: "lvlPicBulletId", message: "Picture bullet declaration is missing or uninterpreted; source reference retained.")
            }
        }
        let simple: Set<String> = ["start", "numFmt", "lvlText", "lvlRestart", "suff", "isLgl", "lvlPicBulletId"]
        var seen = Set<String>()
        for child in n.children {
            if child.isWord, simple.contains(child.name) || ["pPr", "rPr"].contains(child.name) {
                guard seen.insert(child.name).inserted else { throw DocumentError.corruptedPackage("duplicate numbering level property") }
                if simple.contains(child.name), properties.hasExtraAttributes(child, allowed: ["val"]) || !child.children.isEmpty {
                    properties.unparsed(child, part: path)
                }
            } else { properties.unparsed(child, part: path) }
        }
        result.rawProperties = n.children.map(\.xml)
        return result
    }
    var abstracts: [String: [Int: NumberingLevel]] = [:]
    for n in root.wordChildren("abstractNum") {
        try Task.checkCancellation()
        guard let id = n.attr("abstractNumId"), !id.isEmpty, abstracts[id] == nil else { throw DocumentError.corruptedPackage("duplicate abstract numbering ID") }
        var levels: [Int: NumberingLevel] = [:]
        for child in n.wordChildren("lvl") {
            let value = try level(child)
            guard levels[value.level] == nil else { throw DocumentError.corruptedPackage("duplicate numbering level") }
            levels[value.level] = value
        }
        abstracts[id] = levels
        for child in n.children where !(child.isWord && child.name == "lvl") { properties.unparsed(child, part: path) }
    }
    var result: [String: NumberingDefinition] = [:]
    for n in root.wordChildren("num") {
        try Task.checkCancellation()
        guard let id = n.attr("numId"), !id.isEmpty, let abstract = n.child("abstractNumId")?.value, var levels = abstracts[abstract], result[id] == nil else { throw DocumentError.corruptedPackage("invalid numbering instance") }
        var overrides = Set<Int>()
        for override in n.wordChildren("lvlOverride") {
            let levelIndex = try index(override.attr("ilvl"))
            guard overrides.insert(levelIndex).inserted else { throw DocumentError.corruptedPackage("duplicate numbering override") }
            let sources = override.wordChildren("lvl"), starts = override.wordChildren("startOverride")
            guard sources.count <= 1, starts.count <= 1 else { throw DocumentError.corruptedPackage("duplicate numbering override property") }
            if let source = sources.first {
                let value = try level(source)
                guard value.level == levelIndex else { throw DocumentError.corruptedPackage("conflicting numbering override level") }
                levels[levelIndex] = value
            }
            if let source = starts.first {
                guard let start = source.value.flatMap(Int.init), levels[levelIndex] != nil else { throw DocumentError.corruptedPackage("invalid numbering start override") }
                levels[levelIndex]?.start = start
            }
            for child in override.children where !(child.isWord && ["lvl", "startOverride"].contains(child.name)) { properties.unparsed(child, part: path) }
        }
        for child in n.children where !(child.isWord && ["abstractNumId", "lvlOverride"].contains(child.name)) { properties.unparsed(child, part: path) }
        result[id] = NumberingDefinition(id: id, abstractID: abstract, levels: levels)
    }
    for child in root.children where !(child.isWord && ["numPicBullet", "abstractNum", "num"].contains(child.name)) { properties.unparsed(child, part: path) }
    return result
}
