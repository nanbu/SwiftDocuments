import Foundation
import DocumentCore

private let sectionAttributes: [String: Set<String>] = [
    "pgSz": ["w", "h", "orient"], "pgMar": ["top", "right", "bottom", "left", "header", "footer", "gutter"],
    "cols": ["num", "equalWidth", "space", "sep"], "type": ["val"], "titlePg": ["val"],
    "textDirection": ["val"], "docGrid": ["type", "linePitch", "charSpace"],
    "headerReference": ["type"], "footerReference": ["type"]
]

extension StoryReader {
    func section(_ node: MarkupNode) throws -> Section {
        var section = Section(); section.rawProperties = node.children.map(\.xml)
        if !node.attributes.isEmpty { section.rawProperties.append(node.xml); properties.unparsed(node, part: part) }
        if let size = node.child("pgSz") {
            section.pageWidth = points(size.attr("w")); section.pageHeight = points(size.attr("h"))
            section.orientation = size.attr("orient").flatMap(PageOrientation.init(rawValue:))
        }
        if let margins = node.child("pgMar") {
            for key in ["top", "right", "bottom", "left", "header", "footer", "gutter"] {
                if let value = points(margins.attr(key)) { section.margins[key] = value }
            }
        }
        if let columns = node.child("cols") {
            section.columnCount = integer(columns.attr("num")).flatMap { $0 > 0 ? $0 : nil } ?? 1
            section.equalColumnWidths = columns.attr("equalWidth").flatMap { MarkupNode.boolean($0) }
            section.columnSeparator = columns.attr("sep").flatMap { MarkupNode.boolean($0) }
            section.columnSpacing = points(columns.attr("space"))
            section.columns = columns.wordChildren("col").map { SectionColumn(width: points($0.attr("w")), spacingAfter: points($0.attr("space"))) }
        }
        section.breakKind = node.child("type")?.value
        section.hasDifferentFirstPage = node.child("titlePg")?.on ?? false
        section.textDirection = node.child("textDirection")?.value
        if let grid = node.child("docGrid") {
            for key in ["type", "linePitch", "charSpace"] { section.documentGrid[key] = grid.attr(key) }
        }
        for child in node.children {
            guard child.isWord, let allowed = sectionAttributes[child.name] else { properties.unparsed(child, part: part); continue }
            let isReference = ["headerReference", "footerReference"].contains(child.name)
            var incomplete = properties.hasExtraAttributes(child, allowed: allowed, relationships: isReference ? ["id"] : [])
            if child.name != "cols" && !child.children.isEmpty { incomplete = true }
            let lengths: [String]
            switch child.name {
            case "pgSz": lengths = ["w", "h"]
            case "pgMar": lengths = ["top", "right", "bottom", "left", "header", "footer", "gutter"]
            case "cols": lengths = ["space"]
            default: lengths = []
            }
            if lengths.contains(where: { child.attr($0) != nil && points(child.attr($0)) == nil }) { incomplete = true }
            if child.name == "pgSz", let orientation = child.attr("orient"), PageOrientation(rawValue: orientation) == nil { incomplete = true }
            if child.name == "titlePg" && child.onOffValue == nil { incomplete = true }
            if child.name == "cols" {
                if let count = child.attr("num"), integer(count).map({ $0 > 0 }) != true { incomplete = true }
                if ["equalWidth", "sep"].contains(where: { child.attr($0) != nil && MarkupNode.boolean(child.attr($0)) == nil }) { incomplete = true }
                if child.children.contains(where: { col in
                    !col.isWord || col.name != "col" || properties.hasExtraAttributes(col, allowed: ["w", "space"]) || !col.children.isEmpty ||
                        ["w", "space"].contains(where: { col.attr($0) != nil && points(col.attr($0)) == nil })
                }) { incomplete = true }
            }
            if isReference {
                guard let id = child.rel("id") else { throw DocumentError.invalidRelationship(part: part, detail: "missing header / footer relationship") }
                let header = child.name == "headerReference", relation = try relationship(id, expected: header ? "header" : "footer")
                guard let path = relation.path else { throw DocumentError.invalidRelationship(part: part, detail: "external header / footer") }
                if header { section.headers[child.attr("type") ?? "default"] = path }
                else { section.footers[child.attr("type") ?? "default"] = path }
            }
            if incomplete { properties.unparsed(child, part: part) }
        }
        return section
    }
}
