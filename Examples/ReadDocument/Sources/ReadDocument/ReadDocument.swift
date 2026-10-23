import Foundation
import SwiftDocuments

@main enum ReadDocumentExample {
    static func inspect(_ control: ContentControl, in document: Document) async throws {
        print("Control:", control.descriptor.kind, control.descriptor.id ?? "", "cached text:", control.plainText)
        switch control.content {
        case .blocks(let values): for value in values { try await inspect(value, in: document) }
        case .inlines(let values): for value in values { try await inspect(value, in: document) }
        }
    }
    static func inspect(_ node: DrawingNode, in document: Document) async throws {
        print("Drawing:", node.kind, node.transform.bounds)
        if let chart = node.chart {
            print("Chart:", chart.title ?? "", "groups:", chart.groups.count)
            for group in chart.groups {
                for series in group.series {
                    for point in series.values?.points ?? [] { print("Point:", point.index, point.text) }
                }
            }
        }
        for block in node.text { try await inspect(block, in: document) }
        for child in node.children { try await inspect(child, in: document) }
    }
    static func inspect(_ inline: Inline, in document: Document) async throws {
        switch inline {
        case .text(let run):
            if let symbol = run.symbol { print("Source symbol:", symbol.fontName, symbol.characterCode) }
        case .drawing(let value): try await inspect(value.root, in: document)
        case .equation(let value): print("Equation tokens:", value.lexicalText)
        case .ruby(let value):
            print("Ruby:", value.annotation.map(\.plainText).joined())
            for inline in value.base + value.annotation { try await inspect(inline, in: document) }
        case .hyperlink(let value): for inline in value.inlines { try await inspect(inline, in: document) }
        case .field(let value):
            if let fragment = value.fragment {
                print("Field fragment:", fragment.definitionID, "start:", fragment.startsHere, "end:", fragment.endsHere)
            }
            for inline in value.codeContent + value.result { try await inspect(inline, in: document) }
        case .contentControl(let value): try await inspect(value, in: document)
        case .image(let value):
            if let path = value.assetPath {
                let bytes = try await document.asset(at: path)
                print("Image:", path, "bytes:", bytes.count, "fallback:", value.fallbackAssetPath ?? value.fallbackExternalURL ?? "")
            }
        default: break
        }
    }
    static func inspect(_ block: Block, in document: Document) async throws {
        switch block {
        case .paragraph(let value): for inline in value.inlines { try await inspect(inline, in: document) }
        case .table(let value):
            for control in value.rowControls { print("Row control:", control.range, control.descriptor.id ?? "") }
            for row in value.rows {
                for control in row.cellControls { print("Cell control:", control.range, control.descriptor.id ?? "") }
                for cell in row.cells { for block in cell.blocks { try await inspect(block, in: document) } }
            }
        case .contentControl(let value): try await inspect(value, in: document)
        case .unsupported(let value): print("Uninterpreted:", value.sourcePart, value.name)
        }
    }
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let path = arguments.last else {
            print("Usage: ReadDocument [--scan] file.docx")
            return
        }
        let url = URL(filePath: path)
        if arguments.first == "--scan" {
            let result = try Document.scan(contentsOf: url) { print($0.plainText) }
            print("Blocks:", result.blocksRead, "Warnings:", result.warnings.count)
            return
        }
        let result = try await Document.read(contentsOf: url, options: .init(revisions: .all))
        let document = result.document
        print(document.plainText)
        for field in document.fieldDefinitions {
            print("Field:", field.id, field.instruction, "complete:", field.isComplete)
        }
        for block in document.blocks { try await inspect(block, in: document) }
        for story in document.stories {
            print("Story:", story.kind, story.id)
            for block in story.blocks { try await inspect(block, in: document) }
        }
        if let path = document.packageParts.first(where: { $0.path.hasSuffix(".xml") })?.path {
            let source = try await document.readSourceXML(at: path)
            print("Source XML:", path, source.root.qualifiedName)
        }
        for warning in result.warnings {
            print("Warning:", warning.code.rawValue, warning.part, warning.element, "count:", warning.count)
        }
    }
}
