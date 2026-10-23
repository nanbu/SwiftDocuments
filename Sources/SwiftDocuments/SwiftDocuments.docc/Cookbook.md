# Cookbook

Examples assume `import Foundation`, `import SwiftDocuments` and a document URL named `url`.

## Read paragraphs and tables in order

```swift
let document = try Document(contentsOf: url)
for block in document.blocks {
    switch block {
    case .paragraph(let paragraph): print(paragraph.plainText)
    case .table(let table):
        for row in table.rows { print(row.cells.map(\.plainText)) }
    case .contentControl(let control): print(control.descriptor.title ?? "", control.plainText)
    case .unsupported(let content): print(content.name, content.sourcePart)
    }
}
```

`document.paragraphs` and `document.tables` include nested tables. Use `blocks` to follow the body sequence directly.

Table and cell `preferredWidth` distinguishes points from whole percentage points: `value == 50` with `unit == .percent` means 50%, independently of the source encoding. `sourceValue` and `sourceUnit` retain the original strings, including a percent suffix or fiftieths-of-a-percent encoding. Automatic, none and unknown units have distinct cases. Use this normalized API when laying out a table; physical widths are preferred widths, not computed layout results.

## Read a default-page header

```swift
if let section = document.sections.first,
   let path = section.headers["default"],
   let story = document.stories.first(where: { $0.id == path && $0.kind == .header }) {
    print(story.plainText)
}
```

Header / footer keys are `default`, `first` and `even`. Some producers create several empty stories; do not infer the intended header from array order. `hasDifferentFirstPage` and the raw `evenAndOddHeaders` setting provide additional context.

## Resolve a footnote reference

```swift
for paragraph in document.paragraphs {
    for inline in paragraph.inlines {
        if case .noteReference(let reference) = inline,
           let note = document.stories.first(where: {
               $0.kind == reference.kind && $0.id == reference.id
           }) {
            print(note.plainText)
        }
    }
}
```

Separator / continuation-separator stories have a distinct `type`. Ordinary footnotes have `type == nil`; negative IDs are not ordinary body footnotes.

## Extract image bytes

```swift
for paragraph in document.paragraphs {
    for inline in paragraph.inlines {
        if case .image(let image) = inline, let path = image.assetPath {
            let bytes = try document.asset(at: path)
            print(image.alternativeText ?? "", image.width ?? 0, bytes.count)
        }
    }
}
```

External images have `externalURL` instead of `assetPath`; the library never fetches them. Recurse through hyperlink `inlines` and field `result` to find images inside those containers.

## Inspect content controls without executing them

```swift
for block in document.blocks {
    if case .contentControl(let control) = block {
        print(control.descriptor.kind, control.descriptor.title ?? "")
        print(control.descriptor.binding?.pathQuery ?? "")
        print(control.plainText) // Cached source content, never regenerated.
    }
}
for table in document.tables {
    for range in table.rowControls {
        print(range.range, range.descriptor.id ?? "")
    }
}
```

Inline controls appear as `Inline.contentControl`; `paragraph.runs` includes their text. Table row/cell controls use descriptors and ranges over physical row/cell arrays, keeping one authoritative grid. Checkbox symbols retain their source fonts and codes. Bindings, placeholders, date formatting and interactive behavior are not executed. The normalized source header omits cached body content; original complete bytes remain available through `asset(at:)`.

## Retain revisions

```swift
let result = try Document.read(contentsOf: url, options: ReadOptions(revisions: .all))
for paragraph in result.document.paragraphs {
    for run in paragraph.runs {
        print(run.revision?.kind.rawValue ?? "unchanged", run.text)
    }
}
print(result.warnings)
```

`.final` excludes deleted text and joins paragraphs separated by a deleted mark; `.original` excludes inserted text and joins across inserted marks. Former run/paragraph properties follow the view. `formattingChange` retains the former properties and attribution. Other historical property structures remain recoverable with warnings.

Drawings and pictures follow the same visibility rules. `DocumentDrawing.revision` and `DocumentImage.revision` retain the enclosing insertion, deletion or move metadata, including in `.all` view. A picture's `drawing?.revision` carries the same attribution. Text inside shapes has its own revision metadata. Reading does not accept/reject changes or write documents.

## Keep source symbols and fonts unchanged

```swift
for paragraph in document.paragraphs {
    for run in paragraph.runs {
        if let symbol = run.symbol {
            print(symbol.fontName, symbol.characterCode, run.text)
        }
    }
}
for definition in document.numbering.values {
    for level in definition.levels.values {
        print(level.text, level.formatting.fontName ?? "")
    }
}
```

