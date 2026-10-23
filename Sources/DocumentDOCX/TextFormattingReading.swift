import Foundation
import DocumentCore

extension StoryReader {
    func textFormatting(_ current: MarkupNode?, base: TextFormatting, paragraphMark: Bool = false) throws -> (TextFormatting, TextFormattingChange?, String?) {
        let former = try formerProperties(current, change: "rPrChange", properties: "rPr")
        let selected = options.revisions == .original ? former?.1 ?? current : current
        let ignored: Set<String> = paragraphMark ? ["ins", "del", "moveFrom", "moveTo"] : []
        func resolve(_ node: MarkupNode?) throws -> TextFormatting {
            let style = node?.child("rStyle")?.value
            if let style, styles.styles[style] == nil {
                warnings.add(.invalidReference, part: part, element: "rStyle", message: "Referenced character style is missing; the source ID and available formatting are retained.")
            }
            var result = try styles.text(style, base: base, direct: properties.text(node, part: part, ignoringChildren: ignored))
            if node?.child("rFonts") == nil { properties.resolveFonts(&result, node: node, part: part) }
            return result
        }
        let change = try former.map { record, previous in
            try TextFormattingChange(revision: readRevision(record, kind: .formatting), previous: resolve(previous), source: SourceXMLNode(record))
        }
        let formatting = try options.revisions == .original ? change?.previous ?? resolve(selected) : resolve(selected)
        return (formatting, change, selected?.child("rStyle")?.value)
    }
    func paragraphMark(_ node: MarkupNode?, base: TextFormatting, paragraph: inout Paragraph) throws {
        guard let node else { return }
        let (formatting, change, _) = try textFormatting(node, base: base, paragraphMark: true)
        paragraph.paragraphMarkFormatting = formatting; paragraph.paragraphMarkFormattingChange = change
        for child in node.children where child.isWord {
            let kind: Revision.Kind
            switch child.name { case "ins": kind = .insertion; case "del": kind = .deletion; case "moveFrom": kind = .moveFrom; case "moveTo": kind = .moveTo; default: continue }
            paragraph.paragraphMarkRevisions.append(readRevision(child, kind: kind))
            if !child.children.isEmpty { properties.unparsed(child, part: part) }
        }
        if paragraph.paragraphMarkRevisions.count > 1 || paragraph.paragraphMarkRevisions.contains(where: { [.moveFrom, .moveTo].contains($0.kind) }) {
            warnings.add(.unsupportedContent, part: part, element: "paragraphMarkRevisions", message: "Multiple or moved paragraph-mark annotations are retained without projecting a paragraph join.")
        }
    }
}
