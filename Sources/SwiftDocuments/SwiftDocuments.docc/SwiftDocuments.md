# ``SwiftDocuments``

Read and write documents through a format-neutral, Sendable value model.

## Overview

SwiftDocuments 1.0 provides a reading API governed by semantic versioning. It reads DOCX and DOCM with no external Swift package dependencies. ODT and modern Pages have partial reading codecs: ODF text/styles/tables/images/related stories, and Pages IWA body text/basic styles/referenced headers and footers, anchored tables and lazy inline images. Positioned objects and advanced table/image properties remain original IWA data with warnings. A fictional DOCX import/save fixture is verified with Pages Creator Studio 15.4; this does not establish support for every native Pages feature. Version 1.1 adds UTF-8 Markdown subset reading and basic DOCX/DOCM/ODT writing, plus modern Pages body-text writing. Source package parts, assets and advanced semantics are omitted with explicit writing warnings. Markdown writing, decryption and layout remain outside this milestone.

```swift
import Foundation
import SwiftDocuments

let result = try Document.read(contentsOf: URL(filePath: "report.docx"))
print(result.document.plainText)
print(result.warnings)
```

The umbrella re-exports `DocumentCore`, `DocumentDOCX`, `DocumentODT`, `DocumentPages` and `DocumentMarkdown`, registering `.docx`, `.docm`, `.odt`, `.pages` and `.markdown`. Select only Word through `CodecSet([.docx, .docm])` when linking those products directly. Read / inspect / asset offer both synchronous and async methods. Async work runs on the generic executor with cooperative cancellation. Unsupported content is recoverable through warnings, raw XML and original package parts.

See <doc:Reading> for read / inspect / scan semantics and <doc:Cookbook> for recipes. The [support contract](https://github.com/nanbu/SwiftDocuments#support) states precisely what the reader interprets.

## Topics

### Opening and reading

- ``Document``
- ``ReadOptions``
- ``ReadResult``
- ``ScanResult``
- ``DocumentSummary``
- ``DocumentFormat``
- ``DocumentError``
- ``PackageLimits``
- ``ReadWarning``

### Basic writing

- ``WriteOptions``
- ``WriteResult``
- ``WriteWarning``

### Body and inline content

- ``Block``
- ``Paragraph``
- ``Inline``
- ``TextRun``
- ``BreakKind``
- ``Hyperlink``
- ``Field``
- ``FieldDefinition``
- ``FieldFragment``
- ``DocumentImage``
- ``NoteReference``
- ``Bookmark``
- ``CommentReference``
- ``Revision``
- ``UnsupportedContent``

### Drawings, equations and source data

- ``DocumentDrawing``
- ``DrawingNode``
- ``DrawingTransform``
- ``DrawingPlacement``
- ``DrawingGeometry``
- ``GeometryPath``
- ``Equation``
- ``EquationNode``
- ``Chart``
- ``ChartGroup``
- ``ChartSeries``
- ``ChartData``
- ``ChartPoint``
- ``ChartAxis``
- ``PartReference``
- ``SourceXMLNode``
- ``SourceXMLReadResult``
- ``RubyText``
- ``SymbolCharacter``
- ``DocumentFont``
- ``DocumentTheme``

### Formatting and lists

- ``TextFormatting``
- ``ParagraphFormatting``
- ``FormattingChange``
- ``TextFormattingChange``
- ``ParagraphFormattingChange``
- ``ParagraphAlignment``
- ``LineSpacingRule``
- ``TextVerticalAlignment``
- ``DocumentStyle``
- ``ListReference``
- ``NumberingDefinition``
- ``NumberingLevel``

### Tables and related stories

- ``Table``
- ``TableBorder``
- ``TableBorderEdge``
- ``TableCellEdge``
- ``TableAlignment``
- ``TableLayout``
- ``TableRow``
- ``TableCell``
- ``TableFormatting``
- ``TableRowFormatting``
- ``TableCellFormatting``
- ``TableRowHeightRule``
- ``TableColumn``
- ``TableColumnChange``
- ``TableFormattingChange``
- ``TableRowFormattingChange``
- ``TableCellFormattingChange``
- ``CellMergeChange``
- ``TableWidth``
- ``ContentControl``
- ``ContentControlDescriptor``
- ``ContentControlRange``
- ``ContentBinding``
- ``ContentControlItem``
- ``VerticalMerge``
- ``Story``
- ``StoryKind``
- ``Section``
- ``PageOrientation``
- ``DocumentMetadata``
- ``PackagePart``

### Codecs

- ``CodecSet``
- ``Codec``
- ``DocumentCodec``
- ``DOCXCodec``
- ``ODTCodec``
- ``PagesCodec``
- ``MarkdownCodec``

### Guides

- <doc:Reading>
- <doc:Cookbook>
