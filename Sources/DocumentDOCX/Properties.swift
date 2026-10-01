import Foundation
import DocumentCore

/// Word lengths become points; percentages and automatic widths retain their original unit in the table API.
func points(_ string: String?) -> Double? { string.flatMap(Double.init).map { $0 / 20 } }
func integer(_ string: String?) -> Int? { string.flatMap(Int.init) }

final class Properties {
    let warnings: WarningCollector
    init(_ warnings: WarningCollector) { self.warnings = warnings }
    func unparsed(_ node: MarkupNode, part: String) {
        warnings.add(.uninterpretedFormatting, part: part, element: node.name, message: "書式の一部は未解釈です。rawProperties または元パーツに保持しました。")
    }
    func text(_ node: MarkupNode?, part: String) -> TextFormatting {
        var f = TextFormatting()
        guard let node else { return f }
        let attrs: [String: Set<String>] = [
            "b": ["val"], "i": ["val"], "strike": ["val"], "vanish": ["val"], "caps": ["val"], "smallCaps": ["val"],
            "u": ["val"], "rFonts": ["ascii", "hAnsi", "eastAsia", "cs", "asciiTheme", "hAnsiTheme"], "sz": ["val"], "szCs": ["val"], "bCs": ["val"], "iCs": ["val"],
            "color": ["val", "themeColor"], "highlight": ["val"], "vertAlign": ["val"], "lang": ["val", "eastAsia", "bidi"], "rtl": ["val"], "rStyle": ["val"], "spacing": ["val"], "kern": ["val"]
        ]
        for n in node.children {
            var interpreted = n.isWord
            if n.isWord {
                switch n.name {
                case "b": f.bold = n.on
                case "i": f.italic = n.on
                case "bCs": f.boldComplexScript = n.on
                case "iCs": f.italicComplexScript = n.on
                case "strike": f.strike = n.on
                case "vanish": f.hidden = n.on
                case "caps": f.allCaps = n.on
                case "smallCaps": f.smallCaps = n.on
                case "u": f.underline = n.value ?? "single"
                case "rFonts":
                    f.fontName = n.attr("ascii") ?? n.attr("hAnsi")
                    f.fontNameEastAsia = n.attr("eastAsia"); f.fontTheme = n.attr("asciiTheme") ?? n.attr("hAnsiTheme")
                    f.fontNameComplexScript = n.attr("cs")
                    if let ascii = n.attr("ascii"), let hansi = n.attr("hAnsi"), ascii != hansi { interpreted = false }
                case "sz": f.fontSize = n.value.flatMap(Double.init).map { $0 / 2 }
                case "szCs": f.fontSizeComplexScript = n.value.flatMap(Double.init).map { $0 / 2 }
                case "spacing": f.characterSpacing = points(n.value)
                case "kern": f.kerning = n.value.flatMap(Double.init).map { $0 / 2 }
                case "color": f.color = n.value; f.themeColor = n.attr("themeColor")
                case "highlight": f.highlight = n.value
                case "vertAlign": f.verticalAlignment = n.value.flatMap(TextVerticalAlignment.init(rawValue:)); interpreted = f.verticalAlignment != nil
                case "lang": f.language = n.value; f.languageEastAsia = n.attr("eastAsia"); f.languageComplexScript = n.attr("bidi")
                case "rtl": f.rightToLeft = n.on
                case "rStyle": break
                default: interpreted = false
                }
            }
            let allowed = attrs[n.name] ?? []
            let extra = n.attributes.keys.contains { key in !allowed.contains(String(key.split(separator: "|").last!)) }
            if !interpreted || extra { f.rawProperties.append(n.xml); unparsed(n, part: part) }
        }
        return f
    }
    func paragraph(_ node: MarkupNode?, part: String) -> ParagraphFormatting {
        var f = ParagraphFormatting()
        guard let node else { return f }
        let attrs: [String: Set<String>] = [
            "jc": ["val"], "spacing": ["before", "after", "line", "lineRule"], "ind": ["left", "right", "start", "end", "firstLine", "hanging"],
            "keepNext": ["val"], "keepLines": ["val"], "pageBreakBefore": ["val"], "bidi": ["val"], "outlineLvl": ["val"], "pStyle": ["val"], "widowControl": ["val"], "contextualSpacing": ["val"], "suppressAutoHyphens": ["val"]
        ]
        for n in node.children {
            var interpreted = n.isWord
            if n.isWord {
                switch n.name {
                case "jc": f.alignment = n.value.flatMap(ParagraphAlignment.init(rawValue:)); interpreted = f.alignment != nil
                case "spacing":
                    f.spacingBefore = points(n.attr("before")); f.spacingAfter = points(n.attr("after"))
                    if n.attr("lineRule") != nil || n.attr("line") != nil {
                        f.lineSpacingRule = LineSpacingRule(rawValue: n.attr("lineRule") ?? "auto")
                        if f.lineSpacingRule == nil { interpreted = false }
                    }
                    f.lineSpacing = n.attr("line").flatMap(Double.init).map { $0 / (f.lineSpacingRule == .multiple ? 240 : 20) }
                case "ind":
                    f.indentLeft = points(n.attr("start") ?? n.attr("left")); f.indentRight = points(n.attr("end") ?? n.attr("right"))
                    f.firstLineIndent = points(n.attr("hanging")).map { -$0 } ?? points(n.attr("firstLine"))
                case "keepNext": f.keepWithNext = n.on
                case "keepLines": f.keepTogether = n.on
                case "pageBreakBefore": f.pageBreakBefore = n.on
                case "bidi": f.rightToLeft = n.on
                case "outlineLvl": f.outlineLevel = integer(n.value)
                case "widowControl": f.widowControl = n.on
                case "contextualSpacing": f.contextualSpacing = n.on
                case "suppressAutoHyphens": f.suppressAutoHyphens = n.on
                case "pStyle", "numPr", "sectPr": break
                default: interpreted = false
                }
            }
            let extra = attrs[n.name].map { allowed in n.attributes.keys.contains { !allowed.contains(String($0.split(separator: "|").last!)) } } ?? false
            if !interpreted || extra { f.rawProperties.append(n.xml); unparsed(n, part: part) }
        }
        return f
    }
    func list(_ node: MarkupNode?, inheriting base: ListReference? = nil) -> ListReference? {
        guard let n = node?.child("numPr") else { return base }
        guard let id = n.child("numId")?.value ?? base?.id else { return nil }
        return ListReference(id: id, level: integer(n.child("ilvl")?.value) ?? base?.level ?? 0)
    }
}

