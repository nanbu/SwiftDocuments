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
    case .unsupported(let content): print(content.name, content.sourcePart)
    }
}
```

`document.paragraphs` and `document.tables` include nested tables. Use `blocks` to follow the body sequence directly.

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

`.final` excludes deleted text; `.original` excludes inserted text. These views do not merge paragraphs after paragraph-mark deletion or reconstruct historical formatting.

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

## CLI

```sh
swift run swiftdoc text sample.docx
swift run swiftdoc inspect sample.docx
swift run -c release swiftdoc scan sample.docx
```

`text` sends body text to stdout and warnings to stderr. `inspect` returns JSON. `scan` / `read` count blocks and characters for benchmarking, explicitly omitting related stories.
