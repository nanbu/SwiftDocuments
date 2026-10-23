# Verification

Run from the package root. Empty evaluation sets are failures.

| Check | Command | Negative controls / boundary |
|---|---|---|
| Behavior and malformed input | `swift test` | Synthetic ZIP/XML boundary fixtures plus independent producer oracles; Core/DOCX-only linking |
| API and concurrency contracts | Included in `swift test` | Registration order / replacement, explicit dispatch, MIME refusal, MainActor executor / task-local checks, controlled out-of-order batch completion, concurrency bound, child cancellation and joining, scan consumer-error priority, source-local style warnings, deflate / CRC chunk boundaries |
| Companion package consumers | `python3 scripts/check-companion-apis.py --sheets <checkout> --slides <checkout>` | Build and run each local companion with SwiftDocuments, including module-qualified names, registration, read / inspect / scan and companion round trips. No network dependencies; uses the higher of the two packages' toolchain requirements. Not included in CI, which does not check out companion repositories; does not verify a three-package graph. |
| Source and graphics reading | Included in `swift test` | Original symbol codes, font charsets, Japanese/ruby settings, revision property history and paragraph joins, DrawingML canvas/group nesting, SVG fallback references, all 187 preset geometries at multiple aspect ratios, OMML arguments, sparse chart caches and malformed source data |
| Geometry source and generated presets | `python3 scripts/generate-preset-geometries.py --check` and `swift test` | Pinned-reference drift, explicit preset/custom extrusion flags, Strict/Transitional custom commands, required coordinates/guide declarations, foreign namespaces, percentage offsets, preserved preset XML and read/scan warning parity |
| Field continuity | Included in `swift test` | Multi-paragraph code/result phases, nested instruction/result fields, table/control/hyperlink boundaries, independent note/text-box scopes, Strict/form source, malformed states, semantic depth bounds and immediate scan delivery across 2,000 cached paragraphs |
| Independent symbol fallback reference | `python3 docs/reference/symbol-font-fallback/generate.py --check` plus the standalone Swift checks in that directory | Generated-table drift, representative mappings, unmapped Japanese and unchanged source; no claim of installed-font coverage |
| Executable example | `swift run --package-path Examples/ReadDocument ReadDocument sample.docx` | Separate local package compiles against public API; input remains unchanged |
| Optimized build | `swift build -c release` | All products compile |
| Time and resident memory | `scripts/benchmark.py` with a release binary | Complete block / character counts and zero warnings checked before accepting paired time/RSS measurements; see performance.md |
| Support declarations | `python3 scripts/check-contract.py` | README matches nonempty support ledger, advertised tests exist, no package dependencies, synthetic fixture metadata |
| Support detector | `python3 scripts/check-contract.py --self-test` | Table drift, empty ledger, missing test, added dependency, personal fixture author |
| Public content | `python3 scripts/check-public-content.py --history` | Tracked and untracked nonignored files, ZIP contents and every reachable Git revision; home paths, companion references, private keys, GitHub/OpenAI/AWS/Google/Slack/service credentials and credential assignments, private directories, signing artifacts, logs and embedded report templates |
| Public detector | `python3 scripts/check-public-content.py --self-test` | Positive/negative controls for every rule, including expanded ZIP/IWA leaks, common service credentials and embedded private report templates; always also runs before the ordinary check |
| API reference | `scripts/build-docs.sh` | Fresh library-only compiler graphs with explicit re-export inclusion, public access only, every explicit symbol is rendered, deterministic English API inventory, required entry points and guide pages, no local home paths in output; DocC warnings fail |
| API detector | `python3 scripts/check-api-reference.py --self-test` | Missing rendered symbol, empty graph / output and local-path leak |

CI runs behavioral, release and publication checks on macOS and on Linux with Swift 6.2.4 and 6.4.1. Local macOS validation also uses Apple Swift 6.4. The library compiles for the arm64 iOS 17 target; device/simulator execution is not yet verified. DocC builds and deploys separately on macOS. Producer regeneration needs python-docx / LibreOffice, but test execution does not. Public-content checks supplement human review; they are not a general-purpose secret scanner.

The Linux Actions container trusts only its checked-out workspace for Git ownership checks. DocC queries the current module path and invokes the library symbol extractor with explicit re-export inclusion; no test-runner graph is needed.

## Extended format reading

The suite covers conditional Word table styles, theme color luminance transforms and script fonts, ODF common/automatic style scope, repeated tables, lazy assets, metadata, notes/headers, malformed XML/encryption and expansion limits. Modern Pages tests independently encode custom Snappy frames and Protobuf objects, checking referenced body ownership, UTF-16 surrogate boundaries, style inheritance, headers, scan parity and malformed graphs. These wire fixtures are synthetic. The additional `pages-15.4.pages` fixture was imported from a generated fictional DOCX and saved by Pages Creator Studio 15.4 (build 7051.0.79); its body order, Japanese/emoji text, 3×2 table, header row, dimensions, rich cell text and lazy image are compared to the source and observed Pages UI. See the fixture provenance for sanitation and reproduction.

ODF contract regressions also cover container/inline/table extensions counted once per source occurrence, unsupported explicit formatting and overflowing lengths, malformed/duplicate list levels, missing/duplicate note bodies with stories included or omitted, scoped table-style IDs and missing-style diagnostic locations. Pages regressions cover nested unknown fields, terminal and wrong-kind style references, dangling omitted-story targets and shared header/footer storage roles. Read and scan diagnostics are compared on the same inputs.

Table-reading regressions also cover Strict/Transitional border units and logical edges, independent style-edge overrides, original-view grid positions, row-level table exception history, invalid/foreign extensions and duplicate-edge rejection. ODF fixtures exercise row/column/cell style fallback per property, cell text/paragraph precedence and independent nested-table/note contexts, repeated columns, physical covered cells, ruby base/annotation separation, tabs and comment attribution. Pages wire fixtures check UTF-16 language ranges, explicit inherited-property resets, tabs, outline levels and writing direction. These formatting fixtures are independently constructed synthetic source packages. The separate Pages producer fixture verifies only its documented import/save path.

Pages attachment regressions also exercise sparse and wide tile offsets, exact decimal coefficients, unsupported cell versions/kinds/ranges, mixed text/table markers, cyclic rich-cell graphs, table work/depth limits, invalid resource mappings and deferred image CRC failures. The public-content audit decompresses IWA streams so Snappy compression cannot hide local paths.

## Basic writing and Markdown verification

Run the baseline tests/release build and `scripts/verify-basic-writing.py` with a
built CLI. With `--soffice`, the script independently opens generated DOCX,
DOCM and ODT in LibreOffice and checks Japanese/emoji, text, list items and code.
It also checks ZIP CRCs, generated XML, macro-enabled MIME without fabricated VBA,
and the first stored ODT mimetype entry. It uses fictional input in a temporary
directory and installs no producer output into this repository.

Swift tests independently construct Markdown source and model values, checking
headings, emphasis/links/code/lists, unsupported literal source, UTF-8 and parser
limits, read/scan parity, format selection, nested tables, default typography,
loss aggregation, strict failures and cancellation before saving. Markdown is a
subset; no CommonMark or GFM conformance is inferred.

The modern Pages body-text writer was opened in Pages Creator Studio 15.4 on
macOS on 2026-10-23. The generated fictional probe displayed Japanese, emoji,
paragraphs and a hard line break. This verifies that body-text output path only;
Pages formatting, tables, links and metadata are not native writing support.
The sanitized blank template and its generation instructions are retained in
`Sources/DocumentPages/Resources` and `scripts/prepare-pages-template.py`.
