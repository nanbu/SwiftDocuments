import Foundation

/// Options for basic model serialization, independently of reading options.
public struct WriteOptions: Sendable, Equatable, Codable {
    /// Refuse any diagnosed loss before returning bytes or committing a file.
    public var strict: Bool
    /// Compress generated ZIP parts; ODT's first mimetype entry is always stored.
    public var compress: Bool
    public init(strict: Bool = false, compress: Bool = true) { self.strict = strict; self.compress = compress }
}
/// An aggregated serialization loss. Source package parts are not copied by basic writers.
public struct WriteWarning: Sendable, Equatable, Codable {
    public enum Code: String, Sendable, Codable { case omittedContent, flattenedContent, unsupportedFormatting, omittedMetadata, sourcePartsOmitted }
    public var code: Code
    public var element: String
    public var message: String
    public var count: Int
    public init(code: Code, element: String, message: String, count: Int = 1) {
        self.code = code; self.element = element; self.message = message; self.count = count
    }
}
/// Generated document bytes and writing losses, separate from source reading warnings.
public struct WriteResult: Sendable {
    public let data: Data
    public let warnings: [WriteWarning]
    public init(data: Data, warnings: [WriteWarning] = []) { self.data = data; self.warnings = warnings }
}
extension DocumentCodec {
    /// Reading-only custom codecs retain source compatibility.
    public func write(_ document: Document, options: WriteOptions = .init()) throws -> WriteResult {
        throw DocumentError.writingNotSupported(format)
    }
}
extension CodecSet {
    /// Serialize using an explicit format, the source format, or DOCX for a new document.
    public func write(_ document: Document, as format: DocumentFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult {
        try writeSync(document, as: format, options: options)
    }
    /// Serialize completely before atomically replacing a local destination.
    public func write(_ document: Document, to url: URL, as format: DocumentFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult {
        try writeURLSync(document, to: url, as: format, options: options)
    }
    /// Serialize on the generic executor, retaining cooperative task cancellation.
    @concurrent public func write(_ document: Document, as format: DocumentFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult {
        try writeSync(document, as: format, options: options)
    }
    /// Serialize and atomically save on the generic executor.
    @concurrent public func write(_ document: Document, to url: URL, as format: DocumentFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult {
        try writeURLSync(document, to: url, as: format, options: options)
    }
    private func writeSync(_ document: Document, as format: DocumentFormat?, options: WriteOptions) throws -> WriteResult {
        try Task.checkCancellation()
        let result = try codec(for: format ?? document.sourceFormat ?? .docx).implementation.write(document, options: options)
        try Task.checkCancellation()
        if options.strict && !result.warnings.isEmpty { throw DocumentError.writingLoss(result.warnings) }
        return result
    }
    private func writeURLSync(_ document: Document, to url: URL, as format: DocumentFormat?, options: WriteOptions) throws -> WriteResult {
        guard url.isFileURL else { throw DocumentError.invalidOptions("writing requires a file URL") }
        let result = try writeSync(document, as: format ?? DocumentFormat(fileExtension: url.pathExtension), options: options)
        try Task.checkCancellation()
        try result.data.write(to: url, options: .atomic)
        return result
    }
}

/// Shared supported-subset projection; format-specific spelling belongs in codecs.
package final class BasicWriting {
    package private(set) var warnings: [WriteWarning] = []
    private var remaining = 2_000_000
    package let richText: Bool
    package init(richText: Bool = true) { self.richText = richText }
    package func warn(_ code: WriteWarning.Code, _ element: String, _ message: String, count: Int = 1) {
        guard count > 0 else { return }
        if let i = warnings.firstIndex(where: { $0.code == code && $0.element == element }) { warnings[i].count += count }
        else { warnings.append(.init(code: code, element: element, message: message, count: count)) }
    }
    package func finish(_ data: Data, options: WriteOptions) throws -> WriteResult {
        try Task.checkCancellation()
        if options.strict && !warnings.isEmpty { throw DocumentError.writingLoss(warnings) }
        return WriteResult(data: data, warnings: warnings)
    }
    private func charge(_ depth: Int) throws {
        try Task.checkCancellation()
        guard depth <= 128, remaining > 0 else { throw DocumentError.invalidModel("writing model depth or node limit exceeded") }
        remaining -= 1
    }
    package func project(_ source: Document) throws -> Document {
        try preflight(source.blocks)
        var result = Document()
        if !source.packageParts.isEmpty { warn(.sourcePartsOmitted, "packageParts", "Basic writing regenerates the package; original parts, assets and macros are not copied.", count: source.packageParts.count) }
        if !source.readWarnings.isEmpty { warn(.omittedContent, "readWarnings", "The input contains reading warnings; unresolved source semantics are not reconstructed.", count: source.readWarnings.count) }
        if !source.stories.isEmpty { warn(.omittedContent, "stories", "Related stories are omitted.", count: source.stories.count) }
        if !source.sections.isEmpty { warn(.unsupportedFormatting, "sections", "Source sections and page layout are omitted.", count: source.sections.count) }
        if !source.styles.isEmpty { warn(.unsupportedFormatting, "styles", "Source style definitions are replaced by direct resolved formatting.", count: source.styles.count) }
        if !source.settings.isEmpty || !source.fonts.isEmpty || source.theme != nil { warn(.unsupportedFormatting, "documentSettings", "Source settings, font records and themes are omitted.") }
        if !source.uninterpretedContent.isEmpty || !source.fieldDefinitions.isEmpty { warn(.omittedContent, "sourceDefinitions", "Uninterpreted content and field definitions are omitted.") }
        let metadata = source.metadata
        if richText {
            result.metadata.title = metadata.title; result.metadata.subject = metadata.subject
            result.metadata.creator = metadata.creator; result.metadata.description = metadata.description; result.metadata.keywords = metadata.keywords
        }
        var rest = metadata
        if richText { rest.title = nil; rest.subject = nil; rest.creator = nil; rest.description = nil; rest.keywords = nil }
        if try JSONEncoder().encode(rest) != JSONEncoder().encode(DocumentMetadata()) { warn(.omittedMetadata, "metadata", "Metadata outside the basic writing subset is omitted.") }
        result.numbering = source.numbering
        result.blocks = try blocks(source.blocks, source: source, depth: 0)
        return result
    }
    // Validate the graph iteratively before any recursive formatting/text projections.
    // This also covers unsupported containers whose plainText helpers are recursive.
    private indirect enum Node {
        case block(Block), inline(Inline), control(ContentControl), drawing(DrawingNode), equation(EquationNode)
    }
    private func preflight(_ blocks: [Block]) throws {
        var pending: [(Node, Int)] = blocks.reversed().map { (.block($0), 0) }
        var count = 0
        while let (node, depth) = pending.popLast() {
            try Task.checkCancellation(); count += 1
            guard depth <= 32, count <= 2_000_000 else { throw DocumentError.invalidModel("basic writing supports at most 32 nested levels and 2,000,000 body nodes") }
            switch node {
            case .block(.paragraph(let p)):
                pending += p.inlines.reversed().map { (.inline($0), depth + 1) }
            case .block(.table(let table)):
                for row in table.rows.reversed() {
                    for cell in row.cells.reversed() { pending += cell.blocks.reversed().map { (.block($0), depth + 1) } }
                }
            case .block(.contentControl(let c)), .inline(.contentControl(let c)):
                pending.append((.control(c), depth + 1))
            case .inline(.hyperlink(let h)):
                pending += h.inlines.reversed().map { (.inline($0), depth + 1) }
            case .inline(.field(let f)):
                pending += f.result.reversed().map { (.inline($0), depth + 1) }
            case .inline(.ruby(let r)):
                pending += r.base.reversed().map { (.inline($0), depth + 1) }
            case .control(let c):
                switch c.content {
                case .blocks(let values): pending += values.reversed().map { (.block($0), depth + 1) }
                case .inlines(let values): pending += values.reversed().map { (.inline($0), depth + 1) }
                }
            case .inline(.drawing(let d)): pending.append((.drawing(d.root), depth + 1))
            case .drawing(let d):
                pending += d.children.reversed().map { (.drawing($0), depth + 1) }
                pending += d.text.reversed().map { (.block($0), depth + 1) }
            case .inline(.equation(let e)): pending.append((.equation(e.root), depth + 1))
            case .equation(let e): pending += e.children.reversed().map { (.equation($0), depth + 1) }
            default: break
            }
        }
    }
    private final class TableBuffer {
        var table = Table()
        var row = TableRow()
    }
    private enum BlockJob {
        case visit(Block, Int), beginRow(TableRow, Int), endRow, beginCell(TableCell, Int), endCell, endTable
    }
    private func blocks(_ values: [Block], source: Document, depth: Int) throws -> [Block] {
        var jobs: [BlockJob] = values.reversed().map { .visit($0, depth) }
        var outputs: [[Block]] = [[]]
        var tables: [TableBuffer] = []
        while let job = jobs.popLast() {
            try Task.checkCancellation()
            switch job {
            case .visit(let block, let level):
                try charge(level)
                switch block {
                case .paragraph(let p):
                    var value = Paragraph()
                    value.formatting = try paragraphFormatting(p.formatting)
                    value.defaultTextFormatting = try textFormatting(p.defaultTextFormatting)
                    value.inlines = try inlines(p.inlines, depth: level + 1)
                    if let list = p.list {
                        guard list.level >= 0 && list.level < 9 else { throw DocumentError.invalidModel("list level must be in 0...8") }
                        if richText, source.numbering[list.id]?.levels[list.level] != nil { value.list = list }
                        else { warn(.flattenedContent, "list", "List reference is unresolved or unsupported; item text is retained.") }
                    }
                    if p.paragraphMarkFormatting != nil || p.paragraphMarkFormattingChange != nil || !p.paragraphMarkRevisions.isEmpty || p.formattingChange != nil { warn(.unsupportedFormatting, "paragraphHistory", "Paragraph mark typography and revision history are omitted.") }
                    if p.sectionBreak != nil { warn(.unsupportedFormatting, "sectionBreak", "Paragraph section breaks are omitted.") }
                    if p.styleID != nil { warn(.unsupportedFormatting, "styleID", "Paragraph style identity is replaced by resolved formatting.") }
                    outputs[outputs.count - 1].append(.paragraph(value))
                case .table(let table):
                    guard !table.rows.isEmpty else { throw DocumentError.invalidModel("tables require at least one row") }
                    if !richText { warn(.flattenedContent, "table", "Table structure is projected to tab/newline-separated text.") }
                    else if table.styleID != nil || !table.columns.isEmpty || table.preferredWidth != nil || table.alignment != nil || table.layout != nil || table.indentation != nil || table.cellSpacing != nil || table.rightToLeft != nil || table.shading != nil || !table.borders.isEmpty || !table.cellMargins.isEmpty || !table.properties.isEmpty || table.formattingChange != nil || table.columnChange != nil || !table.rowControls.isEmpty { warn(.unsupportedFormatting, "tableFormatting", "Advanced table appearance and history are omitted.") }
                    if Set(table.rows.map { $0.cells.count }).count > 1 { warn(.flattenedContent, "tableGrid", "Nonrectangular table is written with physical cells only.") }
                    tables.append(TableBuffer()); jobs.append(.endTable)
                    for row in table.rows.reversed() {
                        jobs.append(.endRow)
                        for cell in row.cells.reversed() {
                            jobs.append(.endCell)
                            jobs += cell.blocks.reversed().map { .visit($0, level + 1) }
                            jobs.append(.beginCell(cell, level))
                        }
                        jobs.append(.beginRow(row, level))
                    }
                case .contentControl(let control):
                    warn(.flattenedContent, "contentControl", "Control semantics are removed; cached text is retained.")
                    switch control.content {
                    case .blocks(let children): jobs += children.reversed().map { .visit($0, level + 1) }
                    case .inlines(let children):
                        var p = Paragraph(); p.inlines = try inlines(children, depth: level + 1)
                        outputs[outputs.count - 1].append(.paragraph(p))
                    }
                case .unsupported(let content):
                    warn(.flattenedContent, "unsupported", "Unsupported source content is projected to its text.")
                    try Self.validateText(content.text)
                    var p = Paragraph(); p.inlines = [.text(TextRun(content.text))]
                    outputs[outputs.count - 1].append(.paragraph(p))
                }
            case .beginRow(let row, let level):
                try charge(level)
                guard !row.cells.isEmpty else { throw DocumentError.invalidModel("table rows require at least one cell") }
                if row.height != nil || row.heightRule != nil || row.preventSplit != nil || !row.properties.isEmpty || !row.revisions.isEmpty || row.formattingChange != nil || row.tableOverrides != nil || row.tableOverridesChange != nil || !row.cellControls.isEmpty || row.omittedLeadingColumns != 0 || row.omittedTrailingColumns != 0 || row.leadingWidth != nil || row.trailingWidth != nil { warn(.unsupportedFormatting, "rowFormatting", "Row appearance, omissions and history are omitted.") }
                tables[tables.count - 1].row = TableRow()
                tables[tables.count - 1].row.isHeader = row.isHeader
            case .endRow:
                let buffer = tables[tables.count - 1]; buffer.table.rows.append(buffer.row)
            case .beginCell(let cell, let level):
                try charge(level)
                guard cell.columnSpan > 0, cell.rowSpan > 0 else { throw DocumentError.invalidModel("table spans must be positive") }
                if cell.columnSpan != 1 || cell.rowSpan != 1 || cell.isCovered || cell.verticalMerge != nil { warn(.flattenedContent, "cellMerge", "Merged/covered cells are written as ordinary physical cells.") }
                if cell.preferredWidth != nil || cell.verticalAlignment != nil || cell.shading != nil || !cell.borders.isEmpty || !cell.margins.isEmpty || cell.textDirection != nil || cell.noWrap != nil || cell.fitText != nil || !cell.properties.isEmpty || !cell.revisions.isEmpty || cell.formattingChange != nil || cell.mergeChange != nil { warn(.unsupportedFormatting, "cellFormatting", "Cell appearance and history are omitted.") }
                outputs.append([])
            case .endCell:
                var cell = TableCell(); cell.blocks = outputs.removeLast()
                tables[tables.count - 1].row.cells.append(cell)
            case .endTable:
                let table = tables.removeLast().table
                if richText { outputs[outputs.count - 1].append(.table(table)) }
                else {
                    var p = Paragraph(); p.inlines = [.text(TextRun(table.plainText))]
                    outputs[outputs.count - 1].append(.paragraph(p))
                }
            }
        }
        return outputs[0]
    }
    private func inlines(_ values: [Inline], depth: Int, insideLink: Bool = false) throws -> [Inline] {
        try values.flatMap { inline -> [Inline] in
            try charge(depth)
            switch inline {
            case .text(let run):
                if run.revision != nil || run.symbol != nil || run.formattingChange != nil || run.styleID != nil { warn(.unsupportedFormatting, "runSource", "Run style identity, symbol metadata and revision history are omitted.") }
                try Self.validateText(run.text)
                return [.text(TextRun(run.text, formatting: try textFormatting(run.formatting)))]
            case .tab, .lineBreak: return [inline]
            case .hyperlink(let link):
                let children = try inlines(link.inlines, depth: depth + 1, insideLink: true)
                if insideLink { warn(.flattenedContent, "nestedHyperlink", "Nested link targets are removed; display text is retained."); return children }
                if link.anchor != nil { warn(.flattenedContent, "hyperlinkAnchor", "Bookmark anchors are not reconstructed; the display text and external target, if present, are retained.") }
                if richText { return [.hyperlink(Hyperlink(target: link.target, anchor: link.anchor, tooltip: link.tooltip, inlines: children))] }
                warn(.flattenedContent, "hyperlink", "Link target is removed; display text is retained."); return children
            case .contentControl(let control):
                warn(.flattenedContent, "contentControl", "Control semantics are removed; cached text is retained.")
                switch control.content {
                case .inlines(let children): return try inlines(children, depth: depth + 1, insideLink: insideLink)
                case .blocks(let children):
                    let projected = try blocks(children, source: Document(), depth: depth + 1)
                    return [.text(TextRun(projected.map(\.plainText).joined(separator: "\n")))]
                }
            case .field(let field):
                warn(.flattenedContent, "field", "Field instructions and history are removed; cached text is retained.")
                return try inlines(field.result, depth: depth + 1, insideLink: insideLink)
            case .ruby(let ruby):
                warn(.flattenedContent, "ruby", "Ruby annotations are removed; base text is retained.")
                return try inlines(ruby.base, depth: depth + 1, insideLink: insideLink)
            default:
                warn(.flattenedContent, "inline", "Unsupported inline semantics are projected to display text; embedded assets are omitted.")
                try Self.validateText(inline.plainText)
                return [.text(TextRun(inline.plainText))]
            }
        }
    }
    private func textFormatting(_ f: TextFormatting) throws -> TextFormatting {
        var result = TextFormatting(), rest = f
        if richText {
            if let size = f.fontSize { guard size.isFinite && size > 0 && size <= 1638 && (size * 2).rounded() == size * 2 else { throw DocumentError.invalidModel("font size must be a positive half-point value up to 1638") } }
            if let color = f.color { guard color.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { throw DocumentError.invalidModel("color must be six hexadecimal RGB digits") } }
            result.bold = f.bold; result.italic = f.italic; result.strike = f.strike
            result.fontName = f.fontName; result.fontSize = f.fontSize; result.color = f.color
            rest.bold = nil; rest.italic = nil; rest.strike = nil; rest.fontName = nil; rest.fontSize = nil; rest.color = nil
            if let underline = f.underline, ["none", "single", "double"].contains(underline) { result.underline = underline; rest.underline = nil }
        }
        if rest != TextFormatting() { warn(.unsupportedFormatting, "textFormatting", "Text properties outside the target's basic subset are omitted.") }
        return result
    }
    private func paragraphFormatting(_ f: ParagraphFormatting) throws -> ParagraphFormatting {
        var result = ParagraphFormatting(), rest = f
        if richText {
            result.alignment = f.alignment; rest.alignment = nil
            if let level = f.outlineLevel { guard (0...8).contains(level) else { throw DocumentError.invalidModel("outline level must be in 0...8") } }
            result.outlineLevel = f.outlineLevel; rest.outlineLevel = nil
        }
        if rest != ParagraphFormatting() { warn(.unsupportedFormatting, "paragraphFormatting", "Paragraph properties outside the target's basic subset are omitted.") }
        return result
    }
    package static func validateText(_ value: String) throws {
        guard value.unicodeScalars.allSatisfy({ $0.value == 9 || $0.value == 10 || $0.value == 13 || (0x20...0xD7FF).contains($0.value) || (0xE000...0xFFFD).contains($0.value) || (0x10000...0x10FFFF).contains($0.value) }) else { throw DocumentError.invalidModel("text contains an invalid XML character") }
    }
    package static func xml(_ value: String) throws -> String {
        try validateText(value)
        return value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "\r", with: "&#13;").replacingOccurrences(of: "\n", with: "&#10;").replacingOccurrences(of: "\t", with: "&#9;")
    }
}
