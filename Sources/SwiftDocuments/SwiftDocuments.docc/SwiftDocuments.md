# ``SwiftDocuments``

Read Word documents through a format-neutral, Sendable value model.

## Overview

SwiftDocuments is in development. It reads DOCX and DOCM with no external Swift package dependencies. ODT and Pages currently have format detection and an extension design, but no reading codec. Writing, conversion, decryption and layout are not implemented. APIs may change before a stable release.

```swift
import Foundation
import SwiftDocuments

let result = try Document.read(contentsOf: URL(filePath: "report.docx"))
print(result.document.plainText)
print(result.warnings)
```

The umbrella re-exports `DocumentCore` and `DocumentDOCX`. Select only Word through `CodecSet([.docx, .docm])` when linking those products directly. Read operations are synchronous; the caller selects the task or thread. Unsupported content is recoverable through warnings, raw XML and original package parts.

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

### Body and inline content

- ``Block``
- ``Paragraph``
- ``Inline``
- ``TextRun``
- ``BreakKind``
- ``Hyperlink``
- ``Field``
- ``DocumentImage``
- ``NoteReference``
- ``Bookmark``
- ``CommentReference``
- ``Revision``
- ``UnsupportedContent``

### Formatting and lists

- ``TextFormatting``
- ``ParagraphFormatting``
- ``ParagraphAlignment``
- ``LineSpacingRule``
- ``TextVerticalAlignment``
- ``DocumentStyle``
- ``ListReference``
- ``NumberingDefinition``
- ``NumberingLevel``

### Tables and related stories

- ``Table``
- ``TableRow``
- ``TableCell``
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

### Guides

- <doc:Reading>
- <doc:Cookbook>
