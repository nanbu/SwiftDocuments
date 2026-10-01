# Reading specification

## Goal and completion boundary

Apply SwiftSheets' design principles to documents: Swift 6.2+, `Sendable` value types and no external Swift package dependencies. The current milestone implements the Word reading contract below and verifies valid / malformed packages, producer-generated files and large synthetic documents. It is not a word processor or an implementation of every ECMA-376 rendering rule. The README support table and warnings define the boundary.

## Modules and extension points

`DocumentCore` owns the format-neutral document, block, paragraph, inline, table, style, numbering, story, section and metadata models; `DocumentCodec` / `CodecSet`; and shared ZIP / XML infrastructure. `DocumentDOCX` implements DOCX / DOCM. `SwiftDocuments` re-exports both and adds convenience entry points. Linking only Core and selected codecs uses the same model.

A future `DocumentODT` will project ODF content.xml / styles.xml onto the model. A future `DocumentPages` will interpret IWA object graphs. Pages layout canvases must not be forced into Word's page semantics. Positioned and unknown content retains source parts and raw representations. Writing, conversion, layout and encryption are outside this milestone.

Pages detection inspects the first TSP.ArchiveInfo in Index/Document.iwa for object 1, type 10000 (TP.DocumentArchive). Shared iWork ZIP filenames alone do not identify Pages. Legacy iWork, Index.zip and folder packages are not supported.

## Entry points

- `Document.read(_:)` / `Document.read(contentsOf:)` return `ReadResult`; convenience initializers retain warnings in `readWarnings`.
- `CodecSet([.docx, .docm])` exposes read / inspect / scan with selected codecs.
- `scan` synchronously delivers top-level main-story blocks in order to a throwing callback. Callback errors propagate unchanged. It retains at most one body-block XML tree, but also the ZIP input, expanded XML, styles and requested related stories. It is not a constant-memory ZIP / XML stream. The returned document has no body blocks, and `blocksRead` counts delivered blocks. Earlier callbacks may have run when later malformed XML causes failure.
- `inspect` returns format, metadata, package inventory and declared expanded size without parsing body blocks or validating body / image CRCs.

## Formats and containers

Identify content through MIME, content types and root relationships; do not trust filename extensions or assume a fixed main-part path. Read DOCX / DOCM, Strict / Transitional WordprocessingML and stored / deflate / ZIP64 packages. Detect ODT / modern Pages and report missing codecs. Refuse OLE legacy DOC and encrypted OOXML containers without claiming an exact distinction.

Check CRCs on inflation, declared lengths, duplicate names, local headers, overlapping entry ranges, unsafe paths and multi-disk ZIPs. Defaults are 10,000 parts, 512 MiB expanded total, 128 MiB per part, depth 128 and 2,000,000 XML nodes. Violations throw. Reject DTD / entity declarations, including UTF-16 / UTF-32 inputs. External relationships remain URLs and are never fetched. Normalize internal relationship paths within the OPC package; traversal, missing targets and duplicate IDs throw.

## Word contract

Read body order, paragraphs, formatted runs, tabs, breaks and tables (nested tables, gridSpan, vMerge, widths, borders and cell properties). Frequent run / paragraph properties have typed fields; raw XML supplements uninterpreted properties. Resolve style inheritance and Word style toggles. Preserve numbering abstract definitions, instances and level overrides; paragraphs carry numbering IDs / levels, without computed display numbers.

Preserve section size, margins, columns and inherited header / footer references, without pagination or automatic wrapping. Read links, bookmarks, simple / complex field instructions and cached results, note references, comment ranges and comment bodies. Images carry asset references, alternative text, EMU-to-point sizes and inline / floating placement; assets inflate and validate CRC on demand. DOCM VBA is never executed; it remains an opaque part in the inventory with a warning.

Revision views are `.final` (default), `.original` and `.all`. In `.all`, runs carry revision ID, kind, author and date. Inserted / deleted table rows follow the view. Paragraph-mark merging and historical formatting remain incomplete with raw representations and warnings. Missing note / comment references warn with `invalidReference`; reference checks are omitted when related stories are omitted.

Read display content inside content-control / custom-XML wrappers, but warn about controls and bindings. Text boxes, equations, OLE, altChunk, shapes, charts and unknown semantic elements use raw XML and warnings. Aggregate warnings by code / part / element with an occurrence count so repeated unsupported content does not grow the warning array indefinitely. Raw XML preserves meaning and namespaces, not original bytes or namespace prefixes.

## Formatting and semantic boundaries

Resolve defaults → paragraph basedOn chain → paragraph direct formatting → character style → run direct formatting. Style booleans are toggles; direct formatting provides explicit values. Style chains are limited to 128 links and cycles are rejected. Conditional table styles and full theme / tint resolution are unsupported and warned about. Retain font / color theme references and uninterpreted formatting with `uninterpretedFormatting`.

Tables retain physical cells with separate `columnSpan` / `verticalMerge`; they do not fabricate virtual merged cells. Body `plainText` separates paragraphs with newlines, cells with tabs and rows with newlines. Related stories remain separate. Fields return cached text without evaluating instructions. Hidden text remains in the model.

## Sources and verification

- [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/), Parts 1–4.
- [Microsoft: WordprocessingML structure](https://learn.microsoft.com/en-us/office/open-xml/word/structure-of-a-wordprocessingml-document).
- Hand-built synthetic fixtures target specification boundaries. Independent python-docx and LibreOffice producer fixtures verify interoperability; provenance is recorded beside them.
- `swift test`, release builds and support / public-content checks run in CI on macOS and Linux.
- Benchmark both time and memory; untested environments are not called verified.

## Publication and documentation

Only reusable implementation, tests, synthetic fixtures, English documentation and canonical marketing content belong in this repository. Never publish private development reports, raw work logs, local paths, customer documents or credentials. A public-content detector checks tracked files, fixture metadata and public text; its self-tests and commands are recorded in verification.md.

The API reference is built with DocC from public compiler symbol graphs. All three library modules and the umbrella's convenience extensions are included. CI publishes only the generated documentation artifact to GitHub Pages. Build outputs and symbol graph source paths are not committed.
