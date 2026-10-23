# Word, Writer and Pages: shared design

```mermaid
flowchart LR
    A[Caller: Document / CodecSet] --> B[DocumentCore: value model]
    B --> C[DocumentDOCX: OPC / WordprocessingML]
    B --> D[DocumentODT: ODF content / styles]
    B --> E[DocumentPages: IWA / object graph]
```

## Shared semantics

Share document meaning: ordered `Block`s, `Paragraph`s, formatted text and references in `Inline`, physical cells in `Table`, styles, numbering definitions, independent `Story` regions and `Section`s. `DocumentImage` records references and placement. Shared type names do not encode Word-specific XML names.

Measurements use points; color fields retain RGB strings and theme references. `LineSpacingRule` distinguishes multiples from point values. Unresolved format-specific settings remain in `rawProperties` with source parts. Content outside the model remains recoverable through `UnsupportedContent` and warnings.

## Codec boundary

`DocumentCodec` read / inspect / scan share one result contract. `CodecSet` selects linked codecs without Word rules; umbrella convenience APIs use `CodecSet.all`. Core has no Word parser dependency, allowing ODT-only or Pages-only configurations.

| Concept | Word | LibreOffice Writer | Pages design mapping |
|---|---|---|---|
| Body | document part / body | content.xml / office:text | TSWP storage text and paragraph ranges |
| Formatting | pPr / rPr / basedOn | paragraph / text styles and automatic styles | stylesheet / character / paragraph style archives |
| Tables | tbl / tr / tc, gridSpan / vMerge | table, covered-table-cell | TST TableInfo / TableModel and cell storage |
| Headers | section references to story parts | master page header / footer | storage tied to sections / section templates |
| Images / positioning | DrawingML / VML | draw:frame | drawable objects; distinguish inline attachment from canvas |
| Numbering | abstractNum / num / lvlOverride | list-style and list instances | list styles and paragraph list metadata |

ODT and Pages implement the subsets recorded in implementation-spec.md; the table also records future extension points.

## Adding Writer

ODF MIME detection already exists. `DocumentODT` resolves common / automatic styles in content.xml and styles.xml, then maps text, paragraphs and tables; unsupported list/page-style details remain diagnosed source data. Preserve frame attachment versus free positioning rather than flattening frames into paragraph text. Reading must not require launching Office or converting a document with another app.

## Adding Pages

Pages is not a publicly specified XML format. Interpret Snappy / Protobuf IWA records and object references in a separate internal layer. The codec validates root type 10000 (TP.DocumentArchive), follows its body reference and resolves UTF-16 text/style boundaries. Point attachments resolve isolated inline tables and images, including table tile/string/rich-text storage and metadata-backed lazy image resources. Positioned content and advanced object semantics remain opaque with warnings. Numbers / Keynote sharing the Index/Document.iwa filename are rejected. Legacy iWork, Index.zip and folder packages are outside detection support.

Synthetic fixtures verify text, basic formatting, range boundaries and referenced headers/footers. The fictional Pages Creator Studio 15.4 import/save fixture additionally verifies Japanese/emoji text, a 3×2 table and a generated image. The sanitized fixture was reopened in Pages to check its display; producer evidence is limited to that path. Layout documents need an explicit positioned-content model. `UnsupportedContent` is the recovery path until such semantics are implemented.

Sources:

- [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376/): Word packages, content and compatibility.
- [OASIS ODF 1.3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/): Writer XML specification.
- [iWorkFileFormat](https://github.com/obriensp/iWorkFileFormat): IWA analysis and Protobuf descriptions.
- [python-pages investigation](https://github.com/isoparametric/python-pages/blob/main/REPORT.md): TP.DocumentArchive and storage analysis.

## Before writing support

Current APIs are read-only. A writer requires a separate preservation contract for relationship IDs, style IDs and opaque parts. Conversions should combine reading warnings and writing losses in one result, following SwiftSheets' approach.
