# SwiftDocuments

A modern Swift document library built around a **format-neutral value model and one codec per format**, following SwiftSheets.

**In development:** DOCX and DOCM reading is available. API compatibility is not yet guaranteed; there is no tagged release. LibreOffice Writer (ODT) and Apple Pages have a shared-model design and format detection, but no reading codecs yet.

Swift 6.2+, macOS 14+ and iOS 17+. Uses Foundation / FoundationXML and system zlib, with no external Swift package dependencies.

[API reference](https://nanbu.github.io/SwiftDocuments/) · [Cookbook](docs/cookbook.md) · [Reading specification](docs/implementation-spec.md) · [Format design](docs/format-design.md)

```swift
import Foundation
import SwiftDocuments

let document = try Document(contentsOf: URL(filePath: "report.docx"))
print(document.plainText)

for paragraph in document.paragraphs {
    print(paragraph.styleID ?? "", paragraph.plainText)
    for run in paragraph.runs where run.formatting.bold == true {
        print(run.text, run.formatting.fontSize ?? 11)
    }
}
print(document.readWarnings)
```

`paragraphs` includes paragraphs inside nested tables, in document order. `blocks` preserves the sequence of body paragraphs and tables. Headers, footers, footnotes, endnotes and comments live in `stories`; body `plainText` does not include them.

## Install

Until a release is tagged, depend on `main` (pin the resolved revision for reproducible builds):

```swift
// Package.swift
 dependencies: [
    .package(url: "https://github.com/nanbu/SwiftDocuments.git", branch: "main")
 ],
 targets: [
    .target(name: "App", dependencies: [
        .product(name: "SwiftDocuments", package: "SwiftDocuments")
    ])
 ]
```

To link only the Word implementation, use the same model and codec entry points:

```swift
import Foundation
import DocumentCore
import DocumentDOCX

let codecs = CodecSet([.docx, .docm])
let result = try codecs.read(contentsOf: url)
print(result.document.plainText, result.warnings)
```

The models are `Sendable` value types. Reading is synchronous; callers choose the task or thread. Each operation owns its parsing state, so independent documents can be read concurrently.

## Reading APIs

| API | Result |
|---|---|
| `Document(contentsOf:)` / `Document(data:)` | Document with `readWarnings` |
| `Document.read` | `ReadResult`: document and warnings |
| `Document.inspect` | Format, metadata, package inventory and declared expanded size; does not parse the body |
| `Document.scan` | Synchronous throwing callback per body block and `ScanResult`, without retaining body blocks |
| `document.asset(at:)` | Original bytes of an image or opaque part, inflated and CRC-checked on demand |

URL and Data inputs are supported. Detection reads package contents rather than trusting the extension. `CodecSet` exposes the same operations and accepts custom `DocumentCodec` implementations.

```swift
let summary = try Document.inspect(contentsOf: url)
print(summary.expandedBytes, summary.metadata.title ?? "")

let result = try Document.scan(contentsOf: url,
    options: ReadOptions(includeRelatedStories: false)
) { block in
    print(block.plainText) // hand each block to a search index, for example
}
print(result.blocksRead, result.warnings)
```

`scan` releases the XML tree one top-level body block at a time. It still retains the ZIP input, expanded body XML, styles and requested related stories; it is not constant-memory streaming. A single large table is one block. A callback error stops the scan and propagates unchanged. Malformed XML later in the input can fail after earlier callbacks have already run.

## Support

<!-- contract:start -->
| Feature | Read | API / boundary |
|---|---|---|
| Body, paragraphs, runs, tabs and breaks | supported | `blocks`, `paragraphs`, `runs`, `plainText` |
| Bold, italic, size, color, East Asian and complex scripts | supported | `TextFormatting`; theme references retained, unresolved tint / theme details remain raw with warnings |
| Paragraph formatting and style inheritance | supported | `ParagraphFormatting`, `styles`; style toggles distinguished from direct formatting |
| Tables, nesting, merges, widths and borders | supported | `tables`, `rows`, `cells`; borders retained as raw `properties`, conditional table styles unresolved |
| Numbering | supported | `list`, `numbering`; displayed numbering strings are not computed |
| Links and bookmarks | supported | `Inline.hyperlink`, `.bookmark`; external URLs are never fetched |
| Fields | supported | Instructions and cached display values; no evaluation. Cross-paragraph fields represented per paragraph with warnings |
| Images | supported | `Inline.image` references, size and alternative text; assets inflated lazily |
| Sections, headers and footers | supported | `sections`, `stories`; inherited references resolved, no pagination |
| Footnotes, endnotes and comments | supported | `stories`, `.noteReference`, `.commentReference` |
| Revisions | supported | `ReadOptions.revisions`; insertion, deletion, moves and table rows. Paragraph-mark merging and historical formatting not fully reproduced |
| Metadata and DOCM | supported | `metadata`, `packageParts`; VBA retained and warned about, never executed |
| Strict, Transitional and ZIP64 | supported | Main part resolved through relationships; no fixed document path |
| Content controls, math, shapes, charts, OLE and altChunk | raw | Display content / raw XML / original parts and warnings; no behavioral or rendering implementation |
| Legacy DOC and encrypted documents | refused | OLE containers rejected; no exact distinction between legacy DOC and encrypted DOCX |
| ODT and Pages reading | planned | Format detection only; reading codecs not provided |
| Writing, conversion and layout | planned | Outside the current API |
<!-- contract:end -->

`supported` means the stated API and boundary, not every element of ECMA-376. Unknown content and uninterpreted formatting produce warnings; original package parts remain accessible. Warnings are aggregated by code / part / element with an occurrence `count`. Raw XML is a namespace-preserving reconstruction, not a byte-identical copy.

## Limits and verification

Default `ReadOptions.limits`: 10,000 parts, 512 MiB total expanded bytes, 128 MiB per part, XML depth 128 and 2,000,000 XML nodes. Limit violations, malformed packages and missing relationship targets throw. DTD / entity declarations are rejected and external resources are not loaded. CRC is checked only for inflated parts; `inspect` does not verify body or image CRCs. Model and style memory can exceed XML size: these limits are not a process memory budget.

macOS tests and release builds have been verified, including independent python-docx expectations and documents resaved by LibreOffice 26.2.3.2. CI runs the same suite on macOS and Linux. iOS execution has not been verified yet.

```sh
swift test
swift build -c release
python3 scripts/check-contract.py
python3 scripts/check-public-content.py
swift run swiftdoc text sample.docx
swift run swiftdoc inspect sample.docx
```

See [performance and reproduction](docs/performance.md), [contributing](CONTRIBUTING.md) and [security](SECURITY.md). MIT License.
