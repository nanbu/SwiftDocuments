# Reading documents

Choose a full model, a package inspection or a per-block scan.

## Full model

``Document`` convenience initializers return the document and retain warnings in `readWarnings`. `Document.read(contentsOf:format:options:)` returns ``ReadResult``. Body blocks preserve paragraph / table order, while `paragraphs` and `tables` recursively flatten nested tables. Headers, footers, notes and comments remain separate ``Story`` values.

The umbrella and ``CodecSet`` accept the same optional `format` override for Data and URL read / inspect / scan. Omit it to detect package contents. Explicit selection still validates DOCX / DOCM MIME. URL inputs use content detection when the format is omitted. `CodecSet.formats` keeps first registration order; re-registration replaces the implementation with the last choice. `contains(_:)`, `codec(for:)` and `Codec.format` expose the selection, including custom codecs.

## Inspection

`Document.inspect(contentsOf:format:limits:)` returns ``DocumentSummary`` without parsing the body. Expanded sizes are ZIP declarations. Metadata and necessary package infrastructure are inflated and checked; Word/ODT body and image CRCs are not checked by inspection. Pages inspection inflates its root IWA part for identification, but does not interpret all body objects.

## Async reading and batches

Read / inspect / asset have same-named async overloads running on the generic executor, including from MainActor. The synchronous codec protocol, methods and initializers remain available. In an async context existing calls may need `await`. File I/O remains synchronous; this API does not promise a speed improvement or asynchronous disk I/O.

`Document.readAll(contentsOf:options:maxConcurrentReads:)` and the identical ``CodecSet`` operation preserve input order and duplicate URLs, with a default of four concurrent reads. A nonpositive limit throws `DocumentError.invalidOptions`, even for empty input. A failure cancels and awaits remaining children and returns no partial batch. Each document has its own parsing limits; the concurrency limit is not a total-result or process-memory budget.

Cancellation is checked around dispatch, file reads, ZIP entries, inflation / CRC chunks, XML callbacks and model processing. `CancellationError` propagates unchanged. Scan remains synchronous to support caller-owned callback state; it may stop after earlier callbacks have run, and a consumer error takes precedence over cancellation triggered by that callback. File I/O, stored-part copies, raw XML reconstruction and third-party codecs without cancellation checks cannot be forcibly interrupted.

## Per-block scan

``Document/scan(contentsOf:format:options:onBlock:)`` calls the synchronous throwing callback once per top-level body block in order. The result retains styles, sections, metadata, warnings and requested related stories, but no body blocks. A callback error propagates unchanged. A later XML error can be thrown after earlier callbacks have already run, so callers must handle partial effects.

Word scanning releases each body-block XML tree; ODT retains the content XML tree and Pages retains the decoded object graph. All formats retain ZIP input; it is not constant-memory streaming. A large table remains one block. Set `includeRelatedStories` to false when those bodies are unnecessary; the result reports `storiesOmitted` when appropriate.

## Warnings, limits and assets

``ReadWarning`` aggregates occurrences by code / part / element. ``PackageLimits`` bounds package sizes and parser work, not total process memory. Malformed packages, missing relationship targets and exceeded limits throw ``DocumentError``. DTD / entity declarations are refused; external URLs are never fetched and VBA is never executed.

Images store references and placement; `Document.asset(at:)` inflates the requested package part and validates its CRC. Opaque parts can be accessed the same way. Raw XML preserves semantics and namespaces, not byte-for-byte formatting.

Missing paragraph / character styles report `invalidReference` at the referring part and element, while preserving IDs, text and available formatting. Missing inheritance targets report the `basedOn` declaration in the styles part. Style cycles and excessive inheritance depth still throw.

## Units and formatting

The reader preserves original symbol character codes, font-table charsets, script-specific fonts/themes, ruby and Japanese paragraph settings. It does not inspect installed fonts, substitute symbols or generate list labels. Separate viewers own those display policies; standalone fallback reference material is retained outside package targets.

``DocumentDrawing`` exposes nested canvases, groups, shapes, placements and image choices. ``Equation`` retains typed argument structure and a normalized source subtree; its lexical text does not invent a linear mathematical notation. ``Chart`` retains groups, series, sparse cached values, formulas and axes, with complete source properties. No equation typesetting, workbook recalculation or chart rendering is implied. Unknown semantics remain recoverable with warnings.

Drawings and images retain enclosing insertion/deletion/move attribution in `revision` and follow the selected revision view. Connector nodes expose `startConnection` / `endConnection` source object IDs and site indices. Canvas nodes expose background `fill` and whole-object `line` formatting. Unprojected effects remain raw with warnings; connection routing and document editing are outside the reader.

`Document.readSourceXML(at:)` reads an original XML part on demand with its original QNames and mixed content, using the document's limits. It also has an async overload. Exact part bytes remain available through `asset(at:)`; reconstructed raw XML and equation snapshots need not preserve prefixes or byte formatting.

Measurements use points, including universal mm/cm/in/pt/pc/pi values. A multiple line spacing is expressed as a ratio; exact / at-least spacing is in points. Table and cell `preferredWidth` uses ``TableWidth`` to distinguish points, whole percentage points, automatic, none and uninterpreted values, retaining the original value/unit strings. Legacy cell width projections are read-only source views. Word text theme colors, luminance tint/shade and script fonts are resolved while preserving their source references. Conditional table text, paragraph and cell styles are resolved. Table/cell borders merge per edge, and typed cell margins, row grid omissions and row-level table exceptions retain their declarations and previous-property snapshots. Competing adjacent borders and page layout are not computed. ODF tables retain physical covered cells and row spans; covered source content is accessible directly but excluded from ordinary text/paragraph traversal. ODF ruby retains separate base/annotation text; Pages additionally resolves language ranges, tabs and explicit style resets. Its isolated table attachment paragraphs become table blocks in source order; table tile cells retain cached text and scalar values without recalculating formulas or locale display formats. Inline image attachments resolve package resources lazily and retain dimensions and alternative text. Unknown drawables and mixed text/table anchors retain unsupported markers and warnings. Fields retain cached display values and instructions without evaluation. Numbering definitions are available, but displayed numbers are not computed.

``Document/fieldDefinitions`` records complete instructions, parent identities and source completion state. ``Field/fragment`` links each local inline fragment to its definition, including start/end/separator boundaries. A complex field can span paragraphs, tables or controls; scan delivers its fragments as blocks arrive, without retaining the entire cached result or later mutating an emitted value. Fragment `instruction` is local text; use the definition for the complete instruction. `codeContent` retains instruction-side nesting and is excluded from display text. Individual notes, headers and text boxes have independent scopes. Unclosed fields retain incomplete definitions and produce warnings at story end; no closing marker or computed result is invented.