Character codes are the source values. A missing Office font does not change them or produce a parsing warning. A separate viewer owns fallback, counter evaluation and shaping. The standalone symbol-font reference records mapping tables, a CoreText example and an HTML explanation without adding a runtime dependency.

## Inspect drawings, equations and chart caches

```swift
func inspect(_ node: DrawingNode) {
    print(node.kind, node.transform.bounds, node.geometry?.preset ?? "custom")
    if let start = node.startConnection { print("start", start.targetID, start.siteIndex) }
    if let end = node.endConnection { print("end", end.targetID, end.siteIndex) }
    if node.kind == .canvas { print("outline", node.line?.width as Any, node.line?.fill?.color?.value as Any) }
    if let chart = node.chart {
        for group in chart.groups {
            for series in group.series {
                print(series.values?.formula ?? "")
                for point in series.values?.points ?? [] {
                    print(point.index, point.text, point.number as Any)
                }
            }
        }
    }
    for child in node.children { inspect(child) }
}
for paragraph in document.paragraphs {
    for inline in paragraph.inlines {
        switch inline {
        case .drawing(let drawing): inspect(drawing.root)
        case .image(let image):
            print(image.assetPath ?? "", image.fallbackAssetPath ?? "")
        case .equation(let equation):
            print(equation.root.kind, equation.lexicalText)
        case .ruby(let ruby):
            print(ruby.base.map(\.plainText).joined(), ruby.annotation.map(\.plainText).joined())
        default: break
        }
    }
}
```

Drawing coordinates use points and preserve nested group coordinate systems. Preferred SVG and fallback references remain separate; assets are never executed. Chart points keep sparse source indices and lexical values, and formulas are not evaluated. Equation lexical text joins tokens without inventing a linear mathematical notation. Chart appearance, unknown drawing properties and other uninterpreted semantics remain available with warnings.

## Read an original XML part on demand

```swift
if let path = document.packageParts.first(where: { $0.path.hasSuffix(".xml") })?.path {
    let result = try document.readSourceXML(at: path)
    print(result.root.qualifiedName, result.root.namespaceBindings)
    print(result.root.attributes, result.root.content)
    let originalBytes = try document.asset(at: path)
    print(originalBytes.count)
}
```

The source tree preserves original QNames, namespace scopes and ordered mixed content. It uses the original parsing limits, validates CRC and refuses DTD/entities. `asset(at:)` returns exact stored part bytes after decompression. Equation source subtrees are normalized projections; read the original part when original prefixes or byte formatting matter.

## Inspect empty-paragraph and paragraph-mark typography

```swift
for paragraph in document.paragraphs {
    let defaults = paragraph.defaultTextFormatting
    let mark = paragraph.paragraphMarkFormatting ?? defaults
    print(defaults.fontNameEastAsia ?? "", mark.fontSize as Any)
    if let change = paragraph.paragraphMarkFormattingChange {
        print(change.revision.author ?? "", change.previous.fontSize as Any)
    }
}
```

The mark is the paragraph-ending character. Its separate typography can matter to
a viewer even when the paragraph or table cell has no text runs. It does not
change the formatting of the paragraph's existing text or add a pilcrow to
`plainText`. The reader retains source font names without selecting installed fonts.

## Inspect table property history

```swift
for table in document.tables {
    print(table.columns.map(\.width)) // missing source widths remain nil
    if let change = table.formattingChange {
        print(change.revision.id, change.previous.preferredWidth as Any)
    }
    for row in table.rows {
        for cell in row.cells {
            print(cell.revisions.map(\.kind), cell.formattingChange?.previous.columnSpan as Any)
            if let change = cell.mergeChange {
                print(change.wasMergedWithPrevious, change.isMergedWithPrevious)
            }
        }
    }
}
```

Original view selects recorded former text, paragraph, table, row, cell and column
properties. Histories retain attribution and source records without copying cell
content. A tracked split means that the cell is no longer merged with the previous
row; it does not invent a new merge start or extra physical cells.

## Use smaller parsing limits

```swift
let limits = PackageLimits(
    maxEntries: 2_000,
    maxExpandedBytes: 64 << 20,
    maxPartBytes: 16 << 20,
    maxXMLDepth: 64,
    maxXMLNodes: 200_000
)
let result = try Document.read(contentsOf: url, options: ReadOptions(limits: limits))
```

Violations throw `DocumentError.limitExceeded` rather than returning truncated success. `inspect` sizes come from ZIP declarations; inflation validates actual length and CRC.

