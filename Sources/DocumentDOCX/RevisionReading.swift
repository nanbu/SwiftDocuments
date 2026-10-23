import Foundation
import DocumentCore

func sourceRevision(_ node: MarkupNode, kind: Revision.Kind) -> Revision {
    Revision(id: node.attr("id") ?? "", kind: kind, author: node.attr("author"), date: node.attr("date"), sourceAttributes: node.attributes)
}

/// Retains only a paragraph awaiting removal of its terminating mark, not the complete body.
final class ParagraphJoiner {
    private var pending: Paragraph?
    private let view: ReadOptions.RevisionView
    private let warnings: WarningCollector?
    private let part: String
    init(view: ReadOptions.RevisionView, warnings: WarningCollector? = nil, part: String = "") { self.view = view; self.warnings = warnings; self.part = part }
    private func joins(_ p: Paragraph) -> Bool {
        guard p.paragraphMarkRevisions.count == 1, let change = p.paragraphMarkRevision else { return false }
        return (view == .final && change.kind == .deletion) || (view == .original && change.kind == .insertion)
    }
    func offer(_ block: Block) -> [Block] {
        var emitted: [Block] = []
        if case .paragraph(var paragraph) = block {
            if let previous = pending { paragraph.inlines = previous.inlines + paragraph.inlines; pending = nil }
            if joins(paragraph) { pending = paragraph } else { emitted.append(.paragraph(paragraph)) }
        } else {
            if let previous = pending {
                if case .contentControl = block { warnings?.add(.unsupportedContent, part: part, element: "controlParagraphMarkJoin", message: "Cross-control paragraph-mark join retained as a source revision; the control boundary is preserved.") }
                emitted.append(.paragraph(previous)); pending = nil
            }
            emitted.append(block)
        }
        return emitted
    }
    func finish() -> [Block] {
        defer { pending = nil }
        return pending.map { [.paragraph($0)] } ?? []
    }
}

extension StoryReader {
    func changedProperties<Value: Sendable>(_ node: MarkupNode?, change: String, properties name: String,
                                            decode: (MarkupNode?) throws -> Value) throws -> (Value, FormattingChange<Value>?) {
        let former = try formerProperties(node, change: change, properties: name)
        let history = try former.map { record, previous in
            try FormattingChange(revision: readRevision(record, kind: .formatting), previous: decode(previous), source: SourceXMLNode(record))
        }
        if options.revisions == .original, let history { return (history.previous, history) }
        return (try decode(node), history)
    }
    func readRevision(_ node: MarkupNode, kind: Revision.Kind) -> Revision {
        var allowed: Set<String> = ["id", "author", "date"]
        if node.isWord && node.name == "cellMerge" { allowed.formUnion(["vMerge", "vMergeOrig"]) }
        if properties.hasExtraAttributes(node, allowed: allowed) { properties.unparsed(node, part: part) }
        return sourceRevision(node, kind: kind)
    }
    func storyBlocks(_ nodes: [MarkupNode]) throws -> [Block] {
        let joiner = ParagraphJoiner(view: options.revisions, warnings: warnings, part: part)
        return try blocks(nodes).flatMap { joiner.offer($0) } + joiner.finish()
    }
    func makeRun(_ text: String, formatting: TextFormatting, styleID: String? = nil, revision: Revision? = nil, change: TextFormattingChange? = nil) -> TextRun {
        var run = TextRun(text, formatting: formatting, styleID: styleID, revision: revision)
        run.formattingChange = change
        return run
    }
}
