import Foundation

/// A content-detected document format; ODT and Pages currently have no reading codec.
public enum DocumentFormat: String, Sendable, Codable, CaseIterable {
    case docx, docm, odt, pages
    /// The codec product associated with this format; planned products may not exist yet.
    public var productName: String {
        switch self { case .docx, .docm: "DocumentDOCX"; case .odt: "DocumentODT"; case .pages: "DocumentPages" }
    }
}

/// A format-neutral document value with body content, related stories and lazy package assets.
public struct Document: Sendable {
    /// Ordered blocks in this body. A scan result retains no main-body blocks.
    public var blocks: [Block] = []
    /// Metadata read from core, extended and custom package properties.
    public var metadata = DocumentMetadata()
    /// Source styles keyed by style identifier.
    public var styles: [String: DocumentStyle] = [:]
    /// Effective numbering instances keyed by source identifier.
    public var numbering: [String: NumberingDefinition] = [:]
    /// Section properties, including inherited header and footer references.
    public var sections: [Section] = []
    /// Headers, footers, notes and comments, separate from body text.
    public var stories: [Story] = []
    /// Aggregated warnings produced while reading the source.
    public var readWarnings: [ReadWarning] = []
    /// The detected format, or nil for a newly constructed value.
    public var sourceFormat: DocumentFormat?
    /// The original package inventory, including opaque parts.
    public var packageParts: [PackagePart] = []
    /// Source settings keyed by local element name, stored as reconstructed XML.
    public var settings: [String: String] = [:]
    private var assetStore: PackageArchive?

    public init() {}
    package mutating func attach(_ archive: PackageArchive) { assetStore = archive }
    /// Inflate the requested original package part and validate CRC. External URLs are never fetched.
    public func asset(at path: String) throws -> Data {
        guard let assetStore else { throw DocumentError.missingPart(path) }
        return try assetStore.read(path)
    }
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String { blocks.map(\.plainText).joined(separator: "\n") }
    /// All body paragraphs in document order, including nested table cells.
    public var paragraphs: [Paragraph] { blocks.flatMap(\.paragraphs) }
    /// All body tables, recursively including nested tables.
    public var tables: [Table] { blocks.flatMap(\.tables) }
}

/// An ordered body block: paragraph, table or recoverable uninterpreted content.
public indirect enum Block: Sendable {
    case paragraph(Paragraph)
    case table(Table)
    case unsupported(UnsupportedContent)
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String {
        switch self { case .paragraph(let p): p.plainText; case .table(let t): t.plainText; case .unsupported(let u): u.text }
    }
    /// All body paragraphs in document order, recursively including nested table cells.
    public var paragraphs: [Paragraph] {
        switch self { case .paragraph(let p): [p]; case .table(let t): t.rows.flatMap { $0.cells.flatMap { $0.blocks.flatMap(\.paragraphs) } }; case .unsupported: [] }
    }
    /// All body tables, recursively including nested tables.
    public var tables: [Table] {
        switch self { case .table(let t): [t] + t.rows.flatMap { $0.cells.flatMap { $0.blocks.flatMap(\.tables) } }; default: [] }
    }
}

/// A paragraph with ordered inline content and resolved formatting.
public struct Paragraph: Sendable {
    /// Ordered inline content.
    public var inlines: [Inline] = []
    /// The source style identifier, if present.
    public var styleID: String?
    /// Resolved formatting for this content.
    public var formatting = ParagraphFormatting()
    /// The source numbering instance and level, if present.
    public var list: ListReference?
    /// Section properties attached to this paragraph, if present.
    public var sectionBreak: Section?
    public init() {}
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String { inlines.map(\.plainText).joined() }
    /// Text runs recursively flattened through hyperlinks and cached field results.
    public var runs: [TextRun] { inlines.flatMap(\.runs) }
}

