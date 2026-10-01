# Reading documents

Choose a full model, a package inspection or a per-block scan.

## Full model

``Document`` convenience initializers return the document and retain warnings in `readWarnings`. ``Document/read(contentsOf:options:)`` returns ``ReadResult``. Body blocks preserve paragraph / table order, while `paragraphs` and `tables` recursively flatten nested tables. Headers, footers, notes and comments remain separate ``Story`` values.

## Inspection

``Document/inspect(contentsOf:limits:)`` returns ``DocumentSummary`` without parsing the body. Expanded sizes are ZIP declarations. Metadata and necessary package infrastructure are inflated and checked; body and image CRCs are not checked by inspection.

## Per-block scan

``Document/scan(contentsOf:options:onBlock:)`` calls the synchronous throwing callback once per top-level body block in order. The result retains styles, sections, metadata, warnings and requested related stories, but no body blocks. A callback error propagates unchanged. A later XML error can be thrown after earlier callbacks have already run, so callers must handle partial effects.

Scanning releases each body-block XML tree, but retains ZIP input and expanded XML; it is not constant-memory streaming. A large table remains one block. Set `includeRelatedStories` to false when those bodies are unnecessary; the result reports `storiesOmitted` when appropriate.

## Warnings, limits and assets

``ReadWarning`` aggregates occurrences by code / part / element. ``PackageLimits`` bounds package sizes and parser work, not total process memory. Malformed packages, missing relationship targets and exceeded limits throw ``DocumentError``. DTD / entity declarations are refused; external URLs are never fetched and VBA is never executed.

Images store references and placement; ``Document/asset(at:)`` inflates the requested package part and validates its CRC. Opaque parts can be accessed the same way. Raw XML preserves semantics and namespaces, not byte-for-byte formatting.

## Units and formatting

Measurements use points. A multiple line spacing is expressed as a ratio; exact / at-least spacing is in points. Cell widths with a percentage unit retain the source value and unit. RGB and theme references remain separate; complete theme tint and conditional table-style resolution are not implemented. Fields retain cached display values and instructions without evaluation. Numbering definitions are available, but displayed numbers are not computed.
