import Foundation
import DocumentCore

/// Metadata only: cached body content is never retained here.
final class FieldRegistry {
    var definitions: [FieldDefinition] = []
    private var counts: [String: Int] = [:]
    func add(_ node: MarkupNode, parentID: String?, reader: StoryReader, simple: Bool = false) throws -> Int {
        counts[reader.part, default: 0] += 1
        let header = MarkupNode(name: node.name, namespace: node.namespace, attributes: node.attributes)
        header.namespaceBindings = node.namespaceBindings
        if !simple { header.content = node.content }
        let definition = FieldDefinition(id: "\(reader.part)#field-\(counts[reader.part]!)", parentID: parentID,
            kind: simple ? .simple : .complex, sourcePart: reader.part, instruction: simple ? node.attr("instr") ?? "" : "",
            isLocked: node.attr("fldLock").flatMap(MarkupNode.boolean), isDirty: node.attr("dirty").flatMap(MarkupNode.boolean),
            hasSeparator: false, isComplete: simple, source: try SourceXMLNode(header))
        definitions.append(definition)
        return definitions.count - 1
    }
}

private struct FieldSegment {
    var index: Int
    var fragment: FieldFragment
    var instruction = ""
    var code: [Inline] = []
    var result: [Inline] = []
    var touched = false
    func value(in registry: FieldRegistry) -> Inline {
        let definition = registry.definitions[index]
        var field = Field(instruction: instruction, result: result, isLocked: definition.isLocked ?? false)
        field.codeContent = code; field.fragment = fragment
        return .field(field)
    }
}

/// Open identities survive paragraphs; segment content belongs only to the current resolve call.
final class FieldReader {
    private var open: [Int] = []
    private let parentID: String?
    init(parentID: String? = nil) { self.parentID = parentID }