/// Text, control characters, references or recoverable content inside a paragraph.
public indirect enum Inline: Sendable {
    case text(TextRun)
    case tab
    case lineBreak(BreakKind)
    case hyperlink(Hyperlink)
    case field(Field)
    case image(DocumentImage)
    case noteReference(NoteReference)
    case bookmark(Bookmark)
    case commentReference(CommentReference)
    case unsupported(UnsupportedContent)
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String {
        switch self {
        case .text(let r): r.text
        case .tab: "\t"
        case .lineBreak(let b): b == .page ? "\u{000C}" : "\n"
        case .hyperlink(let h): h.inlines.map(\.plainText).joined()
        case .field(let f): f.result.map(\.plainText).joined()
        case .unsupported(let u): u.text
        default: ""
        }
    }
    /// Text runs recursively flattened through hyperlinks and cached field results.
    public var runs: [TextRun] {
        switch self { case .text(let r): [r]; case .hyperlink(let h): h.inlines.flatMap(\.runs); case .field(let f): f.result.flatMap(\.runs); default: [] }
    }
}

/// A line, page or column break. Plain text uses form feed for page breaks and newline otherwise.
public enum BreakKind: String, Sendable, Codable { case line, page, column }
/// A text run with resolved formatting and optional source style and revision.
public struct TextRun: Sendable {
    /// The retained text or source text representation.
    public var text: String
    /// The source style identifier, if present.
    public var styleID: String?
    /// Resolved formatting for this content.
    public var formatting: TextFormatting
    /// Source revision metadata, if present.
    public var revision: Revision?
    public init(_ text: String, formatting: TextFormatting = .init(), styleID: String? = nil, revision: Revision? = nil) {
        self.text = text; self.formatting = formatting; self.styleID = styleID; self.revision = revision
    }
}
/// Resolved run formatting. Optional fields preserve absent versus explicitly false values; measurements are in points.
public struct TextFormatting: Sendable, Equatable {
    public var bold: Bool?
    public var italic: Bool?
    public var strike: Bool?
    public var hidden: Bool?
    public var allCaps: Bool?
    public var smallCaps: Bool?
    /// Source underline style value.
    public var underline: String?
    /// Latin / general font name.
    public var fontName: String?
    /// East Asian font name.
    public var fontNameEastAsia: String?
    /// Complex-script font name.
    public var fontNameComplexScript: String?
    /// Source font theme reference; not resolved to an installed font.
    public var fontTheme: String?
    /// Font size in points.
    public var fontSize: Double?
    /// Complex-script font size in points.
    public var fontSizeComplexScript: Double?
    public var boldComplexScript: Bool?
    public var italicComplexScript: Bool?
    /// Source RGB color or automatic-color value; theme tint is not fully resolved.
    public var color: String?
    /// Source theme color reference.
    public var themeColor: String?
    /// Source highlight color name.
    public var highlight: String?
    /// Source vertical alignment for this content.
    public var verticalAlignment: TextVerticalAlignment?
    public var language: String?
    public var languageEastAsia: String?
    public var languageComplexScript: String?
    /// Additional character spacing in points.
    public var characterSpacing: Double?
    /// Minimum font size in points at which kerning applies.
    public var kerning: Double?
    public var rightToLeft: Bool?
    /// Uninterpreted properties as namespace-preserving reconstructed XML, not original bytes.
    public var rawProperties: [String] = []
    public init() {}
    public mutating func merge(_ other: Self, toggling: Bool = false) {
        func flag(_ base: Bool?, _ next: Bool?) -> Bool? {
            guard let next else { return base }
            return toggling ? (next ? !(base ?? false) : base) : next
        }
        bold = flag(bold, other.bold); italic = flag(italic, other.italic)
        strike = flag(strike, other.strike); hidden = flag(hidden, other.hidden)
        allCaps = flag(allCaps, other.allCaps); smallCaps = flag(smallCaps, other.smallCaps)
        boldComplexScript = flag(boldComplexScript, other.boldComplexScript); italicComplexScript = flag(italicComplexScript, other.italicComplexScript)
        underline = other.underline ?? underline; fontName = other.fontName ?? fontName
        fontNameEastAsia = other.fontNameEastAsia ?? fontNameEastAsia; fontTheme = other.fontTheme ?? fontTheme
        fontNameComplexScript = other.fontNameComplexScript ?? fontNameComplexScript
        fontSize = other.fontSize ?? fontSize
        fontSizeComplexScript = other.fontSizeComplexScript ?? fontSizeComplexScript
        if other.color != nil || other.themeColor != nil { color = other.color; themeColor = other.themeColor }
        highlight = other.highlight ?? highlight; verticalAlignment = other.verticalAlignment ?? verticalAlignment
        language = other.language ?? language; rightToLeft = other.rightToLeft ?? rightToLeft
        languageEastAsia = other.languageEastAsia ?? languageEastAsia; languageComplexScript = other.languageComplexScript ?? languageComplexScript
        characterSpacing = other.characterSpacing ?? characterSpacing; kerning = other.kerning ?? kerning
        rawProperties += other.rawProperties
    }
}
/// Paragraph formatting with point measurements, except multiple line spacing, which is a ratio.
public struct ParagraphFormatting: Sendable, Equatable {
    public var alignment: ParagraphAlignment?
    /// Space before the paragraph in points.
    public var spacingBefore: Double?
    /// Space after the paragraph in points.
    public var spacingAfter: Double?
    /// Line-height ratio for multiple spacing, or points for exact / at-least spacing.
    public var lineSpacing: Double?
    /// Units and minimum / exact behavior of line spacing.
    public var lineSpacingRule: LineSpacingRule?
    /// Leading indentation in points.
    public var indentLeft: Double?
    /// Trailing indentation in points.
    public var indentRight: Double?
    /// First-line indentation in points; negative values represent hanging indentation.
    public var firstLineIndent: Double?
    public var keepWithNext: Bool?
    public var keepTogether: Bool?
    public var pageBreakBefore: Bool?
    public var rightToLeft: Bool?
    /// Zero-based source outline level.
    public var outlineLevel: Int?
    public var widowControl: Bool?
    public var contextualSpacing: Bool?
    public var suppressAutoHyphens: Bool?
    /// Uninterpreted properties as namespace-preserving reconstructed XML, not original bytes.
    public var rawProperties: [String] = []
    public init() {}
    public mutating func merge(_ f: Self) {
        alignment = f.alignment ?? alignment; spacingBefore = f.spacingBefore ?? spacingBefore
        spacingAfter = f.spacingAfter ?? spacingAfter; lineSpacing = f.lineSpacing ?? lineSpacing
        lineSpacingRule = f.lineSpacingRule ?? lineSpacingRule
        indentLeft = f.indentLeft ?? indentLeft; indentRight = f.indentRight ?? indentRight
        firstLineIndent = f.firstLineIndent ?? firstLineIndent
        keepWithNext = f.keepWithNext ?? keepWithNext; keepTogether = f.keepTogether ?? keepTogether
        pageBreakBefore = f.pageBreakBefore ?? pageBreakBefore; rightToLeft = f.rightToLeft ?? rightToLeft
        outlineLevel = f.outlineLevel ?? outlineLevel; rawProperties += f.rawProperties
        widowControl = f.widowControl ?? widowControl; contextualSpacing = f.contextualSpacing ?? contextualSpacing
        suppressAutoHyphens = f.suppressAutoHyphens ?? suppressAutoHyphens
    }
}
/// Paragraph alignment values, retaining Word-specific alignment variants.
public enum ParagraphAlignment: String, Sendable, Codable {
    case left, center, right, start, end, distributed = "distribute", justified = "both"
    case thaiDistributed = "thaiDistribute", kashidaLow = "lowKashida", kashidaMedium = "mediumKashida", kashidaHigh = "highKashida", numericTab = "numTab"
}
/// Multiple spacing is a ratio; exact and at-least spacing are measured in points.
public enum LineSpacingRule: String, Sendable, Codable { case multiple = "auto", exact, atLeast }
/// Baseline, superscript or subscript positioning.
public enum TextVerticalAlignment: String, Sendable, Codable { case baseline, superscript, `subscript` }
/// Portrait or landscape section orientation.
public enum PageOrientation: String, Sendable, Codable { case portrait, landscape }
/// A source style definition with its inheritance reference and own properties.
public struct DocumentStyle: Sendable {
    /// Source identifier used to resolve references.
    public var id: String
    /// Source name, if provided.
    public var name: String
    /// The source kind of this value.
    public var kind: String
    /// Identifier of the source parent style, if any.
    public var basedOn: String?
    /// Whether the source marks this as the default style of its kind.
    public var isDefault: Bool
    /// Paragraph properties declared by this style or numbering level.
    public var paragraph: ParagraphFormatting
    /// Run properties declared by this style.
    public var text: TextFormatting
    /// The source numbering instance and level, if present.
    public var list: ListReference?
    public init(id: String, name: String, kind: String, basedOn: String? = nil, isDefault: Bool = false, paragraph: ParagraphFormatting = .init(), text: TextFormatting = .init(), list: ListReference? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.basedOn = basedOn; self.isDefault = isDefault
        self.paragraph = paragraph; self.text = text; self.list = list
    }
}
/// A source numbering-instance identifier and zero-based level.
public struct ListReference: Sendable, Equatable {
    /// Source identifier used to resolve references.
    public var id: String
    /// Zero-based list level.
    public var level: Int
    public init(id: String, level: Int = 0) { self.id = id; self.level = level }
}
/// A numbering-level definition. Display strings are retained, not evaluated.
public struct NumberingLevel: Sendable {
    /// Zero-based list level.
    public var level: Int
    /// Starting number declared for this level.
    public var start: Int
    /// The format identifier or source numbering format, according to this type.
    public var format: String
    /// The retained text or source text representation.
    public var text: String
    /// Paragraph properties declared by this style or numbering level.
    public var paragraph: ParagraphFormatting
    /// Resolved formatting for this content.
    public var formatting: TextFormatting
    /// Source numbering restart level; nil when absent.
    public var restartAfterLevel: Int?
    public init(level: Int, start: Int = 1, format: String = "decimal", text: String = "%1.", paragraph: ParagraphFormatting = .init(), formatting: TextFormatting = .init(), restartAfterLevel: Int? = nil) {
        self.level = level; self.start = start; self.format = format; self.text = text
        self.paragraph = paragraph; self.formatting = formatting; self.restartAfterLevel = restartAfterLevel
    }
}
/// A numbering instance linked to its abstract definition and effective levels.
public struct NumberingDefinition: Sendable {
    /// Source identifier used to resolve references.
    public var id: String
    /// Identifier of the abstract numbering definition.
    public var abstractID: String
    /// Effective numbering definitions keyed by zero-based level.
    public var levels: [Int: NumberingLevel]
    public init(id: String, abstractID: String, levels: [Int: NumberingLevel]) { self.id = id; self.abstractID = abstractID; self.levels = levels }
}

