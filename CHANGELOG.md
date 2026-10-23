# Changelog

## 1.1.0 — 2026-10-23

- Add the independent `DocumentMarkdown` UTF-8 subset reader with explicit Data
  format selection, extension-based text URL selection, limits and warnings.
- Add sync/async `Document.write` and `CodecSet.write`, atomic file saves,
  `WriteOptions`, `WriteResult`, aggregated writing losses and strict checks.
- Generate basic DOCX/DOCM/ODT packages with paragraphs, basic formatting,
  simple lists, links, tables and metadata. Generate modern Pages body text
  using a sanitized producer-created blank template with retained provenance.
- Add `swiftdoc convert input output` and independent package/LibreOffice
  verification tooling. Markdown writing and lossless package editing remain
  deferred. Original assets, macros and advanced content are not copied.
- Read ODT single/double underline types alongside their explicit styles.

Compatibility note: `DocumentFormat.markdown` and new `DocumentError` cases
require consumers with exhaustive switches to add cases or a default branch.
Existing reading-only custom codecs retain source compatibility through the
default writing implementation.

## 1.0.0

The first stable release of SwiftDocuments' documented reading API.

- Read DOCX and DOCM into format-neutral, Sendable values for paragraphs, text,
  formatting, tables, styles, sections, related stories and metadata.
- Inspect package inventories, scan body blocks and lazily retrieve original
  assets or namespace-preserving source XML.
- Preserve revision history, fields, content controls, Japanese typography,
  DrawingML geometry, Office Math structure and cached chart data within the
  boundaries in the [support table](README.md#support).
- Read documented subsets of ODT and modern Pages, with fictional producer
  fixtures and explicit warnings for uninterpreted content.
- Use synchronous or concurrent async reads and inspections, cooperative
  cancellation and bounded batch reads. Data and URL entry points accept the
  same optional format selection.
- Link individual codecs or the umbrella product. The facade follows
  SwiftSheets' model, codec selection and warning conventions.
- Reject malformed containers, missing required targets, exceeded package/XML
  limits, DTD/entities and unsupported encryption; never execute macros or
  fetch external relationships.

Requires Swift 6.2+, macOS 14+ or iOS 17+. Linux uses system zlib. There are no
external Swift package dependencies. Writing, conversion, rendering, legacy DOC
and decryption are outside this release. Partial/raw support remains explicit;
version 1.0 does not imply complete implementation of every source format.

Future public API changes follow semantic versioning. Breaking source changes,
including changes that invalidate exhaustive switches, require a major release.
