import Foundation
import DocumentCore

func metadata(in package: OPCPackage) throws -> DocumentMetadata {
    var m = DocumentMetadata()
    for r in try package.relationships(from: "").values.sorted(by: { $0.id < $1.id }) {
        guard let path = r.path, ["core-properties", "extended-properties", "custom-properties"].contains(r.type) else { continue }
        let root = try XMLTree.parse(package.archive.read(path), part: path, limits: package.limits)
        for n in root.children {
            switch n.name {
            case "title": m.title = n.text
            case "subject": m.subject = n.text
            case "creator": m.creator = n.text
            case "lastModifiedBy": m.lastModifiedBy = n.text
            case "description": m.description = n.text
            case "keywords": m.keywords = n.text
            case "created": m.created = n.text
            case "modified": m.modified = n.text
            case "Application": m.application = n.text
            case "Pages": m.declaredPages = integer(n.text)
            case "Words": m.declaredWords = integer(n.text)
            case "property": if let name = n.attr("name") { m.custom[name] = n.text }
            default: break
            }
        }
    }
    return m
}

func loadStyles(_ path: String?, package: OPCPackage, properties: Properties, warnings: WarningCollector) throws -> StyleResolver {
    let resolver = StyleResolver(warnings: warnings, part: path ?? package.mainPart)
    guard let path else { return resolver }
    let root = try XMLTree.parse(package.archive.read(path), part: path, limits: package.limits)
    guard root.isWord, root.name == "styles" else { throw DocumentError.invalidXML(part: path, detail: "expected styles root") }
    if let defaults = root.child("docDefaults") {
        resolver.defaults.paragraph = properties.paragraph(defaults.child("pPrDefault")?.child("pPr"), part: path)
        resolver.defaults.text = properties.text(defaults.child("rPrDefault")?.child("rPr"), part: path)
    }
    for n in root.wordChildren("style") {
        guard let id = n.attr("styleId"), resolver.styles[id] == nil else { throw DocumentError.corruptedPackage("missing / duplicate style ID") }
        let kind = n.attr("type") ?? "paragraph"
        let isDefault = n.attr("default").map { ["1", "true", "on"].contains($0) } ?? false
        resolver.styles[id] = DocumentStyle(id: id, name: n.child("name")?.value ?? id, kind: kind, basedOn: n.child("basedOn")?.value,
            isDefault: isDefault, paragraph: properties.paragraph(n.child("pPr"), part: path), text: properties.text(n.child("rPr"), part: path), list: properties.list(n.child("pPr")))
        if isDefault && kind == "paragraph" { resolver.defaultParagraphStyle = id }
        if isDefault && kind == "character" { resolver.defaultCharacterStyle = id }
        if kind == "table" || !n.wordChildren("tblStylePr").isEmpty {
            warnings.add(.uninterpretedFormatting, part: path, element: "tableStyle", message: "表の条件付きスタイルは解決していません。元パーツは asset(at:) で取得できます。")
        }
        for child in n.children where !["name", "basedOn", "pPr", "rPr", "next", "link", "uiPriority", "qFormat", "hidden", "semiHidden", "unhideWhenUsed", "rsid", "aliases", "autoRedefine", "locked", "personal", "personalCompose", "personalReply"].contains(child.name) && child.name != "tblStylePr" {
            properties.unparsed(child, part: path)
        }
    }
    // Validate every chain, including styles not used in the main story.
    for id in resolver.styles.keys.sorted() { _ = try resolver.chain(id) }
    return resolver
}

func loadNumbering(_ path: String?, package: OPCPackage, properties: Properties) throws -> [String: NumberingDefinition] {
    guard let path else { return [:] }
    let root = try XMLTree.parse(package.archive.read(path), part: path, limits: package.limits)
    guard root.isWord, root.name == "numbering" else { throw DocumentError.invalidXML(part: path, detail: "expected numbering root") }
    func level(_ n: MarkupNode) -> NumberingLevel {
        NumberingLevel(level: integer(n.attr("ilvl")) ?? 0, start: integer(n.child("start")?.value) ?? 1,
            format: n.child("numFmt")?.value ?? "decimal", text: n.child("lvlText")?.value ?? "%1.",
            paragraph: properties.paragraph(n.child("pPr"), part: path), formatting: properties.text(n.child("rPr"), part: path),
            restartAfterLevel: integer(n.child("lvlRestart")?.value))
    }
    var abstracts: [String: [Int: NumberingLevel]] = [:]
    for n in root.wordChildren("abstractNum") {
        guard let id = n.attr("abstractNumId"), abstracts[id] == nil else { throw DocumentError.corruptedPackage("duplicate abstract numbering ID") }
        var levels: [Int: NumberingLevel] = [:]
        for child in n.wordChildren("lvl") { let l = level(child); levels[l.level] = l }
        abstracts[id] = levels
        for child in n.children where ["numStyleLink", "styleLink"].contains(child.name) { properties.unparsed(child, part: path) }
    }
    var result: [String: NumberingDefinition] = [:]
    for n in root.wordChildren("num") {
        guard let id = n.attr("numId"), let abstract = n.child("abstractNumId")?.value, var levels = abstracts[abstract], result[id] == nil else { throw DocumentError.corruptedPackage("invalid numbering instance") }
        for override in n.wordChildren("lvlOverride") {
            let index = integer(override.attr("ilvl")) ?? 0
            if let l = override.child("lvl") { levels[index] = level(l) }
            if let start = integer(override.child("startOverride")?.value) { levels[index]?.start = start }
        }
        result[id] = NumberingDefinition(id: id, abstractID: abstract, levels: levels)
    }
    return result
}