/// Physical rows and cells, including nested blocks and source properties.
public struct Table: Sendable {
    /// Physical rows in source order.
    public var rows: [TableRow] = []
    /// Source grid column widths in points.
    public var columnWidths: [Double] = []
    /// The source style identifier, if present.
    public var styleID: String?
    /// Uninterpreted source properties as reconstructed XML.
    public var properties: [String] = []
    public init() {}
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String { rows.map { $0.cells.map(\.plainText).joined(separator: "\t") }.joined(separator: "\n") }
}
/// A physical table row with header, height and uninterpreted properties.
public struct TableRow: Sendable {
    /// Physical cells in source order.
    public var cells: [TableCell] = []
    /// Whether this row is marked as a repeated header.
    public var isHeader = false
    /// Height in points, if specified.
    public var height: Double?
    /// Uninterpreted source properties as reconstructed XML.
    public var properties: [String] = []
    public init() {}
}
/// A physical table cell. Span and merge metadata do not fabricate virtual cells.
public struct TableCell: Sendable {
    /// Ordered blocks in this body. A scan result retains no main-body blocks.
    public var blocks: [Block] = []
    /// Number of grid columns spanned; defaults to one.
    public var columnSpan = 1
    /// Whether this cell starts or continues a vertical merge.
    public var verticalMerge: VerticalMerge?
    /// Width in points for dxa; otherwise the source numeric value with widthUnit.
    public var width: Double?
    /// Source width unit, such as dxa or pct. Percentage values retain fiftieths of a percent.
    public var widthUnit: String?
    /// Source vertical alignment for this content.
    public var verticalAlignment: String?
    /// Source cell fill color.
    public var shading: String?
    /// Uninterpreted source properties as reconstructed XML.
    public var properties: [String] = []
    public init() {}
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String { blocks.map(\.plainText).joined(separator: "\n") }
}
/// Starts a vertically merged region or continues the preceding region.
public enum VerticalMerge: String, Sendable { case restart, continuation }