struct ResolvedStyle {
    var paragraph = ParagraphFormatting()
    var text = TextFormatting()
    var list: ListReference?
}
final class StyleResolver {
    var styles: [String: DocumentStyle] = [:]
    var defaults = ResolvedStyle()
    var defaultParagraphStyle: String?
    var defaultCharacterStyle: String?
    private var cache: [String: [DocumentStyle]] = [:]
    private let warnings: WarningCollector
    private let part: String
    init(warnings: WarningCollector, part: String) { self.warnings = warnings; self.part = part }
    func chain(_ id: String) throws -> [DocumentStyle] {
        if let cached = cache[id] { return cached }
        var result: [DocumentStyle] = [], seen: Set<String> = [], cursor: String? = id
        while let key = cursor {
            guard seen.count < 128 else { throw DocumentError.limitExceeded("style inheritance depth in \(part)") }
            guard seen.insert(key).inserted else { throw DocumentError.corruptedPackage("style inheritance cycle in \(part)") }
            guard let style = styles[key] else {
                warnings.add(.invalidReference, part: part, element: "style", message: "参照先のスタイルがありません。")
                break
            }
            result.append(style); cursor = style.basedOn
        }
        result.reverse(); cache[id] = result; return result
    }
    func paragraph(_ id: String?) throws -> ResolvedStyle {
        var result = defaults
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
        result.merge(direct); return result
    }
}
