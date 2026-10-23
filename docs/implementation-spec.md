# Reading and writing specification

## Version 1.1 basic writing and Markdown

`DocumentMarkdown` is an independent codec product, re-exported by the umbrella.
`DocumentFormat.markdown` uses the canonical extension `md`; `markdown` is an
accepted extension alias. Markdown bytes require explicit `.markdown` selection
because plain text cannot be distinguished reliably from other text formats.
URL entry points select Markdown for `.md` / `.markdown` only when the input is
not a ZIP or OLE container; package signatures retain content-based detection.
`DocumentFormat.detect(Data)` continues to reject unidentifiable text.

Markdown input is strict UTF-8 (optional BOM), normalizing CRLF/CR to LF. The
initial subset covers ATX/setext headings (zero-based `outlineLevel`), paragraphs,
soft breaks as spaces, hard breaks, bullet/decimal single-paragraph list items,
backtick/tilde fenced code, inline code, backslash escapes, strong/emphasis and
inline links. Code uses the semantic style ID `MarkdownCode` (block) or
`MarkdownCodeSpan` (run) with a monospace font. These reserved style IDs are
portable hints, not Word XML names. Nested/multiblock lists, quotes, rules,
images, HTML, reference links, tables and extensions are retained as literal
source with aggregated warnings when recognized; there is no CommonMark/GFM
conformance claim; [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/) is a syntax reference, not a conformance assertion. Code fence language hints warn when discarded. HTML is never
executed, and no link or image resource is fetched. Empty Markdown has no blocks;
invalid UTF-8 or NUL throws `invalidText`. The existing byte, depth and node
limits bound Markdown input and parser/model work; scan and read warnings match.
Inspection validates encoding/byte limits without parsing body blocks and returns
an empty package inventory and metadata. Scan remains synchronous and buffered.

`DocumentCodec.write(_:options:)` has a default implementation throwing
`writingNotSupported` so existing third-party reading codecs remain compatible.
`CodecSet.write(_:as:options:)` and `write(_:to:as:options:)` return `WriteResult`
with bytes and aggregated `WriteWarning`s. The umbrella adds matching instance
methods on `Document`. Sync and `@concurrent` async variants have identical
semantics. Data writes choose explicit format, then `sourceFormat`, then DOCX.
URL writes choose explicit format, then recognized destination extension, then
the Data fallback. A missing codec throws `noCodec`. URL writes require a file
URL, serialize and validate first, then atomically replace the destination;
serialization, strict-loss and cancellation failures before commit leave it intact.