/// Link contents and a target URL or bookmark anchor. Targets are never fetched.
public struct Hyperlink: Sendable {
    /// External or internal link target, retained without fetching.
    public var target: String?
    /// Source bookmark anchor, if present.
    public var anchor: String?
    /// Source hyperlink tooltip, if present.
    public var tooltip: String?
    /// Ordered inline content.
    public var inlines: [Inline]
    public init(target: String? = nil, anchor: String? = nil, tooltip: String? = nil, inlines: [Inline]) {
        self.target = target; self.anchor = anchor; self.tooltip = tooltip; self.inlines = inlines
    }
}
/// A field instruction and cached display inlines; instructions are never evaluated.
public struct Field: Sendable {
    /// The source field instruction; it is not evaluated.
    public var instruction: String
    /// Cached display inlines stored by the producer.
    public var result: [Inline]
    /// Whether the source marks the field as locked.
    public var isLocked: Bool
    public init(instruction: String, result: [Inline], isLocked: Bool = false) { self.instruction = instruction; self.result = result; self.isLocked = isLocked }
}
/// An embedded asset or external image reference with placement and size in points.
public struct DocumentImage: Sendable {
    /// Internal package path for an embedded asset, if present.
    public var assetPath: String?
    /// External image URL, retained without fetching.
    public var externalURL: String?
    /// Source name, if provided.
    public var name: String?
    /// Image description provided by the producer.
    public var alternativeText: String?
    /// Image width in points, if specified.
    public var width: Double?
    /// Height in points, if specified.
    public var height: Double?
    /// Whether source placement is floating rather than inline.
    public var isFloating: Bool
    /// Namespace-preserving reconstructed source XML; byte identity is not guaranteed.
    public var rawXML: String
    public init(assetPath: String? = nil, externalURL: String? = nil, name: String? = nil, alternativeText: String? = nil, width: Double? = nil, height: Double? = nil, isFloating: Bool = false, rawXML: String = "") {
        self.assetPath = assetPath; self.externalURL = externalURL; self.name = name; self.alternativeText = alternativeText
        self.width = width; self.height = height; self.isFloating = isFloating; self.rawXML = rawXML
    }
}
/// A footnote or endnote identifier resolved against related stories.
public struct NoteReference: Sendable {
    /// Source identifier used to resolve references.
    public var id: String
    /// The source kind of this value.
    public var kind: StoryKind
    public init(id: String, kind: StoryKind) { self.id = id; self.kind = kind }
}
/// A bookmark range boundary identified by a source ID.
public struct Bookmark: Sendable {
    /// Source identifier used to resolve references.
    public var id: String
    /// Source name, if provided.
    public var name: String?
    /// Whether this marker opens its bookmark range.
    public var isStart: Bool
    public init(id: String, name: String? = nil, isStart: Bool) { self.id = id; self.name = name; self.isStart = isStart }
}
/// A comment range or reference marker resolved against comment stories.
public struct CommentReference: Sendable {
    public enum Boundary: String, Sendable { case start, end, reference }
    /// Source identifier used to resolve references.
    public var id: String
    /// The start, end or reference marker for a comment.
    public var boundary: Boundary
    public init(id: String, boundary: Boundary) { self.id = id; self.boundary = boundary }
}
/// Source insertion, deletion or move metadata attached to retained runs.
public struct Revision: Sendable {
    public enum Kind: String, Sendable { case insertion, deletion, moveFrom, moveTo }
    /// Source identifier used to resolve references.
    public var id: String
    /// The source kind of this value.
    public var kind: Kind
    /// Source author metadata, if present.
    public var author: String?
    /// Source date string, retained without normalization.
    public var date: String?
    public init(id: String, kind: Kind, author: String? = nil, date: String? = nil) { self.id = id; self.kind = kind; self.author = author; self.date = date }
}
/// Recoverable content outside the typed model, including reconstructed XML and its source part.
public struct UnsupportedContent: Sendable {
    /// Source name, if provided.
    public var name: String
    /// Package part from which this content was read.
    public var sourcePart: String
    /// Namespace-preserving reconstructed source XML; byte identity is not guaranteed.
    public var rawXML: String
    /// The retained text or source text representation.
    public var text: String
    public init(name: String, sourcePart: String, rawXML: String, text: String = "") { self.name = name; self.sourcePart = sourcePart; self.rawXML = rawXML; self.text = text }
}

