import Foundation
import DocumentCore

extension Properties {
    func tableColumns(_ node: MarkupNode?, part: String) throws -> [TableColumn] {
        guard let node else { return [] }
        var result: [TableColumn] = []
        for child in node.children {
            guard child.isWord, child.name == "gridCol" else {
                if !(child.isWord && child.name == "tblGridChange") { unparsed(child, part: part) }
                continue
            }
            let raw = child.attr("w"), width = points(raw)
            if raw != nil && (width == nil || width! < 0) { throw DocumentError.invalidXML(part: part, detail: "invalid table column width") }
            var column = TableColumn(width: width, sourceWidth: raw)
            if hasExtraAttributes(child, allowed: ["w"]) || !child.children.isEmpty { column.rawProperties = [child.xml]; unparsed(child, part: part) }
            result.append(column)
        }
        return result
    }
    func tableFormatting(_ node: MarkupNode?, part: String) throws -> TableFormatting {
        var result = TableFormatting(); guard let node else { return result }
        result.styleID = node.child("tblStyle")?.value
        result.preferredWidth = try tableWidth(node.child("tblW"), part: part)
        result.borders = try tableBorders(node.child("tblBorders"), part: part)
        result.cellMargins = try tableMargins(node.child("tblCellMar"), part: part)
        result.indentation = try tableIndentation(node.child("tblInd"), part: part)
        result.cellSpacing = try tableWidth(node.child("tblCellSpacing"), part: part)
        result.rightToLeft = tableFlag(node.child("bidiVisual"), part: part)
        result.shading = tableShading(node.child("shd"), part: part)
        if let alignment = node.child("jc") {
            result.alignment = alignment.value.flatMap(TableAlignment.init(rawValue:))
            if result.alignment == nil || hasExtraAttributes(alignment, allowed: ["val"]) || !alignment.children.isEmpty || tablePropertyHasText(alignment) { unparsed(alignment, part: part) }
        }
        if let layout = node.child("tblLayout") {
            result.layout = ["autofit": .automatic, "fixed": .fixed][layout.attr("type") ?? ""]
            if result.layout == nil || hasExtraAttributes(layout, allowed: ["type"]) || !layout.children.isEmpty || tablePropertyHasText(layout) { unparsed(layout, part: part) }
        }
        result.rawProperties = node.children.map(\.xml)
        let change = node.name == "tblPrEx" ? "tblPrExChange" : "tblPrChange"
        for child in node.children where !child.isWord || !["tblStyle", "tblW", change, "tblLook", "tblStyleRowBandSize", "tblStyleColBandSize", "tblBorders", "tblCellMar", "tblInd", "tblCellSpacing", "bidiVisual", "jc", "tblLayout", "shd"].contains(child.name) { unparsed(child, part: part) }
        if let style = node.child("tblStyle"), hasExtraAttributes(style, allowed: ["val"]) || !style.children.isEmpty { unparsed(style, part: part) }
        if !node.attributes.isEmpty || tablePropertyHasText(node) { result.rawProperties.append(node.xml); unparsed(node, part: part) }
        return result
    }
    func rowFormatting(_ node: MarkupNode?, part: String) throws -> TableRowFormatting {
        var result = TableRowFormatting(); guard let node else { return result }
        result.preventSplit = tableFlag(node.child("cantSplit"), part: part)
        for (name, assign) in [("gridBefore", { result.omittedLeadingColumns = $0 }), ("gridAfter", { result.omittedTrailingColumns = $0 })] {
            if let grid = node.child(name) {
                guard let value = grid.value.flatMap(Int.init), value >= 0 else { throw DocumentError.invalidXML(part: part, detail: "invalid omitted table grid columns") }
                assign(value)
            }
        }
        result.leadingWidth = try tableWidth(node.child("wBefore"), part: part)
        result.trailingWidth = try tableWidth(node.child("wAfter"), part: part)
        result.isHeader = node.child("tblHeader")?.on ?? false
        if let header = node.child("tblHeader"), header.onOffValue == nil { unparsed(header, part: part) }
        if let height = node.child("trHeight") {
            result.height = points(height.value)
            if height.value != nil && (result.height == nil || result.height! < 0) { throw DocumentError.invalidXML(part: part, detail: "invalid row height") }
            if let rule = height.attr("hRule") {
                result.heightRule = ["auto": .automatic, "exact": .exact, "atLeast": .minimum][rule]
                if result.heightRule == nil { unparsed(height, part: part) }
            }
        }
        result.rawProperties = node.children.map(\.xml)
        let allowed: [String: Set<String>] = ["tblHeader": ["val"], "trHeight": ["val", "hRule"], "gridBefore": ["val"], "gridAfter": ["val"]]
        for child in node.children {
            if child.isWord, ["ins", "del", "trPrChange", "cantSplit", "wBefore", "wAfter"].contains(child.name) { continue }
            if !child.isWord || allowed[child.name] == nil || hasExtraAttributes(child, allowed: allowed[child.name] ?? []) || !child.children.isEmpty { unparsed(child, part: part) }
        }
        if !node.attributes.isEmpty || tablePropertyHasText(node) { result.rawProperties.append(node.xml); unparsed(node, part: part) }
        return result
    }
    func cellFormatting(_ node: MarkupNode?, part: String) throws -> TableCellFormatting {
        var result = TableCellFormatting(); guard let node else { return result }
        if let span = node.child("gridSpan") {
            guard let value = span.value.flatMap(Int.init), value > 0 else { throw DocumentError.invalidXML(part: part, detail: "invalid cell column span") }
            result.columnSpan = value
        }
        if let merge = node.child("vMerge") {
            switch merge.value { case "restart": result.verticalMerge = .restart; case nil, "continue": result.verticalMerge = .continuation; default: unparsed(merge, part: part) }
        }
        result.preferredWidth = try tableWidth(node.child("tcW"), part: part)
        result.borders = try tableBorders(node.child("tcBorders"), part: part, cell: true)
        result.margins = try tableMargins(node.child("tcMar"), part: part)
        result.textDirection = node.child("textDirection")?.value
        result.noWrap = tableFlag(node.child("noWrap"), part: part)
        result.fitText = tableFlag(node.child("tcFitText"), part: part)
        result.verticalAlignment = node.child("vAlign")?.value; result.shading = tableShading(node.child("shd"), part: part)
        result.rawProperties = node.children.map(\.xml)
        let allowed: [String: Set<String>] = ["gridSpan": ["val"], "vMerge": ["val"], "tcW": ["w", "type"], "vAlign": ["val"], "shd": ["fill"], "textDirection": ["val"]]
        for child in node.children {
            if child.isWord, ["cellIns", "cellDel", "cellMerge", "tcPrChange"].contains(child.name) { continue }
            if child.isWord && ["tcW", "tcBorders", "tcMar", "noWrap", "tcFitText", "shd"].contains(child.name) { continue } // Helpers report their own unparsed data.
            if !child.isWord || allowed[child.name] == nil || hasExtraAttributes(child, allowed: allowed[child.name] ?? []) || !child.children.isEmpty { unparsed(child, part: part) }
        }
        if !node.attributes.isEmpty || tablePropertyHasText(node) { result.rawProperties.append(node.xml); unparsed(node, part: part) }
        return result
    }
}

extension StoryReader {
    func formerProperties(_ node: MarkupNode?, change: String, properties: String) throws -> (MarkupNode, MarkupNode)? {
        guard let node else { return nil }
        let records = node.wordChildren(change)
        guard records.count <= 1 else { throw DocumentError.invalidXML(part: part, detail: "duplicate formatting change") }
        guard let record = records.first else { return nil }
        let values = record.wordChildren(properties)
        guard values.count == 1 else { throw DocumentError.invalidXML(part: part, detail: "missing / duplicate previous formatting") }
        for child in record.children where !child.isWord || child.name != properties { self.properties.unparsed(child, part: part) }
        return (record, values[0])
    }
    func cellMergeChange(_ node: MarkupNode?) throws -> CellMergeChange? {
        guard let node else { return nil }
        func state(_ name: String) throws -> Bool {
            switch node.attr(name) { case nil, "rest": false; case "cont": true; default: throw DocumentError.invalidXML(part: part, detail: "invalid tracked cell merge state") }
        }
        return try CellMergeChange(revision: readRevision(node, kind: .formatting), wasMergedWithPrevious: state("vMergeOrig"), isMergedWithPrevious: state("vMerge"), source: SourceXMLNode(node))
    }
}
