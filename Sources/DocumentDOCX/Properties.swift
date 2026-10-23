import Foundation
import DocumentCore

/// Word lengths become points; percentages and automatic widths retain their original unit in the table API.
func wordLength(_ string: String?, unitsPerPoint: Double) -> Double? {
    guard let string else { return nil }
    if let number = Double(string), number.isFinite { return number / unitsPerPoint }
    let scale: Double
    switch string.suffix(2) {
    case "mm": scale = 72 / 25.4
    case "cm": scale = 72 / 2.54
    case "in": scale = 72
    case "pt": scale = 1
    case "pc", "pi": scale = 12
    default: return nil
    }
    guard let number = Double(string.dropLast(2)), number.isFinite, (number * scale).isFinite else { return nil }
    return number * scale
}
func points(_ string: String?) -> Double? { wordLength(string, unitsPerPoint: 20) }
func halfPoints(_ string: String?) -> Double? { wordLength(string, unitsPerPoint: 2) }
func integer(_ string: String?) -> Int? { string.flatMap(Int.init) }

final class Properties {
    var theme: DocumentTheme?
    var themeLanguages: [String: String] = [:]
    var themeColorMapping: [String: String] = [:]
    private static let textAttributes: [String: Set<String>] = [
            "b": ["val"], "i": ["val"], "strike": ["val"], "vanish": ["val"], "caps": ["val"], "smallCaps": ["val"],
            "u": ["val"], "rFonts": ["ascii", "hAnsi", "eastAsia", "cs", "asciiTheme", "hAnsiTheme", "eastAsiaTheme", "cstheme", "csTheme", "hint"], "sz": ["val"], "szCs": ["val"], "bCs": ["val"], "iCs": ["val"],
            "color": ["val", "themeColor", "themeTint", "themeShade"], "highlight": ["val"], "vertAlign": ["val"], "lang": ["val", "eastAsia", "bidi"], "rtl": ["val"], "rStyle": ["val"], "spacing": ["val"], "kern": ["val"], "em": ["val"], "w": ["val"], "position": ["val"]
        ]
    private static let paragraphAttributes: [String: Set<String>] = [
            "jc": ["val"], "spacing": ["before", "after", "line", "lineRule"], "ind": ["left", "right", "start", "end", "firstLine", "hanging"],
            "keepNext": ["val"], "keepLines": ["val"], "pageBreakBefore": ["val"], "bidi": ["val"], "outlineLvl": ["val"], "pStyle": ["val"], "widowControl": ["val"], "contextualSpacing": ["val"], "suppressAutoHyphens": ["val"], "wordWrap": ["val"], "kinsoku": ["val"], "autoSpaceDE": ["val"], "autoSpaceDN": ["val"], "textDirection": ["val"], "snapToGrid": ["val"]
        ]
    let warnings: WarningCollector
    init(_ warnings: WarningCollector) { self.warnings = warnings }
    func unparsed(_ node: MarkupNode, part: String) {
        warnings.add(.uninterpretedFormatting, part: part, element: node.name, message: "Uninterpreted formatting is retained in raw properties or the original part.")
    }
    func text(_ node: MarkupNode?, part: String, ignoringChildren: Set<String> = []) -> TextFormatting {
        var f = TextFormatting()
        guard let node else { return f }
        if !node.attributes.isEmpty { f.rawProperties.append(node.xml); unparsed(node, part: part) }
        let attrs = Self.textAttributes
        for n in node.children {
            if n.isWord && ignoringChildren.contains(n.name) { continue }
            var interpreted = n.isWord
            if n.isWord {
                switch n.name {
                case "b": f.bold = n.onOffValue
                case "i": f.italic = n.onOffValue
                case "bCs": f.boldComplexScript = n.onOffValue
                case "iCs": f.italicComplexScript = n.onOffValue
                case "strike": f.strike = n.onOffValue
                case "vanish": f.hidden = n.onOffValue
                case "caps": f.allCaps = n.onOffValue
                case "smallCaps": f.smallCaps = n.onOffValue
                case "u": f.underline = n.value ?? "single"
                case "rFonts":
                    f.fontName = n.attr("ascii") ?? n.attr("hAnsi")
                    f.fontNameEastAsia = n.attr("eastAsia"); f.fontTheme = n.attr("asciiTheme") ?? n.attr("hAnsiTheme")
                    f.fontNameComplexScript = n.attr("cs")
                    f.fontThemeEastAsia = n.attr("eastAsiaTheme"); f.fontThemeComplexScript = n.attr("cstheme") ?? n.attr("csTheme")
                    f.fontHint = n.attr("hint")
                    if let ascii = n.attr("ascii"), let hansi = n.attr("hAnsi"), ascii != hansi { interpreted = false }
                case "sz": f.fontSize = halfPoints(n.value); interpreted = f.fontSize != nil
                case "szCs": f.fontSizeComplexScript = halfPoints(n.value); interpreted = f.fontSizeComplexScript != nil
                case "spacing": f.characterSpacing = points(n.value); interpreted = f.characterSpacing != nil
                case "kern": f.kerning = halfPoints(n.value); interpreted = f.kerning != nil
                case "color":
                    f.color = n.value; f.themeColor = n.attr("themeColor")
                    f.themeTint = n.attr("themeTint"); f.themeShade = n.attr("themeShade")
                    if let reference = f.themeColor {
                        if let resolved = themeColor(reference, tint: f.themeTint, shade: f.themeShade) { f.color = resolved }
                        else { interpreted = false }
                    } else if f.themeTint != nil || f.themeShade != nil { interpreted = false }
                case "highlight": f.highlight = n.value
                case "vertAlign": f.verticalAlignment = n.value.flatMap(TextVerticalAlignment.init(rawValue:)); interpreted = f.verticalAlignment != nil
                case "lang": f.language = n.value; f.languageEastAsia = n.attr("eastAsia"); f.languageComplexScript = n.attr("bidi")
                case "rtl": f.rightToLeft = n.onOffValue
                case "em": f.emphasis = n.value
                case "w": f.textScale = n.value.flatMap(Double.init).flatMap { $0.isFinite ? $0 / 100 : nil }; interpreted = f.textScale != nil
                case "position": f.position = halfPoints(n.value); interpreted = f.position != nil
                case "rStyle": break
                case "rPrChange": continue
                default: interpreted = false
                }
            }
            if ["b", "i", "bCs", "iCs", "strike", "vanish", "caps", "smallCaps", "rtl"].contains(n.name), n.onOffValue == nil { interpreted = false }
            let allowed = attrs[n.name] ?? []
            let extra = hasExtraAttributes(n, allowed: allowed)
            if !interpreted || extra || !n.children.isEmpty { f.rawProperties.append(n.xml); unparsed(n, part: part) }
        }
        resolveFonts(&f, node: node, part: part)
        return f
    }
    func paragraph(_ node: MarkupNode?, part: String) -> ParagraphFormatting {
        var f = ParagraphFormatting()
        guard let node else { return f }
        if !node.attributes.isEmpty { f.rawProperties.append(node.xml); unparsed(node, part: part) }
        let attrs = Self.paragraphAttributes
        for n in node.children {
            var interpreted = n.isWord
            if n.isWord {
                switch n.name {
                case "jc": f.alignment = n.value.flatMap(ParagraphAlignment.init(rawValue:)); interpreted = f.alignment != nil
                case "spacing":
                    f.spacingBefore = points(n.attr("before")); f.spacingAfter = points(n.attr("after"))
                    if ["before", "after"].contains(where: { n.attr($0) != nil && points(n.attr($0)) == nil }) { interpreted = false }
                    if n.attr("lineRule") != nil || n.attr("line") != nil {
                        f.lineSpacingRule = LineSpacingRule(rawValue: n.attr("lineRule") ?? "auto")
                        if f.lineSpacingRule == nil { interpreted = false }
                    }
                    f.lineSpacing = f.lineSpacingRule == .multiple ? n.attr("line").flatMap(Double.init).flatMap { $0.isFinite ? $0 / 240 : nil } : points(n.attr("line"))
                    if n.attr("line") != nil && f.lineSpacing == nil { interpreted = false }
                case "ind":
                    f.indentLeft = points(n.attr("start") ?? n.attr("left")); f.indentRight = points(n.attr("end") ?? n.attr("right"))
                    f.firstLineIndent = points(n.attr("hanging")).map { -$0 } ?? points(n.attr("firstLine"))
                    if ["left", "right", "start", "end", "firstLine", "hanging"].contains(where: { n.attr($0) != nil && points(n.attr($0)) == nil }) { interpreted = false }
                case "keepNext": f.keepWithNext = n.onOffValue
                case "keepLines": f.keepTogether = n.onOffValue
                case "pageBreakBefore": f.pageBreakBefore = n.onOffValue
                case "bidi": f.rightToLeft = n.onOffValue
                case "outlineLvl": f.outlineLevel = integer(n.value).flatMap { (0...9).contains($0) ? $0 : nil }; interpreted = f.outlineLevel != nil
                case "widowControl": f.widowControl = n.onOffValue
                case "contextualSpacing": f.contextualSpacing = n.onOffValue
                case "suppressAutoHyphens": f.suppressAutoHyphens = n.onOffValue
                case "wordWrap": f.wordWrap = n.onOffValue
                case "kinsoku": f.kinsoku = n.onOffValue
                case "autoSpaceDE": f.autoSpaceEastAsianLatin = n.onOffValue
                case "autoSpaceDN": f.autoSpaceEastAsianNumbers = n.onOffValue
                case "textDirection": f.textDirection = n.value
                case "snapToGrid": f.snapToGrid = n.onOffValue
                case "tabs":
                    f.tabs = n.wordChildren("tab").compactMap { tab in
                        guard let position = points(tab.attr("pos")) else { return nil }
                        return TabStop(position: position, alignment: tab.attr("val") ?? "left", leader: tab.attr("leader"))
                    }
                    if n.children.contains(where: { !$0.isWord || $0.name != "tab" || points($0.attr("pos")) == nil || hasExtraAttributes($0, allowed: ["pos", "val", "leader"]) || !$0.children.isEmpty }) { interpreted = false }
                case "pStyle": interpreted = n.value != nil
                case "numPr":
                    // Numbering children are interpreted by list(); retain the container extensions here.
                    interpreted = !hasExtraAttributes(n, allowed: [])
                case "sectPr": continue // The section decoder checks its attributes and children.
                case "pPrChange", "rPr": continue
                default: interpreted = false
                }
            }
            if ["keepNext", "keepLines", "pageBreakBefore", "bidi", "widowControl", "contextualSpacing", "suppressAutoHyphens", "wordWrap", "kinsoku", "autoSpaceDE", "autoSpaceDN", "snapToGrid"].contains(n.name), n.onOffValue == nil { interpreted = false }
            let extra = hasExtraAttributes(n, allowed: attrs[n.name] ?? [])
            let leafHasChildren = attrs[n.name] != nil && !n.children.isEmpty
            if !interpreted || extra || leafHasChildren { f.rawProperties.append(n.xml); unparsed(n, part: part) }
        }
        return f
    }
    func hasExtraAttributes(_ node: MarkupNode, allowed: Set<String>, relationships: Set<String> = []) -> Bool {
        node.attributes.keys.contains { key in
            let fields = key.split(separator: "|", maxSplits: 1).map(String.init)
            if fields.count == 2 && [XMLNamespace.relationship, XMLNamespace.strictRelationship].contains(fields[0]) { return !relationships.contains(fields[1]) }
            return !allowed.contains(fields.last!) || (fields.count == 2 && ![XMLNamespace.word, XMLNamespace.strictWord].contains(fields[0]))
        }
    }
    func tableWidth(_ node: MarkupNode?, part: String) throws -> TableWidth? {
        guard let node else { return nil }
        let raw = node.attr("w"), sourceUnit = node.attr("type"), unit = sourceUnit ?? "dxa"
        if hasExtraAttributes(node, allowed: ["w", "type"]) || !node.children.isEmpty { unparsed(node, part: part) }
        func finite(_ value: String) throws -> Double {
            guard let parsed = Double(value), parsed.isFinite else { throw DocumentError.invalidXML(part: part, detail: "invalid table width") }
            return parsed
        }
        if let raw, raw.hasSuffix("%") {
            return try TableWidth(value: finite(String(raw.dropLast())), unit: .percent, sourceValue: raw, sourceUnit: sourceUnit)
        }
        switch unit {
        case "auto": return TableWidth(unit: .automatic, sourceValue: raw, sourceUnit: sourceUnit)
        case "nil": return TableWidth(unit: .none, sourceValue: raw, sourceUnit: sourceUnit)
        case "pct": return try TableWidth(value: raw.map { try finite($0) / 50 }, unit: .percent, sourceValue: raw, sourceUnit: sourceUnit)
        case "dxa":
            let value = points(raw)
            if raw != nil && value == nil { throw DocumentError.invalidXML(part: part, detail: "invalid physical table width") }
            return TableWidth(value: value, unit: .points, sourceValue: raw, sourceUnit: sourceUnit)
        default:
            unparsed(node, part: part)
            return TableWidth(unit: .native, sourceValue: raw, sourceUnit: sourceUnit)
        }
    }
    func list(_ node: MarkupNode?, part: String, inheriting base: ListReference? = nil) throws -> ListReference? {
        guard let n = node?.child("numPr") else { return base }
        for child in n.children {
            if !child.isWord || !["numId", "ilvl"].contains(child.name) || hasExtraAttributes(child, allowed: ["val"]) || !child.children.isEmpty {
                unparsed(child, part: part)
            }
        }
        guard n.wordChildren("numId").count <= 1, n.wordChildren("ilvl").count <= 1 else {
            throw DocumentError.invalidXML(part: part, detail: "duplicate numbering reference property")
        }
        let level: Int
        if let child = n.child("ilvl") {
            guard let parsed = child.value.flatMap(Int.init), (0...8).contains(parsed) else {
                throw DocumentError.invalidXML(part: part, detail: "invalid explicit numbering reference level")
            }
            level = parsed
        } else { level = base?.level ?? 0 }
        guard let id = n.child("numId")?.value ?? base?.id else { return nil }
        return ListReference(id: id, level: level)
    }
}