`WriteOptions(strict:compress:)` defaults to false/true. `strict` throws
`writingLoss` when any writing warning exists, before committing a file.
Compression applies to ZIP parts; ODT always stores `mimetype` first without
compression or extra fields, following [ODF 1.3 package rules](https://docs.oasis-open.org/office/OpenDocument/v1.3/OpenDocument-v1.3-part2-packages.html). ZIP32 output is deterministic and rejects sizes or
entry counts requiring ZIP64. Cancellation propagates unchanged.
Before recursive serialization or text projection, an iterative preflight bounds
the written body graph to 32 nested structural levels and 2,000,000 visited nodes,
including cached fields, controls, drawing text and equations. Exceeding this
basic-writer boundary throws `invalidModel`, rather than overflowing the call stack.

Basic writers generate new packages from the model; they do not patch original
XML or preserve unknown parts, revisions, macros, signatures or embedded assets.
DOCX/DOCM and ODT write paragraphs, tabs/breaks, bold/italic/strike/underline,
font name/size/RGB color, paragraph alignment/outline level, simple numbering,
external hyperlinks, rectangular unmerged tables (including nested tables), and title,
subject, creator, description and keywords metadata. DOCM uses the macro-enabled
main-part MIME but never invents or copies VBA. Invalid supported model values
throw `invalidModel`; unsupported semantics are flattened/omitted with warnings.
Resolved formatting is written directly; source style definitions are not copied. Nested links are flattened with warnings, and bookmark anchors are diagnosed because bookmarks are not reconstructed.
Nonrectangular/merged tables are projected to ordinary cells with diagnostics.
Word cells require a final paragraph: when nonempty cell content ends in a table,
the writer appends an empty paragraph and diagnoses the added boundary. Empty
cells receive an empty paragraph without a loss warning. Paragraph default text
formatting uses generated paragraph styles, separately from mark typography.
ODT inline page/column breaks become line breaks with warnings. ODT nested list
levels are flattened with warnings in this first writer. ODT reading recognizes
`style:text-underline-type` single/double/none alongside explicit solid/none underline style;
unsupported values remain warned properties.

Pages basic writing patches a sanitized, producer-created blank modern Pages
template with body text. Paragraphs, tabs, line/page breaks and Unicode are
supported; other content is projected to text with warnings. Formatting, tables,
lists, links and metadata are not claimed as native Pages writing support.
The template generation/sanitation script and provenance are retained. Producer
verification is recorded separately from synthetic self-read tests.

Markdown writing is a subsequent milestone; selecting it for writing currently
throws `writingNotSupported`. Layout, pagination and lossless round-trip editing
remain outside the basic writing contract. Public documentation must distinguish
this subset from the substantially broader reading contract below.

## Goal and completion boundary

Apply SwiftSheets' design principles to documents: Swift 6.2+, `Sendable` value types and no external Swift package dependencies. The current milestone implements the Word, ODF and Pages reading contracts below and verifies valid / malformed packages, producer-generated files and large synthetic documents. It is not a word processor or an implementation of every ECMA-376 rendering rule. The README support table and warnings define the boundary.

## Modules and extension points

`DocumentCore` owns the format-neutral document, block, paragraph, inline, table, style, numbering, story, section and metadata models; `DocumentCodec` / `CodecSet`; and shared ZIP / XML infrastructure. `DocumentDOCX` implements DOCX / DOCM. `SwiftDocuments` re-exports Core and all four codec modules and adds convenience entry points. Linking only Core and selected codecs uses the same model.

The internal system-zlib target/module is `CDocumentZlib`, with no public product. Its package-specific name allows an application to depend on SwiftDocuments alongside another package declaring `CZlib`. Shared public names such as `CodecSet`, `ReadOptions` and `TextRun` are qualified by module when importing multiple document libraries. `scripts/check-companion-apis.py --sheets <checkout> --slides <checkout>` builds and runs independent two-package consumers; it does not claim that the two companion packages can be linked to each other.

`DocumentODT` projects ODF content.xml / styles.xml onto the model. `DocumentPages` interprets modern IWA object graphs. Pages layout canvases must not be forced into Word's page semantics. Positioned and unknown content retains source parts and raw representations. The basic writing milestone above is additive; layout and encryption remain outside scope.

Pages detection inspects the first TSP.ArchiveInfo in Index/Document.iwa for object 1, type 10000 (TP.DocumentArchive). Shared iWork ZIP filenames alone do not identify Pages. Legacy iWork, Index.zip and folder packages are not supported.

## Entry points

- `Document.read(_:)` / `Document.read(contentsOf:)` return `ReadResult`; convenience initializers retain warnings in `readWarnings`.
- `CodecSet([.docx, .docm])` exposes read / inspect / scan with selected codecs.
- `Codec.format`, `CodecSet.formats`, `contains(_:)` and `codec(for:)` expose registration. Formats follow first registration order without duplicates; re-registering a format replaces only its implementation with the last choice. An empty or partial set throws `noCodec` for an absent format. A retrieved `Codec` can be registered in another set. The umbrella only forwards operations to `CodecSet.all`.
- All Data and URL entry points (`Document` initializers, read, inspect and scan) accept the same optional `format` override as `CodecSet`, matching SwiftSheets. Without it, package content determines the format regardless of filename. With it, the selected codec validates the contents; DOCX / DOCM MIME mismatches throw. Async URL reads and inspections forward the override with the same semantics. Batch reading detects each input independently. `DocumentFormat.fileExtension` and `init?(fileExtension:)` map standard extensions case-insensitively for display and explicit selection, without changing detection or implying an implemented codec.
- `scan` synchronously delivers top-level main-story blocks in order to a throwing callback. Callback errors propagate unchanged. Word scanning retains at most one body-block XML tree, but also the ZIP input, expanded XML, styles and requested related stories. It is not a constant-memory ZIP / XML stream. The returned document has no body blocks, and `blocksRead` counts delivered blocks. Earlier callbacks may have run when later malformed XML causes failure.
- `inspect` returns format, metadata, package inventory and declared expanded size without parsing body blocks or validating body / image CRCs.

## Concurrency and cancellation

`CodecSet` and `Document` offer same-named `async throws` read / inspect overloads; `Document.asset(at:)` also has an async overload. Synchronous methods and initializers remain available. In an async context Swift prefers the async overload, so existing calls may need `await`; a synchronous closure can explicitly select the synchronous operation. Scan remains synchronous to preserve non-Sendable callbacks and their caller-owned state.

The async work uses Swift 6.2 `@concurrent` to run on the generic executor, including when called from MainActor. It uses the current task rather than a detached task, retaining cancellation, task-local values and priority. File I/O remains synchronous; this API does not promise asynchronous disk I/O or a speed improvement. Codec protocols remain synchronous and Sendable; parsing state belongs to each operation.

`readAll(contentsOf:options:maxConcurrentReads:) async throws -> [ReadResult]` on both entry points uses a structured task group, with a default of four concurrent documents. The limit must be positive, otherwise `invalidOptions` is thrown even for empty input. Empty input returns an empty array. Results follow input order, including duplicate URLs. On failure or parent cancellation, cancel remaining children, wait for their completion and propagate the error. Limits apply to each document separately; the concurrency limit is not a total result-size or process-memory budget. A failing batch returns no partial result.

Cancellation is checked before/after dispatch and file reads, at ZIP entry and inflation/CRC chunk boundaries, at XML element/text callbacks and during block/story/style processing. Throw `CancellationError` unchanged; never turn it into malformed-input success, a warning or empty content. Scan checks before and after each consumer callback; an error thrown by that callback takes precedence over a cancellation it triggers. Earlier callbacks may have run when cancellation stops the scan. Foundation file I/O, stored-part copies, raw XML reconstruction and third-party codec code that does not check cancellation cannot be forcibly interrupted.

Executor semantics follow [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md), implemented in Swift 6.2. The minimum toolchain remains Swift 6.2.

## Formats and containers

Identify content through MIME, content types and root relationships; do not trust filename extensions or assume a fixed main-part path. Read DOCX / DOCM, Strict / Transitional WordprocessingML and stored / deflate / ZIP64 packages. Read ODT and a documented subset of modern Pages; an explicitly unregistered codec still throws `noCodec`. Refuse OLE legacy DOC and encrypted OOXML containers without claiming an exact distinction.

Built-in Word dispatch reuses the validated archive and OPC metadata created during content detection. It does not rebuild ZIP inventories and reparse content types merely to enter the selected codec. Explicit format selection still validates MIME, and custom codecs retain the existing raw-Data protocol without a new conformance requirement. Parsing and caches belong to each operation; no mutable global document cache is introduced.

Internal selective XML lookups traverse ordered mixed content directly rather than allocating a complete child array for each lookup. Text projection has a single-content fast path; descendant lookup retains source order and namespace matching with an iterative traversal. These optimizations do not cache mutable source trees or relax parsing limits.

Run and paragraph formatting retain public mutable value semantics through private copy-on-write storage. Empty formatting may share immutable default storage; every mutation first obtains unique storage, including mutations of arrays. Copies sent to independent tasks cannot change each other's formatting. This avoids embedding the complete optional formatting payload, including historical properties, in every run/paragraph. Performance claims still require paired time and resident-memory measurements on identical operations and input.

Revision attribution and formatting-history records use immutable shared snapshots. Public setters replace the snapshot, so changing a copied record cannot mutate its source. Optional absent revision/history fields therefore do not reserve the full string/property payload in every unchanged run or paragraph. A former-property snapshot is decoded once per source record and reused when it is also the selected original view; warning occurrence counts do not increase merely because the snapshot is visible in two API locations.

Sections also use private copy-on-write storage while retaining their mutable value API, including dictionaries/columns. An absent paragraph section break therefore does not reserve a complete section payload in every paragraph. Inheritance updates on the document's section list do not mutate independent copies of source section values.

Check CRCs on inflation, declared lengths, duplicate names, local headers, overlapping entry ranges, unsafe paths and multi-disk ZIPs. Defaults are 10,000 parts, 512 MiB expanded total, 128 MiB per part, depth 128 and 2,000,000 XML nodes. Violations throw. Reject DTD / entity declarations, including UTF-16 / UTF-32 inputs. External relationships remain URLs and are never fetched. Normalize internal relationship paths within the OPC package; traversal, missing targets and duplicate IDs throw.

A Foundation parser can report an XML error while its Boolean return value indicates success, particularly on Linux. Reject reported parser / delegate errors, mismatched element boundaries, multiple roots and incomplete documents; never turn recovery into a successful document. Callback errors and explicit limit errors retain priority.

## Word contract

### Preservation and warning coverage

Unknown children of the document root are retained in `Document.uninterpretedContent`, separately from body blocks, with `unsupportedContent` warnings. Uninterpreted row and cell properties remain in `properties` and produce `uninterpretedFormatting` warnings. Recognizing a property name does not imply that all its attributes and children were interpreted: additional section-column information must be retained and diagnosed. Read and scan produce identical aggregated warnings for identical input and options, including these locations. Foreign namespaces cannot impersonate recognized properties or attributes.

The same namespace rule applies to font tables and metadata. Core, extended and custom metadata roots must match their declared relationship kind; foreign children cannot fill standard fields merely by matching a local name. Uninterpreted metadata/font records and attributes warn during reading and remain in original parts. Paragraph/style numbering references reject malformed explicit level values rather than silently replacing them with zero; unknown numbering-reference children and attributes warn.

Explicit invalid on/off values do not become true merely because they differ from the false spellings. Optional formatting/control states remain uninterpreted with warnings; required model booleans retain their normal default plus the diagnostic. Absent on/off values on a present standard on/off element use its schema default.

Property-container attributes and recognized leaf properties are covered by the same preservation contract. Unknown attributes on run/paragraph properties, tabs, numbering references and section properties remain in normalized raw properties and warn; unexpected children of a recognized leaf also warn. Invalid explicit paragraph lengths, tab positions and outline levels cannot disappear as an apparently fully interpreted property. Section grid attributes use standard Word names only; a foreign attribute with the same local name cannot replace a standard grid setting. Section references validate relationship attributes separately from Word attributes.

### Expanded reading and display preparation

The expanded contract retains DrawingML canvases, groups, shapes, connectors, pictures, transforms, anchors, wrapping, text boxes and SVG/fallback asset choices as format-neutral drawing values. Original image bytes remain lazy and CRC-checked; reading never executes SVG, macros, embedded objects or external relationships. Unknown drawing properties remain recoverable and diagnosed. Text and paragraphs inside shapes use the same formatting and revision rules as body stories.

Picture fills expose the same lazy image and preferred-SVG/fallback references as standalone pictures, including unfetched external fallback URLs. Canvas backgrounds and pattern foreground/background colors are retained. Source style references and unprojected text-layout/color details remain raw with warnings rather than silently appearing fully interpreted.

`DocumentDrawing.revision` and `DocumentImage.revision` retain the enclosing insertion, deletion or move attribution, using the same final/original/all visibility rules as text. A standalone picture and its `drawing` scene expose the same attribution. Attribution belongs to the placed scene; text inside a shape remains an independent story with its own revisions. Legacy VML scenes retain enclosing attribution too. This is reading metadata, not an API for accepting/rejecting changes or writing documents.

Word connector shapes are distinguished by their nonvisual connector properties. `DrawingNode.startConnection` and `endConnection` retain the target object ID and zero-based connection-site index without routing lines or inventing missing objects. Missing, duplicate or invalid required connection fields throw; unknown connection properties remain raw and warned. Object identifiers are read only from the object's own nonvisual properties, never from a descendant shape. Canvas whole-object line formatting is exposed in `DrawingNode.line`; unprojected effects remain raw with warnings. Empty canvas formatting records do not produce warnings.

Drawing placement and geometry recognize exact Transitional/Strict namespaces. Foreign elements and attributes cannot supply standard positions, identifiers, colors or path commands. The Office 2010 horizontal/vertical percentage offsets retain fractions for both numeric and percent-suffixed source values. Custom paths retain their coordinate dimensions, fill, stroke and extrusion flags, including explicit false values; bundled preset paths retain explicit extrusion flags too. Missing required guide names/formulas, point coordinates or arc arguments, incorrect recognized-command arity and duplicate guide declarations throw instead of synthesizing zero coordinates or unsupported commands. Invalid optional path dimensions/flags and unknown geometry extensions remain source data with warnings. Preset expansion retains the original geometry subtree; unknown preset adjustments warn instead of disappearing silently. Read and scan diagnose the same source occurrences.

Japanese text retains script-specific font names/themes, language, ruby annotations, vertical text, emphasis and paragraph line-breaking settings. Legacy Symbol/Wingdings text and explicit symbol elements retain original font and character values without Unicode substitution. Numbering retains source levels, starts/restarts, overrides, suffixes, picture references and font properties; it does not generate presentation labels.

`Paragraph.defaultTextFormatting` exposes resolved default text properties even when the paragraph has no runs. Optional `paragraphMarkFormatting` and `paragraphMarkFormattingChange` retain the paragraph-ending character's separate typography and its former-property snapshot; these properties never format existing body runs or synthesize a paragraph glyph. All paragraph-mark revision annotations remain in `paragraphMarkRevisions`; the singular convenience property reads the first annotation and replaces the annotation list on assignment. Multiple/move mark annotations that cannot be faithfully projected by the paragraph-join operation warn. Malformed or duplicate previous-property records throw for run, paragraph and paragraph-mark formatting just as they do for tables.

Picture list markers retain their image relationship, original source representation and lazy asset bytes. Missing picture declarations warn; duplicate IDs, invalid level indices and conflicting overrides throw. Uninterpreted numbering children and attributes warn rather than disappearing behind a recognized parent name. Auxiliary Word parts contribute their relationships to the package inventory/diagnostics, including numbering images and embedded fonts.

The reading/writing package does not select installed fonts, bundle replacement fonts or change source glyph codes. Applications and separate rendering libraries own glyph substitution, font fallback and display-label generation. `TextRun.text` and body `plainText` preserve source character scalars; explicit symbols additionally expose their font name and character code in `SymbolCharacter`. A missing Office font on the reader's machine does not change a read result or produce a parsing warning. This boundary supersedes the earlier experimental display-fallback design.

Standalone fallback reference material lives in `docs/reference/symbol-font-fallback`, outside all package targets. It includes pinned Unicode mapping sources, an offline generator, pure Swift lookup tables, an optional CoreText glyph-check example and a human-readable HTML specification. It describes a downstream display policy, never a reading transformation. References preserve unmapped values, distinguish installed font names from actual glyph coverage and apply standardized text-presentation selectors only to eligible mapped characters. No replacement font binary is distributed.

`Document.readSourceXML(at:)` exposes an immutable, Sendable `SourceXMLNode` tree for an original XML part, with original element/attribute QNames, in-scope namespace bindings and ordered mixed content. It uses the document's read limits, validates the part CRC, rejects DTD/entities and never fetches relationships. Sync and async entry points match the companion libraries. This is an explicit, on-demand preservation API, not a claim that all source semantics were interpreted. Ordinary reads do not copy a complete source tree into the model.

Equations use the companion libraries' `Equation` / `EquationNode` vocabulary. DOCX projects Transitional and Strict Office Math into typed fractions, roots, scripts, matrices, delimiters, limits, operators, runs and property nodes. Argument wrappers and producer order are retained; required missing/duplicate arguments throw. Unknown nodes remain native and warn. An equation retains a namespace-correct normalized source subtree and its part path; exact original part bytes and QNames remain available through the original-part APIs. `lexicalText` joins text tokens without inventing operators or converting to a linear mathematical notation; body `plainText` uses that projection. Equations are immutable shared snapshots, including in scan, related stories and shape text. Reading does not calculate, shape, typeset or rasterize an equation.

Chart reading uses `Chart`, `ChartGroup`, `ChartSeries`, `ChartData`, `ChartPoint`, `ChartAxis` and `PartReference`, following SwiftSlides' vocabulary. Retain chart groups, series order, formulas, sparse indexed literal/cache points, multi-level categories, axis references/scales, titles, legend position and workbook relationships. Do not fill sparse gaps, allocate from a declared point count, recalculate formulas or fetch external resources. Invalid/duplicate point indices and non-finite axis values throw; nonnumeric cached values and inconsistent point counts remain lexical values with warnings. Complete original chart XML is retained alongside the projection; advanced appearance and unknown extensions warn. Charts declared through main/related-story relationships are prepared before body SAX callbacks, so the implementation does not start a reentrant Foundation XML parse. Original workbook/image bytes remain available through lazy assets. Reading a chart is separate from evaluating workbook data or rendering a chart.

Revisions retain attribution for text, paragraph marks, formatting, rows and cells. Original view applies recorded former properties; final view uses current properties; all view preserves change metadata. Deleted paragraph marks join adjacent paragraphs in final view, and inserted marks join them in original view. Parsing and scan remain bounded by top-level body blocks, apart from a pending paragraph needed for a paragraph-mark join.

`FormattingChange<Value>` provides one immutable snapshot contract for previous text, paragraph, table, row and cell properties, with revision attribution and an optional normalized source record. Table/row/cell property changes apply their previous typed properties in original view. Cell insertions/deletions follow the selected revision view, while all view retains attribution. Recorded cell merge states distinguish merged-with-previous from split (`cont`/`rest` in Word annotations); `rest` is not the normal merge-start token. Merge records retain both states and attribution without inventing virtual cells. Unknown properties remain raw and warned.

Physical table column declarations retain optional widths and original width strings in `Table.columns`; a missing width does not remove the column. `columnWidths` is the compatibility projection of known widths. Recorded column-definition changes retain their previous columns and select them in original view. Formatting histories contain properties only, never duplicated cell/body content. Revision snapshots retain original attributes, including extensions.

Source preservation and typed interpretation are recorded independently from downstream visual fidelity. No renderer/font fallback is included in the public products, and no universal pixel-identical pagination or installed-font availability is inferred from parser tests. API documentation, executable examples and the feature/evidence ledger are public English documents; version tagging and publication require the final release decision.

Library diagnostics, CLI usage and public API documentation use English. Warning codes and structured source locations identify diagnostic categories independently of message wording; a consumer should not parse localized prose as an API. Source document text remains in its original language and encoding semantics.

## Subsequent format milestones

Word, ODT (LibreOffice Writer) and Apple Pages reading retain their format-specific semantics and original-part preservation contracts. The first writing milestone is the supported subset above, following SwiftSheets' codec, options and warning conventions; lossless editing and Markdown writing remain future work. An unmeasured format or operation is never marked complete. Release tagging and publication remain a separate final decision.

Read body order, paragraphs, formatted runs, tabs, breaks and tables (nested tables, gridSpan, vMerge, widths, borders and cell properties). Frequent run / paragraph properties have typed fields; raw XML supplements uninterpreted properties. Resolve style inheritance and Word style toggles. Preserve numbering abstract definitions, instances and level overrides; paragraphs carry numbering IDs / levels, without computed display numbers.

Preserve section size, margins, columns and inherited header / footer references, without pagination or automatic wrapping. Read links, bookmarks, simple / complex field instructions and cached results, note references, comment ranges and comment bodies. Images carry asset references, alternative text, EMU-to-point sizes and inline / floating placement; assets inflate and validate CRC on demand. DOCM VBA is never executed; it remains an opaque part in the inventory with a warning.

Revision views are `.final` (default), `.original` and `.all`. Runs carry revision ID, kind, author and date. Inserted / deleted table rows and cells follow the view. Paragraph-mark merging and historical text/paragraph/table properties follow the rules above; other historical property structures remain recoverable with warnings. Missing note / comment references warn with `invalidReference`; reference checks are omitted when related stories are omitted.

Missing paragraph / character style references warn with `invalidReference` at the referring part and element while retaining the style ID, text and available direct/default formatting. Missing `basedOn` targets warn at the styles part while retaining the resolvable inheritance chain. Warnings aggregate by code / part / element, and read / scan return the same warnings for the same options. Missing style references do not fabricate styles or become parse failures; style cycles and excessive chain depth still throw.

Read cached content inside typed content controls. Custom-XML wrappers, OLE, altChunk and unknown semantic elements retain raw XML and warnings. Charts have the typed projection described above, supplemented by raw properties and warnings for uninterpreted semantics. Text boxes and shapes have the typed projection described above, supplemented by raw properties and warnings for uninterpreted semantics. Aggregate warnings by code / part / element with an occurrence count so repeated unsupported content does not grow the warning array indefinitely. Raw XML preserves meaning and namespaces, not original bytes or namespace prefixes.

Content controls retain typed block/inline wrappers with nested cached content, source IDs, titles/tags, editing locks, placeholder metadata, source property snapshots, binding paths, list entries, date settings and explicit checkbox state/symbol metadata. Controls wrapping physical table rows/cells retain descriptors and ranges over the flattened row/cell arrays; they do not duplicate grid content or fabricate cells. Body text, paragraph/table traversal and scan preserve source order; a block control is one top-level scan block. Binding resolution, placeholder generation, date reformatting and interactive editing are not performed. Unknown control properties and unexecuted bindings warn, while source header data remains available. Rendering never replaces the cached content with a generated checkbox or font-dependent symbol. Cross-control paragraph-mark joins that cannot be represented retain their source revision with a warning.

### Field continuity

Complex fields remain open across paragraphs, block controls and tables within one story. `Document.fieldDefinitions` contains operation-local stable IDs, parent IDs, complete lexical instructions, source part/header, lock/dirty state, separator presence and completion state for simple and complex fields. Each `Inline.field` is a value snapshot of a local fragment: `Field.fragment` links it to its definition and records start/end/separator boundaries. `instruction` contains only the instruction text in that fragment; the definition contains the full instruction after the operation completes. This avoids repeatedly copying a growing instruction prefix into every emitted block. `codeContent` retains ordered instruction-side inlines, including nested fields, separately from cached `result`. Code-only fields and nested instruction fields do not contribute display text. Instructions are never evaluated or concatenated with generated nested-field values. Semantic complex-field nesting is bounded by `maxXMLDepth`, including across paragraph boundaries.

Fragments may split at paragraph or inline-container boundaries. Matching IDs and definition parent IDs express continuity without moving text out of hyperlinks/controls or rewriting blocks already delivered to scan. The reader keeps open-field state and definitions, never an entire field's cached body. Scan returns the same definitions and fragment snapshots as read. A missing separator means no cached result. Unmatched/repeated markers and misplaced instructions warn; unclosed fields warn once at story end, retain incomplete definitions and expose cached text. No end marker is invented. Simple fields missing their required instruction attribute throw. Headers, individual notes/comments and text boxes have independent field scopes; table cells and block controls preserve their enclosing story scope. Omitted stories contribute no definitions. Original-part APIs retain unsupported form-field data and extension metadata, which produce warnings. Invalid explicit lock/dirty booleans remain unspecified and warn.

## Formatting and semantic boundaries

Resolve defaults → paragraph basedOn chain → paragraph direct formatting → character style → run direct formatting. Style booleans are toggles; direct formatting provides explicit values. Style chains are limited to 128 links and cycles are rejected. Table styles retain whole-table and conditional paragraph/text/cell properties, basedOn chains and source XML. Resolve horizontal bands → vertical bands → first/last columns → first/last rows → corners, following Office precedence. `tblLook` named flags override the corresponding legacy mask bits; absent flags use the mask or the schema defaults (banding enabled, edge regions disabled). Band sizes default to one and must be positive. Grid spans and omitted leading/trailing grid cells determine column positions. Table formatting precedes paragraph/character styles and direct properties. Nested tables establish their own context; row-level table exceptions are separate declarations, and explicit conditional masks remain raw and warned.

Resolve Word text theme colors (including settings color-scheme mappings), HSL luminance tint/shade (tint wins when both occur), and major/minor Latin, East Asian and complex-script fonts. Preserve source theme identifiers and tint/shade bytes in `TextFormatting`. Use explicit language or theme-font settings for script-specific theme fonts, without installed-font lookup. Missing theme slots or unsupported color sources warn and retain cached source values. Theme palette supports sRGB and system last-color values; DrawingML transforms, automatic colors and viewer-dependent font substitution remain outside this contract.

Tables retain physical cells with separate `columnSpan` / `verticalMerge`; they do not fabricate virtual merged cells. Body `plainText` separates paragraphs with newlines, cells with tabs and rows with newlines. Related stories remain separate. Fields return cached text without evaluating instructions. Hidden text remains in the model.

### Table appearance and grid geometry

Tables and cells expose format-neutral border edges (physical left/right and logical start/end are distinct), source line style, point width/spacing, color/theme references and explicit none/nil states. Word line borders use eighth-point widths; decorative art widths are retained as source values with a warning rather than incorrectly converted. Edge declarations merge individually through table styles and conditional cell regions; direct properties override inherited edges, including explicit suppression. Reading does not resolve competing adjacent borders or compute collapsed borders. Unknown edges, attributes and invalid optional border values retain source XML and warn; duplicate recognized edges throw.

Tables expose alignment, layout mode, indentation, default cell margins, cell spacing and visual direction. Cells expose margins, text direction, no-wrap and fit-text state. Rows expose leading/trailing omitted grid columns, their preferred widths and whether row splitting is prevented. Row-level table exceptions remain separate in `tableOverrides`, with their own former-property snapshot; they do not overwrite the parent table declaration. Row/cell/table previous-property snapshots contain the same fields; the original revision view uses previous grid positions for conditional styles. Physical table widths, offsets and padding retain their units without inventing page or column positions. Table-level defaults and cell-specific margins remain distinguishable.

ODF table, column, row and cell styles resolve inheritance and automatic-style scope. Column widths, row height/minimum height, background, cell padding, border edges and percentage table widths use the same model. Cell-style properties fall back individually through explicit cell → row default → column default → family default. Their paragraph/text declarations also apply to cell content, below explicit paragraph/character styles; nested tables establish independent cell contexts. Covered cells remain physical source cells with `isCovered`, their own content, and one grid position; spanning anchors retain `rowSpan` / `columnSpan`. No virtual continuation cells are generated, and covered content is excluded from ordinary table text and paragraph traversal. Counts, repeats and model expansion remain bounded by the existing budget. Unknown table properties remain recoverable and diagnosed.

Word lengths accept unqualified twips/half-points and universal `mm`, `cm`, `in`, `pt`, `pc` and `pi` suffixes, converting physical lengths to points without selecting fonts or laying out content. `TableWidth` represents points, whole percentage points, automatic, none or an uninterpreted unit and retains the original value/unit strings. Tables and cells expose `preferredWidth`; legacy cell width projections are read-only views of that value. A percent suffix overrides the declared Word table unit; unqualified `pct` values are fiftieths of a percent. Missing/sparse declarations are not fabricated. Non-finite/invalid recognized widths throw; unrecognized width units remain source data with warnings.

## ODT contract

ODF ruby retains separate base and annotation inlines, ruby alignment/position, annotation text style and source properties. Each ruby requires exactly one namespace-correct base and annotation; only the base contributes ordinary text/runs. Paragraph tab-stop declarations retain point positions, alignment and literal leader text. Invalid optional positions and unsupported alignment values remain source data and warn rather than becoming zero/left tabs. ODF annotation author/date and range-end markers are projected without adding comment-body text to the main body. Independent notes/comments do not inherit their referring table cell's text context.

Recognized ODF containers and inline/table elements diagnose unprojected attributes, child elements and non-whitespace container text. Foreign extension elements do not become body text. Diagnostics refer to source occurrences, so repeated rows/cells do not multiply extension warnings. Original XML remains accessible through `readSourceXML`. Unsupported explicit alignment, break, keep, decoration and line-height values remain raw and warned; they never become fabricated false/single/exact values. Physical measures must remain finite after conversion. Numbered list levels and start values must be positive integers; missing/duplicate levels and malformed values throw rather than defaulting to a valid list. Notes require one note body; missing/duplicate bodies throw even when related stories are omitted.

`ODTCodec` / `Codec.odt` validate the ODF text MIME, content root and optional manifest; encrypted manifest entries are refused. Read common, default and automatic paragraph/text/table/row/column/cell/ruby styles from styles.xml and content.xml with namespace-correct lookup and bounded, cycle-checked inheritance. ODF booleans are explicit values, not Word toggles. Read ordered paragraphs/headings, spans, tabs, spaces, breaks, links, bookmarks, lists, nested tables, repeated rows/cells, column/row spans and explicit covered cells, without fabricating virtual cells. Repetition and synthesized model work share a bounded budget derived from maxXMLNodes; invalid counts throw. Read embedded/external image references lazily, notes/comments as separate stories, master-page headers/footers and metadata. Unknown structures/properties retain XML and warnings. Unsupported positioned frames do not become main-body text. Page-style layout, field execution, tracked-change projection and advanced ODF style maps remain raw and warned. Inspect reads inventory/metadata/manifest but does not parse content.xml; scan currently retains the full content XML tree (unlike Word's incremental body parsing).

## Pages contract

Pages additionally projects language boundary tables onto UTF-16 text ranges, paragraph tab stops and outline levels, capitalization, emphasis and explicit writing direction. Language resets return to the effective style language; ranges never split surrogate pairs. Named-font/color/language and tab/line-spacing null declarations clear inherited values rather than leaving a parent's value active. Unknown tab alignment or writing direction warns without substituting a guessed value. Source null flags remain in the original IWA records; the shared formatting model represents their resolved effect.

Projected nested style headers, colors, line spacing and attribute-boundary tables diagnose unknown fields with a qualified field path. Recognized-but-unprojected storage/style fields also warn. Unsupported alignment values remain unspecified and warned. All style references in boundary tables are validated, including terminal boundaries with no display text; paragraph and character references must target the corresponding style kind. Header/footer references must resolve to text storage even when related stories are omitted. A storage referenced as both header and footer retains both story roles.

`PagesCodec` / `Codec.pages` validate object 1/type 10000 and follow its body-storage reference rather than collecting every storage object as body text. Decode all custom Snappy chunks and bounded Protobuf archive messages, rejecting invalid lengths, wire types, duplicate object IDs and dangling required references. Expanded IWA data and message/field counts are bounded by the read limits, including aggregate decoded bytes across parts. Decode type-2001 text chunks, UTF-16 paragraph/character style boundaries, type-2021/2022 style inheritance and basic text/paragraph properties. Reject boundaries splitting surrogate pairs or outside storage text. Decode paragraph separators, tabs, soft line breaks and page breaks. Root page geometry is retained separately from text flow; referenced header/footer storage remains in stories; note/textbox attachment semantics remain opaque. Unknown objects, attachments, unsupported attribute tables and unprojected fields are diagnosed and original IWA bytes remain available through assets. Layout-only files have no fabricated body: positioned objects remain opaque. List labels, field semantics and revisions in Pages remain source data with warnings. Legacy XML iWork, nested Index.zip and directory packages remain unsupported. Inspect validates the root IWA and package inventory without decoding every body/storage object; scan retains the bounded decoded graph. Producer evidence is limited to the documented fictional DOCX imported and saved by Pages Creator Studio 15.4; it does not establish compatibility with all Pages documents.


Storage attachment table 9 uses point anchors at UTF-16 U+FFFC markers. Follow drawable attachments (2003) to tables (6000/6001) and images (3005). An isolated table marker paragraph projects to a table block in source order; mixed text/table anchors and other drawable types retain an unsupported inline marker and warn rather than inventing paragraph boundaries. Non-marker attachment variants remain opaque with warnings. Missing referenced objects, duplicate/surrogate-splitting/out-of-range anchors, graph cycles and excessive nesting throw. Storage section table 17 establishes header/footer ownership in addition to legacy root section references.

Tables project bounded row/column dimensions, header rows, column widths and row heights, current version-5 tile buffers (including wide offsets), string/rich-text cells and cached scalar values. Sparse cells preserve grid positions. Rich text follows 6005 data-list / 6218 payload / 2001 storage references and retains text formatting; unsupported segmented data lists, payload ranges, cell encodings, formulas and display formats warn and retain their original source. Numeric projection uses cached lexical values without recalculation or locale formatting. Unsupported cell content is represented explicitly instead of being mistaken for an empty cell. All synthesized grid cells count toward the read work limit before allocation. Unprojected table styles and merge metadata warn; no merge geometry is inferred.

Images resolve resource identifiers through Metadata.iwa data-info entries to existing safe Data/ package paths, retaining asset names, accessibility descriptions and drawable sizes in points. Image bytes remain lazy and are CRC-checked only when requested as assets. Missing/duplicate resource declarations and unsafe/missing image targets throw. Unsupported crops, masks and wrapping remain source data and warn. The producer fixture retains only generated media; its preparation script removes previews, unused bundled theme images and local printer settings, normalizes package metadata, and preserves the body/table/image IWA graph.

## Sources and verification

- [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/), Parts 1–4.
- [Microsoft: WordprocessingML structure](https://learn.microsoft.com/en-us/office/open-xml/word/structure-of-a-wordprocessingml-document).
- [Microsoft: paragraph-mark typography](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.paragraphmarkrunproperties?view=openxml-3.0.1) and [its former properties](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.previousparagraphmarkrunproperties?view=openxml-3.0.1).
- [Microsoft: tracked cell merges](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.cellmerge?view=openxml-3.0.1) and [the distinct annotation values](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.verticalmergerevisionvalues?view=openxml-3.0.1).
- [Microsoft: Office Math objects and argument structure](https://devblogs.microsoft.com/math-in-office/officemath/).
- [Microsoft: complex field markers and story boundaries](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.fieldchar?view=openxml-3.0.1).
- [Microsoft: chart cache values](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.charts.numberingcache?view=openxml-3.0.1).
- [Microsoft: canvas background and whole-object line formatting](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-odrawxml/c62c9d58-77b1-426f-b11d-9a6f877e7491) and [Word shape connector properties](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.office2010.word.drawingshape.wordprocessingshape?view=openxml-3.0.1).
- Hand-built synthetic fixtures target specification boundaries. Independent python-docx and LibreOffice producer fixtures verify interoperability; provenance is recorded beside them.
- `swift test`, release builds and support / public-content checks run in CI on macOS and Linux.
- Benchmark both time and memory; untested environments are not called verified.

## Publication and documentation

Only reusable implementation, tests, synthetic fixtures, English documentation and canonical marketing content belong in this repository. Never publish private development reports (including embedded report-template source), raw work logs, local paths, customer documents or credentials. Marketing content defaults to English and may offer a Japanese translation. A public-content detector checks tracked and nonignored untracked files, expanded fixture contents and reachable Git history for private artifacts and common credential formats; negative controls cover each detection rule. Its commands are recorded in verification.md. This is defense in depth, not proof that every possible secret can be recognized.

Version 1.0 stabilizes the documented reading API under semantic versioning. Partial projections and raw-only features remain explicit in the support ledger; version 1.0 does not promise complete Office/ODF/Pages interpretation, writing or rendering. Public API changes after 1.0 follow semantic versioning, with additive improvements allowed in minor releases.

The API reference is built with DocC from public compiler symbol graphs. All six library modules and the umbrella's convenience extensions are included. CI publishes only the generated documentation artifact to GitHub Pages. Build outputs and symbol graph source paths are not committed.

An English Markdown API inventory is generated from those compiler graphs, with deterministic ordering and declarations rather than a manually maintained list. Executable examples are separate local Swift packages using the public products; their documented commands compile and run against synthetic inputs.

Format references: [ODF 1.3 schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html), [TSWP field schema](https://github.com/masaccio/numbers-parser/blob/master/src/protos/TSWPArchives.proto), [TST table schema](https://github.com/masaccio/numbers-parser/blob/master/src/protos/TSTArchives.proto), [TSD drawing schema](https://github.com/masaccio/numbers-parser/blob/master/src/protos/TSDArchives.proto), [Pages root fields](https://github.com/isoparametric/python-pages/blob/main/schema/TP_partial.proto), [Office table precedence](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/f7f85a73-5f60-4f7e-a725-4f1f06198388). Schemas inform independently implemented readers; no third-party runtime dependency is added.