/// A related body region kept separate from the main document body.
public enum StoryKind: String, Sendable { case header, footer, footnote, endnote, comment }
/// A header, footer, note or comment body with its source identity and blocks.
public struct Story: Sendable {
    /// Source identifier used to resolve references.
    public var id: String
    /// The source kind of this value.
    public var kind: StoryKind
    /// Package part from which this content was read.
    public var sourcePart: String
    /// Ordered blocks in this body. A scan result retains no main-body blocks.
    public var blocks: [Block]
    /// Source author metadata, if present.
    public var author: String?
    /// Source date string, retained without normalization.
    public var date: String?
    /// Source story type; nil for ordinary notes, distinct values for separators.
    public var type: String?
    public init(id: String, kind: StoryKind, sourcePart: String, blocks: [Block], author: String? = nil, date: String? = nil, type: String? = nil) {
        self.id = id; self.kind = kind; self.sourcePart = sourcePart; self.blocks = blocks; self.author = author; self.date = date; self.type = type
    }
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String { blocks.map(\.plainText).joined(separator: "\n") }
}
/// Section page geometry and inherited header / footer references; no layout is computed.
public struct Section: Sendable {
    /// Section page width in points.
    public var pageWidth: Double?
    /// Section page height in points.
    public var pageHeight: Double?
    /// Section page orientation, if specified.
    public var orientation: PageOrientation?
    /// Source page margins keyed by local name, in points.
    public var margins: [String: Double] = [:]
    /// Declared section column count; defaults to one.
    public var columnCount = 1
    /// Source section-break type.
    public var breakKind: String?
    /// Whether the section declares distinct first-page headers / footers.
    public var hasDifferentFirstPage = false
    /// Header type (default / first / even) to resolved package part path.
    public var headers: [String: String] = [:]
    /// Footer type (default / first / even) to resolved package part path.
    public var footers: [String: String] = [:]
    /// Uninterpreted properties as namespace-preserving reconstructed XML, not original bytes.
    public var rawProperties: [String] = []
    public init() {}
}
/// Core, extended and custom package metadata; declared counts are producer values.
public struct DocumentMetadata: Sendable, Codable {
    public var title: String?
    public var subject: String?
    public var creator: String?
    public var lastModifiedBy: String?
    public var description: String?
    public var keywords: String?
    public var created: String?
    public var modified: String?
    public var application: String?
    /// Page count declared by the producer, not computed by this library.
    public var declaredPages: Int?
    /// Word count declared by the producer, not computed by this library.
    public var declaredWords: Int?
    /// Custom source metadata stored as string values.
    public var custom: [String: String] = [:]
    public init() {}
}
/// Package inventory entry; sizes are declared compressed and expanded byte counts.
public struct PackagePart: Sendable, Codable {
    /// Internal package part path.
    public var path: String
    /// Declared content type, if available.
    public var contentType: String?
    /// Declared compressed byte count.
    public var compressedSize: Int
    /// Declared expanded byte count.
    public var expandedSize: Int
    public init(path: String, contentType: String? = nil, compressedSize: Int, expandedSize: Int) {
        self.path = path; self.contentType = contentType; self.compressedSize = compressedSize; self.expandedSize = expandedSize
    }
}
