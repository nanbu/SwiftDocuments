# SwiftDocuments

A modern Swift document library built around a **format-neutral value model and one codec per format**, following SwiftSheets.

**Version 1.1:** DOCX/DOCM reading, partial ODT/modern Pages reading, UTF-8 Markdown subset reading, and basic DOCX/DOCM/ODT/Pages writing. The documented public API follows semantic versioning. See the support boundaries below; Pages producer verification covers the fictional import/save fixture described below.

Swift 6.2+, macOS 14+ and iOS 17+. Uses Foundation / FoundationXML and system zlib, with no external Swift package dependencies.

[API reference](https://nanbu.github.io/SwiftDocuments/) · [API inventory](docs/api-reference.md) · [Executable example](Examples/ReadDocument) · [Cookbook](docs/cookbook.md) · [Reading and writing specification](docs/implementation-spec.md) · [Format design](docs/format-design.md)

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

Add the versioned package with Swift Package Manager:

```swift
// Package.swift
 dependencies: [
    .package(url: "https://github.com/nanbu/SwiftDocuments.git", from: "1.1.0")
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

Link `DocumentODT` with `DocumentCore` and select `CodecSet([.odt])`, or link `DocumentPages` with `DocumentCore` and select `CodecSet([.pages])`. Link `DocumentMarkdown` with `DocumentCore` and select `CodecSet([.markdown])` for Markdown. The umbrella re-exports Core and all four codec modules and registers five formats.

The models are `Sendable` value types. Synchronous methods remain available; async read / inspect / asset methods run on the generic executor so callers can await them from MainActor. Each operation owns its parsing state. Cancellation is cooperative; file I/O itself remains synchronous.

## Reading APIs

| API | Result |
|---|---|
| `Document(contentsOf:)` / `Document(data:)` | Document with `readWarnings` |
| `Document.read` | `ReadResult`: document and warnings |
| `Document.inspect` | Format, metadata, package inventory and declared expanded size; does not parse the body |
| `Document.scan` | Synchronous throwing callback per body block and `ScanResult`; returned document omits body blocks |
| `Document.readAll(contentsOf:options:maxConcurrentReads:)` | Async batch, results in input order, with bounded concurrent reads |
| `document.asset(at:)` | Original bytes of an image or opaque part, inflated and CRC-checked on demand |
| `document.readSourceXML(at:)` | Original XML names, namespace scopes, attributes and ordered mixed content; parsed on demand with the original limits |

URL and Data inputs are supported. Package detection reads contents rather than trusting the extension. Plain-text Markdown Data requires explicit `format: .markdown`; URL inputs use `.md` / `.markdown` when no ZIP/OLE signature is present. All Data and URL initializers and read / inspect / scan entry points accept an optional `format` override; the selected codec still validates the contents. `DocumentFormat(fileExtension:)` recognizes standard extensions for explicit selection without changing detection.

`CodecSet` exposes the same operations and accepts custom `DocumentCodec` implementations. `formats`, `contains(_:)`, `codec(for:)` and `Codec.format` expose registration. Formats keep first registration order; re-registration replaces the implementation with the last choice. Missing codecs throw `DocumentError.noCodec`.

When importing other document libraries, qualify shared names, for example `DocumentCore.CodecSet` and `DocumentCore.ReadOptions`. The internal zlib module has a package-specific name to avoid target conflicts with other libraries.

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

Word `scan` releases the XML tree one top-level body block at a time. ODT retains the content XML tree; Pages retains the decoded IWA graph. It still retains the ZIP input, expanded body XML, styles and requested related stories; it is not constant-memory streaming. A single large table or block content control is one block. A callback error stops the scan and propagates unchanged. Malformed XML later in the input can fail after earlier callbacks have already run.

```swift
// In an async function, including on MainActor:
let result = try await Document.read(contentsOf: url)
let batch = try await Document.readAll(contentsOf: urls, maxConcurrentReads: 4)
print(result.warnings, batch.map { $0.document.plainText })
```

In an async context Swift selects the async overload, so existing calls may need `await`. Scan stays synchronous and accepts caller-owned callback state. A batch failure cancels and awaits remaining children before throwing, without returning partial results. The concurrent-read limit must be positive and applies to active documents, not the memory of the full result. Cancellation may stop a scan after earlier callbacks; consumer errors retain precedence.

## Markdown and basic writing

```swift
let markdown = try Document.read(Data("# Notes\n\n**Hello** 日本語".utf8), format: .markdown)
let saved = try markdown.document.write(to: URL(filePath: "notes.docx"))
print(saved.warnings)

var draft = Document()
var paragraph = Paragraph()
paragraph.inlines = [.text(TextRun("A new document"))]
draft.blocks = [.paragraph(paragraph)]
let bytes = try draft.write(as: .odt, options: WriteOptions(strict: true))
```

`write(as:options:)` returns generated bytes and aggregated `WriteWarning`s.
`write(to:as:options:)` serializes and validates the complete model before an
atomic local save. An explicit format wins; otherwise a recognized output
extension wins, followed by the source format, then DOCX for a new document.
Sync and async overloads are available. Custom reading-only codecs continue to
compile and throw `writingNotSupported` for writes by default.

DOCX/DOCM and ODT writing covers paragraphs, basic text formatting, outline
levels/alignment, simple lists, external links, unmerged tables and basic
metadata. Pages writing covers body text, paragraphs, Unicode, tabs and line/page
breaks using a sanitized blank producer template. It projects tables/links and
formatting to text with warnings. Basic writing regenerates packages; it does
not preserve source assets, VBA, signatures, unknown XML, stories, revisions or
advanced layout. `strict: true` refuses any diagnosed writing loss before saving.
Imported package parts also produce an explicit regeneration warning. A bounded iterative preflight rejects body graphs beyond 32 structural levels or 2,000,000 visited nodes before recursive serialization. Reading
warnings remain on the source document and are diagnosed by writing separately.

Markdown is a documented subset, not a CommonMark/GFM conformance claim. Images,
HTML, reference links, tables, quotes and complex lists remain literal text with
warnings. Markdown export is deferred; `write(as: .markdown)` throws
`writingNotSupported`. See the [specification](docs/implementation-spec.md) for
per-format limitations, including ODT break/list fallback and required Word cell
terminators.

```sh
swift run swiftdoc convert notes.md notes.docx
swift run swiftdoc convert notes.md notes.odt
swift run swiftdoc convert notes.md notes.pages
```

## Support

<!-- contract:start -->
| Feature | Read | API / boundary |
|---|---|---|
| Codec selection and content detection | supported | Ordered `formats`, `contains`, `codec(for:)`; consistent Data/URL format overrides, content detection by default |
| Async and bounded batch reading | supported | read / inspect / asset async overloads; ordered `readAll`, cooperative cancellation; scan remains synchronous |
| Body, paragraphs, runs, tabs and breaks | supported | `blocks`, `paragraphs`, `runs`, `plainText` |
| Bold, italic, size, color, East Asian and complex scripts | supported | `TextFormatting`; theme colors, HSL tint/shade and major/minor script fonts resolved; source references retained |
| Paragraph formatting and style inheritance | supported | `ParagraphFormatting`, `styles`, empty-paragraph defaults and separate paragraph-mark typography; style toggles distinguished from direct formatting |
| Tables, nesting, merges, widths and borders | partial | `tables`, `rows`, `cells`; typed borders, padding, placement and row exceptions; conditional cell styles resolved, no border conflict/layout computation |
| Numbering | supported | `list`, `numbering`; displayed numbering strings are not computed |
| Links and bookmarks | supported | `Inline.hyperlink`, `.bookmark`; external URLs are never fetched |
| Fields | partial | Stable definitions and fragments across paragraphs, tables and controls; separate instruction/cached content, no evaluation; form-field behavior remains raw |
| Images | supported | `Inline.image` references, size and alternative text; assets inflated lazily |
| Sections, headers and footers | supported | `sections`, `stories`; inherited references resolved, no pagination |
| Footnotes, endnotes and comments | supported | `stories`, `.noteReference`, `.commentReference` |
| Revisions | partial | Text/drawing/image move and edit attribution, row/cell insertions and deletions, simple paragraph-mark joins, former text/paragraph/table/row/cell/column properties and recorded cell merge states; other historical structures remain raw and warned |
| Metadata and DOCM | supported | `metadata`, `packageParts`; VBA retained and warned about, never executed |
| Strict, Transitional and ZIP64 | supported | Main part resolved through relationships; no fixed document path |
| Japanese typography and source fonts | supported | Ruby, script fonts/themes, line-breaking and vertical-text settings; original symbol codes retained, no font substitution |
| DrawingML canvases, groups, shapes and SVG assets | partial | Hierarchical scenes, connector endpoints, canvas backgrounds/outlines, anchors, geometry and lazy SVG/fallback bytes; advanced paint/layout and VML details retain raw data and warnings |
| Office Math structure | supported | Typed OMML arguments and properties, source subtree and lexical text; no computation or typesetting |
| Chart data and source structure | partial | Groups, series, sparse cached values, formulas, categories and axes; advanced appearance remains source XML, workbooks are not evaluated |
| On-demand original XML and warning coverage | supported | `readSourceXML(at:)`, root/container extensions, recognized-property extensions, row/cell properties and unequal columns; read/scan warning parity |
| Content controls | partial | Typed block/inline wrappers, metadata, cached content and table ranges; bindings and interactive behavior are not executed |
| SmartArt, ink, OLE and altChunk | raw | Display content / raw XML / original parts and warnings; no behavioral or rendering implementation |
| Legacy DOC and encrypted documents | refused | OLE containers rejected; no exact distinction between legacy DOC and encrypted DOCX |
| ODT and Pages reading | partial | `DocumentODT` / `DocumentPages`, `.odt` / `.pages`; ODF text/styles/table geometry/covered cells/ruby/images/stories; IWA text/styles/languages/tabs/header-footer, anchored tables and lazy inline images; complex Pages layout remains opaque |
| Markdown reading | partial | `DocumentMarkdown`, `.markdown`; headings, paragraphs, strong/emphasis, inline links/code, simple lists and fenced code; unsupported constructs remain literal source with warnings |
| Basic writing and conversion | partial | `document.write`, `CodecSet.write`, `WriteResult`, strict loss checks; DOCX/DOCM/ODT basic text, formatting, lists and tables; Pages body text only; original assets, macros and advanced semantics are omitted with warnings |
| Markdown writing and layout | planned | Markdown export, pagination and rendering are outside the current API |
<!-- contract:end -->

`partial` identifies a typed projection with additional uninterpreted semantics. `supported` means the stated API and boundary, not every element of ECMA-376. Unknown content and uninterpreted formatting produce warnings; original package parts remain accessible. Warnings are aggregated by code / part / element with an occurrence `count`. Raw XML is a namespace-preserving reconstruction, not a byte-identical copy.

The reader preserves legacy Symbol/Wingdings values and source numbering fonts. Installed-font lookup, glyph substitution, list-label generation and layout belong to a separate viewer/rendering library. The independent [symbol fallback reference](docs/reference/symbol-font-fallback/README.md) records reusable tables and policy without becoming a package dependency.

## Limits and verification

Default `ReadOptions.limits`: 10,000 parts, 512 MiB total expanded bytes, 128 MiB per part, XML depth 128 and 2,000,000 XML nodes. Limit violations, malformed packages and missing relationship targets throw. DTD / entity declarations are rejected and external resources are not loaded. CRC is checked only for inflated parts. Word/ODT inspection skips body and image CRCs; Pages inspection inflates Index/Document.iwa to validate its root, without decoding all storage objects. Model and style memory can exceed XML size: these limits are not a process memory budget.

macOS tests and release builds have been verified, including independent python-docx expectations and DOCX/ODT documents resaved by LibreOffice 26.2.3.2. Pages Creator Studio 15.4 imported and saved a fictional DOCX containing Japanese, emoji, a table and an image; the resulting Pages fixture is verified alongside synthetic wire/schema tests. This evidence covers that import/save path, not every Pages feature. CI runs the same suite on macOS and Linux. The library also compiles for iOS 17 with Swift 6.4; iOS device/simulator execution has not been verified yet.

```sh
swift test
swift build -c release
python3 scripts/check-contract.py
python3 scripts/check-public-content.py
swift run swiftdoc text sample.docx
swift run swiftdoc inspect sample.docx
python3 scripts/verify-basic-writing.py --soffice /path/to/soffice
```

See [performance and reproduction](docs/performance.md), [contributing](CONTRIBUTING.md) and [security](SECURITY.md). MIT License.
