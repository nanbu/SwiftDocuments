import Foundation
import DocumentCore

private let regions: [String: TableStyleRegion] = ["wholeTable": .wholeTable, "band1Horz": .oddRowBand, "band2Horz": .evenRowBand, "band1Vert": .oddColumnBand, "band2Vert": .evenColumnBand, "firstCol": .firstColumn, "lastCol": .lastColumn, "firstRow": .firstRow, "lastRow": .lastRow, "nwCell": .topLeft, "neCell": .topRight, "swCell": .bottomLeft, "seCell": .bottomRight]
func tableBandSize(_ node: MarkupNode?, part: String) throws -> Int? {
    guard let node else { return nil }
    guard let size = node.value.flatMap(Int.init), size > 0 else { throw DocumentError.invalidXML(part: part, detail: "invalid table band size") }
    return size
}
func tableStyleRules(_ node: MarkupNode, properties: Properties, part: String) throws -> [TableStyleRule] {
    func rule(_ n: MarkupNode, _ region: TableStyleRegion) throws -> TableStyleRule {
        var result = TableStyleRule(region: region)
        result.paragraph = properties.paragraph(n.child("pPr"), part: part)
        result.text = properties.text(n.child("rPr"), part: part)
        result.cell = try properties.cellFormatting(n.child("tcPr"), part: part)
        result.row = try properties.rowFormatting(n.child("trPr"), part: part)
        if let row = n.child("trPr"), !row.children.isEmpty { properties.unparsed(row, part: part) }
        result.table = try properties.tableFormatting(n.child("tblPr"), part: part)
        result.source = try SourceXMLNode(n)
        return result
    }
    // Base paragraph/run properties were already parsed by loadStyles.
    var whole = TableStyleRule(region: .wholeTable)
    whole.cell = try properties.cellFormatting(node.child("tcPr"), part: part)
    whole.row = try properties.rowFormatting(node.child("trPr"), part: part)
    if let row = node.child("trPr"), !row.children.isEmpty { properties.unparsed(row, part: part) }
    whole.table = try properties.tableFormatting(node.child("tblPr"), part: part)
    whole.source = try SourceXMLNode(node)
    var result = [whole], seen = Set<String>()
    for n in node.wordChildren("tblStylePr") {
        guard let key = n.attr("type"), let region = regions[key] else { properties.unparsed(n, part: part); continue }
        guard seen.insert(key).inserted else { throw DocumentError.invalidXML(part: part, detail: "duplicate table style region") }
        if properties.hasExtraAttributes(n, allowed: ["type"]) { properties.unparsed(n, part: part) }
        for child in n.children where !child.isWord || !["pPr", "rPr", "tcPr", "trPr", "tblPr"].contains(child.name) { properties.unparsed(child, part: part) }
        result.append(try rule(n, region))
    }
    return result
}
struct TableStyleContext {
    var rules: [TableStyleRule] = []
    var base = ResolvedStyle()
    var flags: [String: Bool] = [:]
    var rowBand = 1, columnBand = 1, rowCount = 0, columnCount = 0
    var formatting = TableFormatting()
    init(node: MarkupNode, tableProperties: MarkupNode?, columnCount: Int, styleID: String?, styles: StyleResolver, properties: Properties, part: String, options: ReadOptions) throws {
        let key = styleID ?? styles.defaultTableStyle
        if let key {
            if styles.styles[key] == nil { properties.warnings.add(.invalidReference, part: part, element: "tblStyle", message: "The table style is missing; source ID retained.") }
            for style in try styles.chain(key) {
                base.paragraph.merge(style.paragraph); base.text.merge(style.text, toggling: true)
                rules += style.tableRules
                rowBand = style.rowBandSize ?? rowBand; columnBand = style.columnBandSize ?? columnBand
            }
        }
        let props = tableProperties
        rowBand = try tableBandSize(props?.child("tblStyleRowBandSize"), part: part) ?? rowBand
        columnBand = try tableBandSize(props?.child("tblStyleColBandSize"), part: part) ?? columnBand
        let look = props?.child("tblLook")
        let mask: UInt16
        if let raw = look?.value {
            guard let parsed = UInt16(raw, radix: 16) else { throw DocumentError.invalidXML(part: part, detail: "invalid table look mask") }
            mask = parsed
        } else { mask = 0 }
        for (name, bit) in [("firstRow", 0x20), ("lastRow", 0x40), ("firstColumn", 0x80), ("lastColumn", 0x100), ("noHBand", 0x200), ("noVBand", 0x400)] {
            if let raw = look?.attr(name) {
                if let value = MarkupNode.boolean(raw) { flags[name] = value } else { properties.unparsed(look!, part: part) }
            } else { flags[name] = Int(mask) & bit != 0 }
        }
        if let look, properties.hasExtraAttributes(look, allowed: ["val", "firstRow", "lastRow", "firstColumn", "lastColumn", "noHBand", "noVBand"]) || !look.children.isEmpty { properties.unparsed(look, part: part) }
        func rows(_ n: MarkupNode) -> [MarkupNode] {
            if n.isWord && n.name == "tr" {
                if options.revisions == .final && n.child("trPr")?.child("del") != nil { return [] }
                if options.revisions == .original && n.child("trPr")?.child("ins") != nil { return [] }
                return [n]
            }
            if n.isWord && n.name == "del" && options.revisions == .final { return [] }
            if n.isWord && n.name == "ins" && options.revisions == .original { return [] }
            if n.isWord && ["tbl", "sdt", "sdtContent", "ins", "del"].contains(n.name) { return n.children.flatMap(rows) }
            return []
        }
        let all = rows(node); rowCount = all.count
        self.columnCount = columnCount
        func selected(_ node: MarkupNode?, name: String) -> MarkupNode? {
            options.revisions == .original ? node?.child(name + "Change")?.child(name) ?? node : node
        }
        for row in all {
            func cells(_ n: MarkupNode) -> [MarkupNode] {
                if n.isWord && n.name == "tc" { return [n] }
                if n.isWord && ["tr", "sdt", "sdtContent", "ins", "del"].contains(n.name) { return n.children.flatMap(cells) }
                return []
            }
            func number(_ node: MarkupNode?, fallback: Int) throws -> Int {
                guard let node else { return fallback }
                guard let value = node.value.flatMap(Int.init), value >= 0 else { throw DocumentError.invalidXML(part: part, detail: "invalid table grid position") }
                return value
            }
            let rowProperties = selected(row.child("trPr"), name: "trPr")
            var count = try number(rowProperties?.child("gridBefore"), fallback: 0)
            for cell in cells(row) {
                let span = try number(selected(cell.child("tcPr"), name: "tcPr")?.child("gridSpan"), fallback: 1)
                let (sum, overflow) = count.addingReportingOverflow(span)
                guard !overflow else { throw DocumentError.invalidXML(part: part, detail: "table grid overflow") }; count = sum
            }
            let trailing = try number(rowProperties?.child("gridAfter"), fallback: 0)
            let (sum, overflow) = count.addingReportingOverflow(trailing)
            guard !overflow else { throw DocumentError.invalidXML(part: part, detail: "table grid overflow") }; count = sum
            self.columnCount = max(self.columnCount, count)
        }
        for rule in rules where rule.region == .wholeTable { formatting.merge(rule.table) }
    }
    func resolve(row: Int, column: Int, span: Int) -> (text: ResolvedStyle, cell: TableCellFormatting) {
        let firstRow = row == 0 && flags["firstRow"] == true, lastRow = row == rowCount - 1 && flags["lastRow"] == true
        let firstCol = column == 0 && flags["firstColumn"] == true, lastCol = column + span == columnCount && flags["lastColumn"] == true
        var order: [TableStyleRegion] = [.wholeTable]
        if flags["noHBand"] != true && !firstRow && !lastRow {
            let index = max(0, row - (flags["firstRow"] == true ? 1 : 0)) / rowBand
            order.append(index % 2 == 0 ? .oddRowBand : .evenRowBand)
        }
        if flags["noVBand"] != true && !firstCol && !lastCol {
            let index = max(0, column - (flags["firstColumn"] == true ? 1 : 0)) / columnBand
            order.append(index % 2 == 0 ? .oddColumnBand : .evenColumnBand)
        }
        if firstCol { order.append(.firstColumn) }; if lastCol { order.append(.lastColumn) }
        if firstRow { order.append(.firstRow) }; if lastRow { order.append(.lastRow) }
        if firstRow && firstCol { order.append(.topLeft) }; if firstRow && lastCol { order.append(.topRight) }
        if lastRow && firstCol { order.append(.bottomLeft) }; if lastRow && lastCol { order.append(.bottomRight) }
        var text = base, cell = TableCellFormatting()
        for region in order {
            var regionText = TextFormatting()
            for rule in rules where rule.region == region {
                text.paragraph.merge(rule.paragraph); regionText.merge(rule.text, toggling: true)
                cell.mergeAppearance(rule.cell)
            }
            text.text.merge(regionText)
        }
        return (text, cell)
    }
}
