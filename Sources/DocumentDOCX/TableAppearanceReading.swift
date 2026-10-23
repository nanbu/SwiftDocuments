import Foundation
import DocumentCore

extension Properties {
    func tablePropertyHasText(_ node: MarkupNode) -> Bool {
        node.content.contains { if case .text(let value) = $0 { return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; return false }
    }
    func tableShading(_ node: MarkupNode?, part: String) -> String? {
        guard let node else { return nil }
        var fill = node.attr("fill"), interpreted = true
        if let value = fill, value != "auto" && (value.count != 6 || UInt32(value, radix: 16) == nil) { fill = nil; interpreted = false }
        if let theme = node.attr("themeFill") {
            if let resolved = themeColor(theme, tint: node.attr("themeFillTint"), shade: node.attr("themeFillShade")) { fill = resolved } else { interpreted = false }
        } else if node.attr("themeFillTint") != nil || node.attr("themeFillShade") != nil { interpreted = false }
        if let pattern = node.value, pattern != "clear" { interpreted = false }
        if !interpreted || hasExtraAttributes(node, allowed: ["fill", "val", "themeFill", "themeFillTint", "themeFillShade"]) || !node.children.isEmpty || tablePropertyHasText(node) { unparsed(node, part: part) }
        return fill
    }
    func tableBorders(_ node: MarkupNode?, part: String, cell: Bool = false) throws -> [TableBorderEdge: TableBorder] {
        guard let node else { return [:] }
        let edges: [String: TableBorderEdge] = ["top": .top, "bottom": .bottom, "left": .left, "right": .right, "start": .start, "end": .end, "insideH": .insideHorizontal, "insideV": .insideVertical, "tl2br": .diagonalDown, "tr2bl": .diagonalUp]
        let lines: Set<String> = ["nil", "none", "single", "thick", "double", "dotted", "dashed", "dotDash", "dotDotDash", "triple", "thinThickSmallGap", "thickThinSmallGap", "thinThickThinSmallGap", "thinThickMediumGap", "thickThinMediumGap", "thinThickThinMediumGap", "thinThickLargeGap", "thickThinLargeGap", "thinThickThinLargeGap", "wave", "doubleWave", "dashSmallGap", "dashDotStroked", "threeDEmboss", "threeDEngrave", "outset", "inset"]
        var result: [TableBorderEdge: TableBorder] = [:], seen = Set<TableBorderEdge>()
        if !node.attributes.isEmpty || tablePropertyHasText(node) { unparsed(node, part: part) }
        for child in node.children {
            guard child.isWord, let edge = edges[child.name], cell || ![.diagonalDown, .diagonalUp].contains(edge) else { unparsed(child, part: part); continue }
            guard seen.insert(edge).inserted else { throw DocumentError.invalidXML(part: part, detail: "duplicate table border edge") }
            guard let style = child.value else { unparsed(child, part: part); continue }
            var border = TableBorder(style: style), interpreted = lines.contains(style)
            border.sourceWidth = child.attr("sz")
            if let raw = border.sourceWidth {
                if lines.contains(style), let width = UInt64(raw) { border.width = Double(width) / 8 }
                else { interpreted = false }
            }
            if let raw = child.attr("space") {
                if let spacing = UInt64(raw) { border.spacing = Double(spacing) } else { interpreted = false }
            }
            if let color = child.attr("color") {
                if color == "auto" || (color.count == 6 && UInt32(color, radix: 16) != nil) { border.color = color }
                else { interpreted = false }
            }
            border.themeColor = child.attr("themeColor"); border.themeTint = child.attr("themeTint"); border.themeShade = child.attr("themeShade")
            if let ref = border.themeColor {
                if let resolved = themeColor(ref, tint: border.themeTint, shade: border.themeShade) { border.color = resolved }
                else { interpreted = false }
            } else if border.themeTint != nil || border.themeShade != nil { interpreted = false }
            for (name, assign) in [("shadow", { border.shadow = $0 }), ("frame", { border.frame = $0 })] {
                if let raw = child.attr(name) {
                    if let flag = MarkupNode.boolean(raw) { assign(flag) } else { interpreted = false }
                }
            }
            if !interpreted || hasExtraAttributes(child, allowed: ["val", "sz", "space", "color", "themeColor", "themeTint", "themeShade", "shadow", "frame"]) || !child.children.isEmpty || tablePropertyHasText(child) {
                border.rawProperties.append(child.xml); unparsed(child, part: part)
            }
            result[edge] = border
        }
        return result
    }
    func tableMargins(_ node: MarkupNode?, part: String) throws -> [TableCellEdge: TableWidth] {
        guard let node else { return [:] }
        var result: [TableCellEdge: TableWidth] = [:]
        if !node.attributes.isEmpty || tablePropertyHasText(node) { unparsed(node, part: part) }
        for child in node.children {
            guard child.isWord, let edge = TableCellEdge(rawValue: child.name) else { unparsed(child, part: part); continue }
            guard result[edge] == nil else { throw DocumentError.invalidXML(part: part, detail: "duplicate cell margin edge") }
            result[edge] = try tableWidth(child, part: part)
            if result[edge]?.value.map({ $0 < 0 }) == true { throw DocumentError.invalidXML(part: part, detail: "negative cell margin") }
            if tablePropertyHasText(child) { unparsed(child, part: part) }
            if let width = result[edge], ![.points, .none].contains(width.unit) { unparsed(child, part: part) }
        }
        return result
    }
    func tableIndentation(_ node: MarkupNode?, part: String) throws -> TableWidth? {
        guard let node else { return nil }
        if (node.attr("type") ?? "dxa") == "dxa" {
            guard let width = points(node.attr("w")) else { throw DocumentError.invalidXML(part: part, detail: "invalid table indentation") }
            if hasExtraAttributes(node, allowed: ["w", "type"]) || !node.children.isEmpty || tablePropertyHasText(node) { unparsed(node, part: part) }
            return TableWidth(value: width, unit: .points, sourceValue: node.attr("w"), sourceUnit: node.attr("type"))
        }
        // Retain declarations ignored by Word instead of inventing a physical offset.
        unparsed(node, part: part)
        return TableWidth(unit: .native, sourceValue: node.attr("w"), sourceUnit: node.attr("type"))
    }
    func tableFlag(_ node: MarkupNode?, part: String) -> Bool? {
        guard let node else { return nil }
        let flag = node.onOffValue
        if flag == nil || hasExtraAttributes(node, allowed: ["val"]) || !node.children.isEmpty || tablePropertyHasText(node) { unparsed(node, part: part) }
        return flag
    }
}