    func resolve(_ tokens: [InlineToken], reader: StoryReader) throws -> [Inline] {
        let registry = reader.references.fields
        func continuations() -> [FieldSegment] {
            open.map { FieldSegment(index: $0, fragment: FieldFragment(definitionID: registry.definitions[$0].id)) }
        }
        var segments = continuations(), output: [Inline] = []
        func append(_ inline: Inline) {
            guard let last = segments.indices.last else { output.append(inline); return }
            if registry.definitions[segments[last].index].hasSeparator { segments[last].result.append(inline) }
            else { segments[last].code.append(inline) }
            segments[last].touched = true
        }
        func flush(force: Bool) {
            while let segment = segments.popLast() {
                if force || segment.touched { append(segment.value(in: registry)) }
            }
            segments = continuations()
        }
        // Wrappers own their original content. Split active field fragments around them,
        // then resume with whatever open identities remain after their children.
        func container(_ build: () throws -> Inline) throws {
            flush(force: false)
            output.append(try build())
            segments = continuations()
        }
        for token in tokens {
            try Task.checkCancellation()
            switch token {
            case .inline(let inline): append(inline)
            case .begin(let node):
                guard open.count < reader.options.limits.maxXMLDepth else { throw DocumentError.limitExceeded("field nesting") }
                let parent = open.last.map { registry.definitions[$0].id } ?? parentID
                let index = try registry.add(node, parentID: parent, reader: reader)
                open.append(index)
                segments.append(FieldSegment(index: index, fragment: FieldFragment(definitionID: registry.definitions[index].id, startsHere: true), touched: true))
            case .instruction(let run):
                if let index = open.last, !registry.definitions[index].hasSeparator {
                    registry.definitions[index].instruction += run.text
                    segments[segments.count - 1].instruction += run.text
                    append(.text(run))
                } else {
                    reader.fieldWarning("instrText", "Field instruction is outside a field's code region; its literal text was retained.")
                    append(.text(run))
                }
            case .separate:
                if let index = open.last, !registry.definitions[index].hasSeparator {
                    registry.definitions[index].hasSeparator = true
                    segments[segments.count - 1].fragment.containsSeparator = true
                    segments[segments.count - 1].touched = true
                } else { reader.fieldWarning("fldChar", "Field separator has no matching code region.") }
            case .end:
                if let index = open.popLast(), var segment = segments.popLast() {
                    registry.definitions[index].isComplete = true
                    segment.fragment.endsHere = true
                    append(segment.value(in: registry))
                } else { reader.fieldWarning("fldChar", "Field end has no matching opening marker.") }
            case .simple(let node, let children):
                guard node.attr("instr") != nil else { throw DocumentError.invalidXML(part: reader.part, detail: "simple field has no instruction attribute") }
                reader.fieldProperties(node, simple: true)
                let parent = open.last.map { registry.definitions[$0].id } ?? parentID
                let index = try registry.add(node, parentID: parent, reader: reader, simple: true)
                let nested = FieldReader(parentID: registry.definitions[index].id)
                let content = try nested.resolve(children, reader: reader)
                nested.finish(reader: reader)
                var field = Field(instruction: registry.definitions[index].instruction, result: content,
                                  isLocked: registry.definitions[index].isLocked ?? false)
                field.fragment = FieldFragment(definitionID: registry.definitions[index].id, startsHere: true, endsHere: true)
                append(.field(field))
            case .hyperlink(var link, let children):
                try container { link.inlines = try resolve(children, reader: reader); return .hyperlink(link) }
            case .control(let descriptor, let children):
                try container { .contentControl(ContentControl(descriptor: descriptor, content: .inlines(try resolve(children, reader: reader)))) }
            case .ruby(var ruby, let base, let annotation):
                try container {
                    ruby.base = try resolve(base, reader: reader)
                    let separate = FieldReader()
                    ruby.annotation = try separate.resolve(annotation, reader: reader)
                    separate.finish(reader: reader)
                    return .ruby(ruby)
                }
            case .drawing(let node, let legacy, let revision):
                // Shape text has its own field scope; its definition IDs share the source-part registry.
                for value in try legacy ? reader.legacyDrawingTokens(node) : reader.drawingTokens(node) {
                    if case .inline(let inline) = value {
                        switch inline {
                        case .drawing(var drawing):
                            drawing.revision = revision; append(.drawing(drawing))
                        case .image(var image):
                            image.revision = revision; image.drawing?.revision = revision; append(.image(image))
                        default: append(inline)
                        }
                    }
                }
            }
        }
        flush(force: true)
        return output
    }

    func finish(reader: StoryReader) {
        for _ in open { reader.fieldWarning("fldChar", "An unclosed field was retained as incomplete fragments at the end of its story.") }
        open.removeAll()
    }
}

extension StoryReader {
    func fieldWarning(_ element: String, _ message: String) {
        warnings.add(.incompleteField, part: part, element: element, message: message)
    }
    func fieldProperties(_ node: MarkupNode, simple: Bool = false) {
        let allowed: Set<String> = simple ? ["instr", "fldLock", "dirty"] : ["fldCharType", "fldLock", "dirty"]
        var uninterpreted = properties.hasExtraAttributes(node, allowed: allowed)
        for key in ["fldLock", "dirty"] where node.attr(key) != nil && node.attr(key).flatMap(MarkupNode.boolean) == nil {
            uninterpreted = true
        }
        if !simple && node.attr("fldCharType") != "begin", node.attr("fldLock") != nil || node.attr("dirty") != nil { uninterpreted = true }
        if uninterpreted { properties.unparsed(node, part: part) }
        if !simple { for child in node.children { _ = unsupported(child) } }
    }
    func finishFields() { fieldReader.finish(reader: self) }
    func independentStoryBlocks(_ nodes: [MarkupNode]) throws -> [Block] {
        let enclosing = fieldReader
        fieldReader = FieldReader()
        defer { fieldReader = enclosing }
        let result = try storyBlocks(nodes)
        finishFields()
        return result
    }
}