## Await a document or read a batch

```swift
// Inside an async function, including on MainActor:
let result = try await Document.read(contentsOf: url)
print(result.document.plainText, result.warnings)

let results = try await Document.readAll(
    contentsOf: [url, anotherURL],
    options: ReadOptions(includeRelatedStories: false),
    maxConcurrentReads: 2
)
for result in results { print(result.document.sourceFormat, result.warnings) }
```

Results keep input order. A failure cancels and awaits remaining children before throwing. `maxConcurrentReads` must be positive; it bounds active document reads, not total result memory. Read / inspect / asset have async overloads; in an async context, existing calls may need `await`. Scan remains synchronous and can keep local callback state.

## Choose and query codecs

```swift
let codecs = CodecSet([.docx, .docm])
print(codecs.formats) // [.docx, .docm], in registration order
if codecs.contains(.docx) {
    let selected = try codecs.codec(for: .docx)
    let wordOnly = CodecSet([selected])
    let summary = try wordOnly.inspect(bytes, format: .docx)
    print(summary.metadata.title ?? "")
}
```

Explicit format selection still validates package contents. Omit `format` to detect them. Re-registering a format replaces its implementation without changing its position. A missing codec throws `noCodec` rather than becoming an unknown format or an empty document.

## CLI

```sh
swift run swiftdoc text sample.docx
swift run swiftdoc inspect sample.docx
swift run -c release swiftdoc scan sample.docx
```

`text` sends body text to stdout and warnings to stderr. `inspect` returns JSON. `scan` / `read` count blocks and characters for benchmarking, explicitly omitting related stories.

## Follow fields across paragraphs

```swift
let definitions = Dictionary(uniqueKeysWithValues: document.fieldDefinitions.map { ($0.id, $0) })
func inspectFields(_ inlines: [Inline]) {
    for inline in inlines {
        switch inline {
        case .field(let field):
            if let fragment = field.fragment, let definition = definitions[fragment.definitionID] {
                print(definition.instruction, definition.parentID ?? "", definition.isComplete)
                print(fragment.startsHere, fragment.endsHere, fragment.containsSeparator)
            }
            inspectFields(field.codeContent)
            inspectFields(field.result)
        case .hyperlink(let link): inspectFields(link.inlines)
        case .contentControl(let control):
            if case .inlines(let values) = control.content { inspectFields(values) }
        case .ruby(let ruby): inspectFields(ruby.base); inspectFields(ruby.annotation)
        default: break
        }
    }
}
for paragraph in document.paragraphs { inspectFields(paragraph.inlines) }
```

`Field.instruction` contains instruction text local to that fragment. The complete
instruction, source state and parent identity live in `fieldDefinitions`. A
fragment's `result` contains only its cached display; `codeContent` also retains
nested instruction fields. Neither instructions nor instruction-side nested
results contribute to body `plainText`. No instruction is evaluated.

In `scan`, collect or consume fragment IDs as blocks arrive, then use the returned
`document.fieldDefinitions` for complete metadata. Emitted blocks never change
when later paragraphs finish a field. IDs are local to one operation, not durable
identifiers across document edits. Keep container boundaries and paragraph/cell
separators when assembling a cached display. Headers, individual notes and text
boxes have separate field scopes; omitted related stories contribute no fields.
Unclosed source fields have `isComplete == false` and warnings, while their cached
text remains accessible. Form-field execution remains unsupported and diagnosed.

## Read table appearance without computing layout

```swift
for table in document.tables {
    print(table.alignment as Any, table.layout as Any)
    print(table.borders[.top]?.width as Any) // points for a line border
    for row in table.rows {
        print(row.omittedLeadingColumns, row.omittedTrailingColumns, row.tableOverrides as Any)
        for cell in row.cells {
            if cell.isCovered { continue } // retained ODF source cell, not another display cell
            print(cell.columnSpan, cell.rowSpan, cell.borders[.left]?.style as Any)
            let padding = cell.margins[.left] ?? table.cellMargins[.left]
            print(padding?.value as Any, padding?.unit as Any)
        }
    }
}
```

Logical start/end and physical left/right edges are separate declarations. Resolve writing direction before choosing an edge for display. Explicit `none`/`nil` borders override inherited style declarations; the reader does not compute conflicts between neighboring borders. Table defaults, conditional cell styles and row table exceptions remain distinguishable. Revision snapshots retain previous borders and margins as well as widths. Covered ODF cells retain their own blocks for source inspection, but their text is excluded from ordinary table text and document paragraph traversal.
