# Changelog

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
