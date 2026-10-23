import Foundation

/// A content-detected document format.
public enum DocumentFormat: String, Sendable, Codable, CaseIterable {
    case docx, docm, odt, pages, markdown
    /// Standard extension; independent of codec availability and content detection.
    public var fileExtension: String { self == .markdown ? "md" : rawValue }
    /// Recognize a standard extension case-insensitively, without opening a file.
    public init?(fileExtension: String) { self.init(rawValue: fileExtension.lowercased() == "md" ? "markdown" : fileExtension.lowercased()) }
    /// The independent codec product associated with this format.
    public var productName: String {
        switch self { case .docx, .docm: "DocumentDOCX"; case .odt: "DocumentODT"; case .pages: "DocumentPages"; case .markdown: "DocumentMarkdown" }
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
    /// Field definitions for body, included related stories and text boxes; cached content stays in local fragments.
    public var fieldDefinitions: [FieldDefinition] = []
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
    /// Non-body source content retained with unsupported-content warnings.
    public var uninterpretedContent: [UnsupportedContent] = []
    /// Source font records; the same name may occur with different legacy charsets.
    public var fonts: [DocumentFont] = []
    public var theme: DocumentTheme?
    private var assetStore: PackageArchive?
    private var sourceLimits = PackageLimits()
    package var parsingLimits: PackageLimits { sourceLimits }

    public init() {}
    package mutating func attach(_ archive: PackageArchive, limits: PackageLimits = .init()) { assetStore = archive; sourceLimits = limits }
    /// Inflate the requested original package part and validate CRC. External URLs are never fetched.
    public func asset(at path: String) throws -> Data {
        try assetSync(at: path)
    }
    /// Inflate and CRC-check an original part on the generic executor.
    @concurrent public func asset(at path: String) async throws -> Data {
        try assetSync(at: path)
    }
    private func assetSync(at path: String) throws -> Data {
        try Task.checkCancellation()
        guard let assetStore else { throw DocumentError.missingPart(path) }
        let data = try assetStore.read(path)
        try Task.checkCancellation()
        return data
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
    case contentControl(ContentControl)
    case unsupported(UnsupportedContent)
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String {
        switch self { case .paragraph(let p): p.plainText; case .table(let t): t.plainText; case .contentControl(let value): value.plainText; case .unsupported(let u): u.text }
    }
    /// All body paragraphs in document order, recursively including nested table cells.
    public var paragraphs: [Paragraph] {
        switch self { case .paragraph(let p): [p]; case .table(let t): t.rows.flatMap { $0.cells.filter { !$0.isCovered }.flatMap { $0.blocks.flatMap(\.paragraphs) } }; case .contentControl(let value): value.paragraphs; case .unsupported: [] }
    }
    /// All body tables, recursively including nested tables.
    public var tables: [Table] {
        switch self { case .table(let t): [t] + t.rows.flatMap { $0.cells.filter { !$0.isCovered }.flatMap { $0.blocks.flatMap(\.tables) } }; case .contentControl(let value): value.tables; default: [] }
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
    /// Resolved default text properties, including for an empty paragraph.
    public var defaultTextFormatting = TextFormatting()
    /// Resolved typography of the paragraph-ending character, separate from body runs.
    public var paragraphMarkFormatting: TextFormatting?
    public var paragraphMarkFormattingChange: TextFormattingChange?
    /// The source numbering instance and level, if present.
    public var list: ListReference?
    public var paragraphMarkRevisions: [Revision] = []
    /// The first ending-character annotation. Assignment replaces the annotation list.
    public var paragraphMarkRevision: Revision? {
        get { paragraphMarkRevisions.first }
        set { paragraphMarkRevisions = newValue.map { [$0] } ?? [] }
    }
    public var formattingChange: ParagraphFormattingChange?
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
    case drawing(DocumentDrawing)
    case ruby(RubyText)
    case equation(Equation)
    case contentControl(ContentControl)
    case noteReference(NoteReference)
    case bookmark(Bookmark)
    case commentReference(CommentReference)
    case unsupported(UnsupportedContent)
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String {
        switch self {
        case .text(let r): r.text
        case .drawing(let drawing): drawing.root.plainText
        case .ruby(let ruby): ruby.base.map(\.plainText).joined()
        case .equation(let equation): equation.lexicalText
        case .contentControl(let value): value.plainText
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
        switch self { case .text(let r): [r]; case .hyperlink(let h): h.inlines.flatMap(\.runs); case .field(let f): f.result.flatMap(\.runs); case .ruby(let ruby): ruby.base.flatMap(\.runs); case .contentControl(let value): value.runs; default: [] }
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
    public var symbol: SymbolCharacter?
    public var formattingChange: TextFormattingChange?
    public init(_ text: String, formatting: TextFormatting = .init(), styleID: String? = nil, revision: Revision? = nil) {
        self.text = text; self.formatting = formatting; self.styleID = styleID; self.revision = revision
    }
}
/// Resolved run formatting. Optional fields preserve absent versus explicitly false values; measurements are in points.
public struct TextFormatting: Sendable, Equatable {
    private struct Value: Sendable, Equatable {
        var bold: Bool?
        var italic: Bool?
        var strike: Bool?
        var hidden: Bool?
        var allCaps: Bool?
        var smallCaps: Bool?
        var underline: String?
        var fontName: String?
        var fontNameEastAsia: String?
        var fontNameComplexScript: String?
        var fontTheme: String?
        var fontThemeEastAsia: String?
        var fontThemeComplexScript: String?
        var fontHint: String?
        var emphasis: String?
        var textScale: Double?
        var position: Double?
        var fontSize: Double?
        var fontSizeComplexScript: Double?
        var boldComplexScript: Bool?
        var italicComplexScript: Bool?
        var color: String?
        var themeColor: String?
        var themeTint: String?
        var themeShade: String?
        var highlight: String?
        var verticalAlignment: TextVerticalAlignment?
        var language: String?
        var languageEastAsia: String?
        var languageComplexScript: String?
        var characterSpacing: Double?
        var kerning: Double?
        var rightToLeft: Bool?
        var rawProperties: [String] = []
        mutating func merge(_ other: Self, toggling: Bool = false) {
            func flag(_ base: Bool?, _ next: Bool?) -> Bool? {
                guard let next else { return base }
                return toggling ? (next ? !(base ?? false) : base) : next
            }
            bold = flag(bold, other.bold); italic = flag(italic, other.italic)
            strike = flag(strike, other.strike); hidden = flag(hidden, other.hidden)
            allCaps = flag(allCaps, other.allCaps); smallCaps = flag(smallCaps, other.smallCaps)
            boldComplexScript = flag(boldComplexScript, other.boldComplexScript); italicComplexScript = flag(italicComplexScript, other.italicComplexScript)
            underline = other.underline ?? underline
            if other.fontName != nil || other.fontTheme != nil { fontName = other.fontName; fontTheme = other.fontTheme }
            if other.fontNameEastAsia != nil || other.fontThemeEastAsia != nil { fontNameEastAsia = other.fontNameEastAsia; fontThemeEastAsia = other.fontThemeEastAsia }
            if other.fontNameComplexScript != nil || other.fontThemeComplexScript != nil { fontNameComplexScript = other.fontNameComplexScript; fontThemeComplexScript = other.fontThemeComplexScript }
            fontNameEastAsia = other.fontNameEastAsia ?? fontNameEastAsia; fontTheme = other.fontTheme ?? fontTheme
            fontNameComplexScript = other.fontNameComplexScript ?? fontNameComplexScript
            fontThemeEastAsia = other.fontThemeEastAsia ?? fontThemeEastAsia; fontThemeComplexScript = other.fontThemeComplexScript ?? fontThemeComplexScript
            fontHint = other.fontHint ?? fontHint; emphasis = other.emphasis ?? emphasis
            textScale = other.textScale ?? textScale; position = other.position ?? position
            fontSize = other.fontSize ?? fontSize
            fontSizeComplexScript = other.fontSizeComplexScript ?? fontSizeComplexScript
            if other.color != nil || other.themeColor != nil { color = other.color; themeColor = other.themeColor; themeTint = other.themeTint; themeShade = other.themeShade }
            highlight = other.highlight ?? highlight; verticalAlignment = other.verticalAlignment ?? verticalAlignment
            language = other.language ?? language; rightToLeft = other.rightToLeft ?? rightToLeft
            languageEastAsia = other.languageEastAsia ?? languageEastAsia; languageComplexScript = other.languageComplexScript ?? languageComplexScript
            characterSpacing = other.characterSpacing ?? characterSpacing; kerning = other.kerning ?? kerning
            rawProperties += other.rawProperties
        }
    }
    // The reference never escapes. All mutations, including array _modify access,
    // first copy shared storage; the static default therefore remains immutable.
    private final class Storage: @unchecked Sendable {
        var value: Value
        init(_ value: Value = Value()) { self.value = value }
    }
    private static let empty = Storage()
    private var storage: Storage = empty
    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(storage.value) }
    }
    public var bold: Bool? {
        get { storage.value.bold }
        set { makeUnique(); storage.value.bold = newValue }
        _modify { makeUnique(); yield &storage.value.bold }
    }
    public var italic: Bool? {
        get { storage.value.italic }
        set { makeUnique(); storage.value.italic = newValue }
        _modify { makeUnique(); yield &storage.value.italic }
    }
    public var strike: Bool? {
        get { storage.value.strike }
        set { makeUnique(); storage.value.strike = newValue }
        _modify { makeUnique(); yield &storage.value.strike }
    }
    public var hidden: Bool? {
        get { storage.value.hidden }
        set { makeUnique(); storage.value.hidden = newValue }
        _modify { makeUnique(); yield &storage.value.hidden }
    }
    public var allCaps: Bool? {
        get { storage.value.allCaps }
        set { makeUnique(); storage.value.allCaps = newValue }
        _modify { makeUnique(); yield &storage.value.allCaps }
    }
    public var smallCaps: Bool? {
        get { storage.value.smallCaps }
        set { makeUnique(); storage.value.smallCaps = newValue }
        _modify { makeUnique(); yield &storage.value.smallCaps }
    }
    /// Source underline style value.
    public var underline: String? {
        get { storage.value.underline }
        set { makeUnique(); storage.value.underline = newValue }
        _modify { makeUnique(); yield &storage.value.underline }
    }
    /// Latin / general font name.
    public var fontName: String? {
        get { storage.value.fontName }
        set { makeUnique(); storage.value.fontName = newValue }
        _modify { makeUnique(); yield &storage.value.fontName }
    }
    /// East Asian font name.
    public var fontNameEastAsia: String? {
        get { storage.value.fontNameEastAsia }
        set { makeUnique(); storage.value.fontNameEastAsia = newValue }
        _modify { makeUnique(); yield &storage.value.fontNameEastAsia }
    }
    /// Complex-script font name.
    public var fontNameComplexScript: String? {
        get { storage.value.fontNameComplexScript }
        set { makeUnique(); storage.value.fontNameComplexScript = newValue }
        _modify { makeUnique(); yield &storage.value.fontNameComplexScript }
    }
    /// Source font theme reference; not resolved to an installed font.
    public var fontTheme: String? {
        get { storage.value.fontTheme }
        set { makeUnique(); storage.value.fontTheme = newValue }
        _modify { makeUnique(); yield &storage.value.fontTheme }
    }
    public var fontThemeEastAsia: String? {
        get { storage.value.fontThemeEastAsia }
        set { makeUnique(); storage.value.fontThemeEastAsia = newValue }
        _modify { makeUnique(); yield &storage.value.fontThemeEastAsia }
    }
    public var fontThemeComplexScript: String? {
        get { storage.value.fontThemeComplexScript }
        set { makeUnique(); storage.value.fontThemeComplexScript = newValue }
        _modify { makeUnique(); yield &storage.value.fontThemeComplexScript }
    }
    public var fontHint: String? {
        get { storage.value.fontHint }
        set { makeUnique(); storage.value.fontHint = newValue }
        _modify { makeUnique(); yield &storage.value.fontHint }
    }
    public var emphasis: String? {
        get { storage.value.emphasis }
        set { makeUnique(); storage.value.emphasis = newValue }
        _modify { makeUnique(); yield &storage.value.emphasis }
    }
    public var textScale: Double? {
        get { storage.value.textScale }
        set { makeUnique(); storage.value.textScale = newValue }
        _modify { makeUnique(); yield &storage.value.textScale }
    }
    public var position: Double? {
        get { storage.value.position }
        set { makeUnique(); storage.value.position = newValue }
        _modify { makeUnique(); yield &storage.value.position }
    }
    /// Font size in points.
    public var fontSize: Double? {
        get { storage.value.fontSize }
        set { makeUnique(); storage.value.fontSize = newValue }
        _modify { makeUnique(); yield &storage.value.fontSize }
    }
    /// Complex-script font size in points.
    public var fontSizeComplexScript: Double? {
        get { storage.value.fontSizeComplexScript }
        set { makeUnique(); storage.value.fontSizeComplexScript = newValue }
        _modify { makeUnique(); yield &storage.value.fontSizeComplexScript }
    }
    public var boldComplexScript: Bool? {
        get { storage.value.boldComplexScript }
        set { makeUnique(); storage.value.boldComplexScript = newValue }
        _modify { makeUnique(); yield &storage.value.boldComplexScript }
    }
    public var italicComplexScript: Bool? {
        get { storage.value.italicComplexScript }
        set { makeUnique(); storage.value.italicComplexScript = newValue }
        _modify { makeUnique(); yield &storage.value.italicComplexScript }
    }
    /// Resolved RGB color, cached source color or automatic-color value.
    public var color: String? {
        get { storage.value.color }
        set { makeUnique(); storage.value.color = newValue }
        _modify { makeUnique(); yield &storage.value.color }
    }
    /// Source hexadecimal luminance tint byte, retained after resolution.
    public var themeTint: String? {
        get { storage.value.themeTint }
        set { makeUnique(); storage.value.themeTint = newValue }
    }
    /// Source hexadecimal luminance shade byte, retained after resolution.
    public var themeShade: String? {
        get { storage.value.themeShade }
        set { makeUnique(); storage.value.themeShade = newValue }
    }
    /// Source theme color reference.
    public var themeColor: String? {
        get { storage.value.themeColor }
        set { makeUnique(); storage.value.themeColor = newValue }
        _modify { makeUnique(); yield &storage.value.themeColor }
    }
    /// Source highlight color name.
    public var highlight: String? {
        get { storage.value.highlight }
        set { makeUnique(); storage.value.highlight = newValue }
        _modify { makeUnique(); yield &storage.value.highlight }
    }
    /// Source vertical alignment for this content.
    public var verticalAlignment: TextVerticalAlignment? {
        get { storage.value.verticalAlignment }
        set { makeUnique(); storage.value.verticalAlignment = newValue }
        _modify { makeUnique(); yield &storage.value.verticalAlignment }
    }
    public var language: String? {
        get { storage.value.language }
        set { makeUnique(); storage.value.language = newValue }
        _modify { makeUnique(); yield &storage.value.language }
    }
    public var languageEastAsia: String? {
        get { storage.value.languageEastAsia }
        set { makeUnique(); storage.value.languageEastAsia = newValue }
        _modify { makeUnique(); yield &storage.value.languageEastAsia }
    }
    public var languageComplexScript: String? {
        get { storage.value.languageComplexScript }
        set { makeUnique(); storage.value.languageComplexScript = newValue }
        _modify { makeUnique(); yield &storage.value.languageComplexScript }
    }
    /// Additional character spacing in points.
    public var characterSpacing: Double? {
        get { storage.value.characterSpacing }
        set { makeUnique(); storage.value.characterSpacing = newValue }
        _modify { makeUnique(); yield &storage.value.characterSpacing }
    }
    /// Minimum font size in points at which kerning applies.
    public var kerning: Double? {
        get { storage.value.kerning }
        set { makeUnique(); storage.value.kerning = newValue }
        _modify { makeUnique(); yield &storage.value.kerning }
    }
    public var rightToLeft: Bool? {
        get { storage.value.rightToLeft }
        set { makeUnique(); storage.value.rightToLeft = newValue }
        _modify { makeUnique(); yield &storage.value.rightToLeft }
    }
    /// Uninterpreted properties as namespace-preserving reconstructed XML, not original bytes.
    public var rawProperties: [String] {
        get { storage.value.rawProperties }
        set { makeUnique(); storage.value.rawProperties = newValue }
        _modify { makeUnique(); yield &storage.value.rawProperties }
    }
    public init() {}
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage || lhs.storage.value == rhs.storage.value
    }
    public mutating func merge(_ other: Self, toggling: Bool = false) {
        guard other.storage !== Self.empty else { return }
        if !toggling && storage === Self.empty { storage = other.storage; return }
        makeUnique()
        storage.value.merge(other.storage.value, toggling: toggling)
    }
}
/// Paragraph formatting with point measurements, except multiple line spacing, which is a ratio.
public struct ParagraphFormatting: Sendable, Equatable {
    private struct Value: Sendable, Equatable {
        var alignment: ParagraphAlignment?
        var spacingBefore: Double?
        var spacingAfter: Double?
        var lineSpacing: Double?
        var lineSpacingRule: LineSpacingRule?
        var indentLeft: Double?
        var indentRight: Double?
        var firstLineIndent: Double?
        var keepWithNext: Bool?
        var keepTogether: Bool?
        var pageBreakBefore: Bool?
        var rightToLeft: Bool?
        var outlineLevel: Int?
        var widowControl: Bool?
        var contextualSpacing: Bool?
        var suppressAutoHyphens: Bool?
        var tabs: [TabStop]? = nil
        var wordWrap: Bool?
        var kinsoku: Bool?
        var autoSpaceEastAsianLatin: Bool?
        var autoSpaceEastAsianNumbers: Bool?
        var textDirection: String?
        var snapToGrid: Bool?
        var rawProperties: [String] = []
        mutating func merge(_ f: Self) {
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
            tabs = f.tabs ?? tabs; wordWrap = f.wordWrap ?? wordWrap; kinsoku = f.kinsoku ?? kinsoku
            autoSpaceEastAsianLatin = f.autoSpaceEastAsianLatin ?? autoSpaceEastAsianLatin
            autoSpaceEastAsianNumbers = f.autoSpaceEastAsianNumbers ?? autoSpaceEastAsianNumbers
            textDirection = f.textDirection ?? textDirection; snapToGrid = f.snapToGrid ?? snapToGrid
        }
    }
    // The reference never escapes. All mutations, including array _modify access,
    // first copy shared storage; the static default therefore remains immutable.
    private final class Storage: @unchecked Sendable {
        var value: Value
        init(_ value: Value = Value()) { self.value = value }
    }
    private static let empty = Storage()
    private var storage: Storage = empty
    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(storage.value) }
    }
    public var alignment: ParagraphAlignment? {
        get { storage.value.alignment }
        set { makeUnique(); storage.value.alignment = newValue }
        _modify { makeUnique(); yield &storage.value.alignment }
    }
    /// Space before the paragraph in points.
    public var spacingBefore: Double? {
        get { storage.value.spacingBefore }
        set { makeUnique(); storage.value.spacingBefore = newValue }
        _modify { makeUnique(); yield &storage.value.spacingBefore }
    }
    /// Space after the paragraph in points.
    public var spacingAfter: Double? {
        get { storage.value.spacingAfter }
        set { makeUnique(); storage.value.spacingAfter = newValue }
        _modify { makeUnique(); yield &storage.value.spacingAfter }
    }
    /// Line-height ratio for multiple spacing, or points for exact / at-least spacing.
    public var lineSpacing: Double? {
        get { storage.value.lineSpacing }
        set { makeUnique(); storage.value.lineSpacing = newValue }
        _modify { makeUnique(); yield &storage.value.lineSpacing }
    }
    /// Units and minimum / exact behavior of line spacing.
    public var lineSpacingRule: LineSpacingRule? {
        get { storage.value.lineSpacingRule }
        set { makeUnique(); storage.value.lineSpacingRule = newValue }
        _modify { makeUnique(); yield &storage.value.lineSpacingRule }
    }
    /// Leading indentation in points.
    public var indentLeft: Double? {
        get { storage.value.indentLeft }
        set { makeUnique(); storage.value.indentLeft = newValue }
        _modify { makeUnique(); yield &storage.value.indentLeft }
    }
    /// Trailing indentation in points.
    public var indentRight: Double? {
        get { storage.value.indentRight }
        set { makeUnique(); storage.value.indentRight = newValue }
        _modify { makeUnique(); yield &storage.value.indentRight }
    }
    /// First-line indentation in points; negative values represent hanging indentation.
    public var firstLineIndent: Double? {
        get { storage.value.firstLineIndent }
        set { makeUnique(); storage.value.firstLineIndent = newValue }
        _modify { makeUnique(); yield &storage.value.firstLineIndent }
    }
    public var keepWithNext: Bool? {
        get { storage.value.keepWithNext }
        set { makeUnique(); storage.value.keepWithNext = newValue }
        _modify { makeUnique(); yield &storage.value.keepWithNext }
    }
    public var keepTogether: Bool? {
        get { storage.value.keepTogether }
        set { makeUnique(); storage.value.keepTogether = newValue }
        _modify { makeUnique(); yield &storage.value.keepTogether }
    }
    public var pageBreakBefore: Bool? {
        get { storage.value.pageBreakBefore }
        set { makeUnique(); storage.value.pageBreakBefore = newValue }
        _modify { makeUnique(); yield &storage.value.pageBreakBefore }
    }
    public var rightToLeft: Bool? {
        get { storage.value.rightToLeft }
        set { makeUnique(); storage.value.rightToLeft = newValue }
        _modify { makeUnique(); yield &storage.value.rightToLeft }
    }
    /// Zero-based source outline level.
    public var outlineLevel: Int? {
        get { storage.value.outlineLevel }
        set { makeUnique(); storage.value.outlineLevel = newValue }
        _modify { makeUnique(); yield &storage.value.outlineLevel }
    }
    public var widowControl: Bool? {
        get { storage.value.widowControl }
        set { makeUnique(); storage.value.widowControl = newValue }
        _modify { makeUnique(); yield &storage.value.widowControl }
    }
    public var contextualSpacing: Bool? {
        get { storage.value.contextualSpacing }
        set { makeUnique(); storage.value.contextualSpacing = newValue }
        _modify { makeUnique(); yield &storage.value.contextualSpacing }
    }
    public var suppressAutoHyphens: Bool? {
        get { storage.value.suppressAutoHyphens }
        set { makeUnique(); storage.value.suppressAutoHyphens = newValue }
        _modify { makeUnique(); yield &storage.value.suppressAutoHyphens }
    }
    public var tabs: [TabStop]? {
        get { storage.value.tabs }
        set { makeUnique(); storage.value.tabs = newValue }
        _modify { makeUnique(); yield &storage.value.tabs }
    }
    public var wordWrap: Bool? {
        get { storage.value.wordWrap }
        set { makeUnique(); storage.value.wordWrap = newValue }
        _modify { makeUnique(); yield &storage.value.wordWrap }
    }
    public var kinsoku: Bool? {
        get { storage.value.kinsoku }
        set { makeUnique(); storage.value.kinsoku = newValue }
        _modify { makeUnique(); yield &storage.value.kinsoku }
    }
    public var autoSpaceEastAsianLatin: Bool? {
        get { storage.value.autoSpaceEastAsianLatin }
        set { makeUnique(); storage.value.autoSpaceEastAsianLatin = newValue }
        _modify { makeUnique(); yield &storage.value.autoSpaceEastAsianLatin }
    }
    public var autoSpaceEastAsianNumbers: Bool? {
        get { storage.value.autoSpaceEastAsianNumbers }
        set { makeUnique(); storage.value.autoSpaceEastAsianNumbers = newValue }
        _modify { makeUnique(); yield &storage.value.autoSpaceEastAsianNumbers }
    }
    public var textDirection: String? {
        get { storage.value.textDirection }
        set { makeUnique(); storage.value.textDirection = newValue }
        _modify { makeUnique(); yield &storage.value.textDirection }
    }
    public var snapToGrid: Bool? {
        get { storage.value.snapToGrid }
        set { makeUnique(); storage.value.snapToGrid = newValue }
        _modify { makeUnique(); yield &storage.value.snapToGrid }
    }
    /// Uninterpreted properties as namespace-preserving reconstructed XML, not original bytes.
    public var rawProperties: [String] {
        get { storage.value.rawProperties }
        set { makeUnique(); storage.value.rawProperties = newValue }
        _modify { makeUnique(); yield &storage.value.rawProperties }
    }
    public init() {}
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage || lhs.storage.value == rhs.storage.value
    }
    public mutating func merge(_ other: Self) {
        guard other.storage !== Self.empty else { return }
        if storage === Self.empty { storage = other.storage; return }
        makeUnique()
        storage.value.merge(other.storage.value)
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
    /// Whole-table and conditional formatting declarations in source order.
    public var tableRules: [TableStyleRule] = []
    public var rowBandSize: Int?
    public var columnBandSize: Int?
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
    /// The source numbering format, such as decimal, bullet or lowerLetter.
    public var format: String
    /// The retained text or source text representation.
    public var text: String
    /// Paragraph properties declared by this style or numbering level.
    public var paragraph: ParagraphFormatting
    /// Resolved formatting for this content.
    public var formatting: TextFormatting
    /// Source numbering restart level; nil when absent.
    public var restartAfterLevel: Int?
    public var suffix: String = "tab"
    public var isLegal: Bool = false
    /// Original picture marker; source bytes are obtained through the owning document's assets.
    public var picture: DocumentImage?
    public var pictureAssetPath: String? { picture?.assetPath }
    public var rawProperties: [String] = []
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
    public var formattingChange: TableFormattingChange?
    public var rowControls: [ContentControlRange] = []
    public var preferredWidth: TableWidth?
    public var alignment: TableAlignment?
    public var layout: TableLayout?
    public var indentation: TableWidth?
    public var cellSpacing: TableWidth?
    public var rightToLeft: Bool?
    public var shading: String?
    public var borders: [TableBorderEdge: TableBorder] = [:]
    public var cellMargins: [TableCellEdge: TableWidth] = [:]
    /// Physical rows in source order.
    public var rows: [TableRow] = []
    public var columns: [TableColumn] = []
    public var columnChange: TableColumnChange?
    /// Compatibility projection of known source widths; columns retains unspecified widths too.
    public var columnWidths: [Double] {
        get { columns.compactMap(\.width) }
        set { columns = newValue.map { TableColumn(width: $0) } }
    }
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
    public var revisions: [Revision] = []
    public var formattingChange: TableRowFormattingChange?
    /// Table-level declarations that apply only to this physical row.
    public var tableOverrides: TableFormatting?
    public var tableOverridesChange: TableFormattingChange?
    public var cellControls: [ContentControlRange] = []
    /// Physical cells in source order.
    public var cells: [TableCell] = []
    /// Whether this row is marked as a repeated header.
    public var isHeader = false
    /// Height in points, if specified.
    public var height: Double?
    public var heightRule: TableRowHeightRule?
    public var preventSplit: Bool?
    public var omittedLeadingColumns = 0
    public var omittedTrailingColumns = 0
    public var leadingWidth: TableWidth?
    public var trailingWidth: TableWidth?
    /// Uninterpreted source properties as reconstructed XML.
    public var properties: [String] = []
    public init() {}
}
/// A physical table cell. Span and merge metadata do not fabricate virtual cells.
public struct TableCell: Sendable {
    public var revisions: [Revision] = []
    public var formattingChange: TableCellFormattingChange?
    public var mergeChange: CellMergeChange?
    /// Ordered blocks in this body. A scan result retains no main-body blocks.
    public var blocks: [Block] = []
    /// Number of grid columns spanned; defaults to one.
    public var columnSpan = 1
    /// Number of source rows spanned by an ODF anchor cell; defaults to one.
    public var rowSpan = 1
    /// An explicit covered source cell. Its content is retained but excluded from display traversal.
    public var isCovered = false
    /// Whether this cell starts or continues a vertical merge.
    public var verticalMerge: VerticalMerge?
    public var preferredWidth: TableWidth?
    /// Legacy source projection. Use preferredWidth for normalized points or percentages.
    public var width: Double? {
        guard let preferredWidth else { return nil }
        return preferredWidth.unit == .points ? preferredWidth.value : preferredWidth.sourceValue.flatMap(Double.init)
    }
    /// Original width encoding, such as dxa/pct; preferredWidth.unit is format-neutral.
    public var widthUnit: String? { preferredWidth.map { $0.sourceUnit ?? "dxa" } }
    /// Source vertical alignment for this content.
    public var verticalAlignment: String?
    /// Source cell fill color.
    public var shading: String?
    public var borders: [TableBorderEdge: TableBorder] = [:]
    public var margins: [TableCellEdge: TableWidth] = [:]
    public var textDirection: String?
    public var noWrap: Bool?
    public var fitText: Bool?
    /// Uninterpreted source properties as reconstructed XML.
    public var properties: [String] = []
    public init() {}
    /// Text projection of this content. Related stories are separate; cells use tabs and rows use newlines.
    public var plainText: String { isCovered ? "" : blocks.map(\.plainText).joined(separator: "\n") }
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
    /// Instruction text local to this fragment; use its definition for the complete instruction. Never evaluated.
    public var instruction: String
    /// Cached display inlines stored by the producer.
    public var result: [Inline]
    /// Whether the source marks the field as locked.
    public var isLocked: Bool
    /// Ordered instruction-side content, including nested fields; excluded from display text and runs.
    public var codeContent: [Inline] = []
    /// Local boundaries and the definition ID; nil for a field constructed without source fragments.
    public var fragment: FieldFragment?
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
    public var drawing: DocumentDrawing?
    /// Attribution for the enclosing insertion, deletion or move of this image.
    public var revision: Revision?
    public var contentType: String?
    public var fallbackAssetPath: String?
    public var fallbackExternalURL: String?
    public var crop: ImageCrop?
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
    public enum Kind: String, Sendable { case insertion, deletion, moveFrom, moveTo, formatting }
    private final class Storage: Sendable {
        let id: String
        let kind: Kind
        let author: String?
        let date: String?
        let attributes: [String: String]
        init(id: String, kind: Kind, author: String?, date: String?, attributes: [String: String]) {
            self.id = id; self.kind = kind; self.author = author; self.date = date; self.attributes = attributes
        }
    }
    private var storage: Storage
    /// Source identifier used to resolve references.
    public var id: String {
        get { storage.id }
        set { storage = Storage(id: newValue, kind: kind, author: author, date: date, attributes: sourceAttributes) }
    }
    /// The source kind of this value.
    public var kind: Kind {
        get { storage.kind }
        set { storage = Storage(id: id, kind: newValue, author: author, date: date, attributes: sourceAttributes) }
    }
    /// Source author metadata, if present.
    public var author: String? {
        get { storage.author }
        set { storage = Storage(id: id, kind: kind, author: newValue, date: date, attributes: sourceAttributes) }
    }
    /// Source date string, retained without normalization.
    public var date: String? {
        get { storage.date }
        set { storage = Storage(id: id, kind: kind, author: author, date: newValue, attributes: sourceAttributes) }
    }
    /// Original attributes, including extensions; typed edits do not rewrite this source snapshot.
    public var sourceAttributes: [String: String] {
        get { storage.attributes }
        set { storage = Storage(id: id, kind: kind, author: author, date: date, attributes: newValue) }
    }
    public init(id: String, kind: Kind, author: String? = nil, date: String? = nil, sourceAttributes: [String: String] = [:]) {
        storage = Storage(id: id, kind: kind, author: author, date: date, attributes: sourceAttributes)
    }
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
    private struct Value: Sendable {
        var pageWidth: Double?
        var pageHeight: Double?
        var orientation: PageOrientation?
        var margins: [String: Double] = [:]
        var columnCount: Int = 1
        var columns: [SectionColumn] = []
        var equalColumnWidths: Bool?
        var columnSpacing: Double?
        var columnSeparator: Bool?
        var textDirection: String?
        var documentGrid: [String: String] = [:]
        var breakKind: String?
        var hasDifferentFirstPage: Bool = false
        var headers: [String: String] = [:]
        var footers: [String: String] = [:]
        var rawProperties: [String] = []
    }
    // Only value-semantic access escapes; mutations always detach shared storage.
    private final class Storage: @unchecked Sendable {
        var value: Value
        init(_ value: Value = Value()) { self.value = value }
    }
    private static let empty = Storage()
    private var storage: Storage = empty
    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(storage.value) }
    }
    /// Section page width in points.
    public var pageWidth: Double? {
        get { storage.value.pageWidth }
        set { makeUnique(); storage.value.pageWidth = newValue }
        _modify { makeUnique(); yield &storage.value.pageWidth }
    }
    /// Section page height in points.
    public var pageHeight: Double? {
        get { storage.value.pageHeight }
        set { makeUnique(); storage.value.pageHeight = newValue }
        _modify { makeUnique(); yield &storage.value.pageHeight }
    }
    /// Section page orientation, if specified.
    public var orientation: PageOrientation? {
        get { storage.value.orientation }
        set { makeUnique(); storage.value.orientation = newValue }
        _modify { makeUnique(); yield &storage.value.orientation }
    }
    /// Source page margins keyed by local name, in points.
    public var margins: [String: Double] {
        get { storage.value.margins }
        set { makeUnique(); storage.value.margins = newValue }
        _modify { makeUnique(); yield &storage.value.margins }
    }
    /// Declared section column count; defaults to one.
    public var columnCount: Int {
        get { storage.value.columnCount }
        set { makeUnique(); storage.value.columnCount = newValue }
        _modify { makeUnique(); yield &storage.value.columnCount }
    }
    public var columns: [SectionColumn] {
        get { storage.value.columns }
        set { makeUnique(); storage.value.columns = newValue }
        _modify { makeUnique(); yield &storage.value.columns }
    }
    public var equalColumnWidths: Bool? {
        get { storage.value.equalColumnWidths }
        set { makeUnique(); storage.value.equalColumnWidths = newValue }
        _modify { makeUnique(); yield &storage.value.equalColumnWidths }
    }
    public var columnSpacing: Double? {
        get { storage.value.columnSpacing }
        set { makeUnique(); storage.value.columnSpacing = newValue }
        _modify { makeUnique(); yield &storage.value.columnSpacing }
    }
    public var columnSeparator: Bool? {
        get { storage.value.columnSeparator }
        set { makeUnique(); storage.value.columnSeparator = newValue }
        _modify { makeUnique(); yield &storage.value.columnSeparator }
    }
    public var textDirection: String? {
        get { storage.value.textDirection }
        set { makeUnique(); storage.value.textDirection = newValue }
        _modify { makeUnique(); yield &storage.value.textDirection }
    }
    public var documentGrid: [String: String] {
        get { storage.value.documentGrid }
        set { makeUnique(); storage.value.documentGrid = newValue }
        _modify { makeUnique(); yield &storage.value.documentGrid }
    }
    /// Source section-break type.
    public var breakKind: String? {
        get { storage.value.breakKind }
        set { makeUnique(); storage.value.breakKind = newValue }
        _modify { makeUnique(); yield &storage.value.breakKind }
    }
    /// Whether the section declares distinct first-page headers / footers.
    public var hasDifferentFirstPage: Bool {
        get { storage.value.hasDifferentFirstPage }
        set { makeUnique(); storage.value.hasDifferentFirstPage = newValue }
        _modify { makeUnique(); yield &storage.value.hasDifferentFirstPage }
    }
    /// Header type (default / first / even) to resolved package part path.
    public var headers: [String: String] {
        get { storage.value.headers }
        set { makeUnique(); storage.value.headers = newValue }
        _modify { makeUnique(); yield &storage.value.headers }
    }
    /// Footer type (default / first / even) to resolved package part path.
    public var footers: [String: String] {
        get { storage.value.footers }
        set { makeUnique(); storage.value.footers = newValue }
        _modify { makeUnique(); yield &storage.value.footers }
    }
    /// Uninterpreted properties as namespace-preserving reconstructed XML, not original bytes.
    public var rawProperties: [String] {
        get { storage.value.rawProperties }
        set { makeUnique(); storage.value.rawProperties = newValue }
        _modify { makeUnique(); yield &storage.value.rawProperties }
    }
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