struct ResolvedStyle {
    var paragraph = ParagraphFormatting()
    var text = TextFormatting()
    var list: ListReference?
}
final class StyleResolver {
    var properties: Properties?
    var styles: [String: DocumentStyle] = [:]
    var defaults = ResolvedStyle()
    var defaultParagraphStyle: String?
    var defaultCharacterStyle: String?
    var defaultTableStyle: String?
    private var cache: [String: [DocumentStyle]] = [:]
    private let part: String
    init(part: String) { self.part = part }
    func chain(_ id: String) throws -> [DocumentStyle] {
        if let cached = cache[id] { return cached }
        var result: [DocumentStyle] = [], seen: Set<String> = [], cursor: String? = id
        while let key = cursor {
            try Task.checkCancellation()
            guard seen.count < 128 else { throw DocumentError.limitExceeded("style inheritance depth in \(part)") }
            guard seen.insert(key).inserted else { throw DocumentError.corruptedPackage("style inheritance cycle in \(part)") }
            // References are diagnosed at their declaration/use site, not once per cached traversal.
            guard let style = styles[key] else { break }
            result.append(style); cursor = style.basedOn
        }
        result.reverse(); cache[id] = result; return result
    }
    func paragraph(_ id: String?, table: ResolvedStyle? = nil) throws -> ResolvedStyle {
        var result = defaults
        if let table { result.paragraph.merge(table.paragraph); result.text.merge(table.text) }
        if let key = id ?? defaultParagraphStyle {
            for style in try chain(key) {
                result.paragraph.merge(style.paragraph); result.text.merge(style.text, toggling: true)
                result.list = style.list ?? result.list
            }
        }
        return result
    }
    func text(_ id: String?, base: TextFormatting, direct: TextFormatting) throws -> TextFormatting {
        var result = base
        if let key = id ?? defaultCharacterStyle { for style in try chain(key) { result.merge(style.text, toggling: true) } }
        result.merge(direct)
        properties?.resolveFonts(&result, node: nil, part: part)
        return result
    }
}
