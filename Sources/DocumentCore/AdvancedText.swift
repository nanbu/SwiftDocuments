import Foundation

/// An explicitly font-encoded source symbol. Display substitution belongs to the renderer.
public struct SymbolCharacter: Sendable, Equatable {
    public var fontName: String
    public var characterCode: UInt32
    public init(fontName: String, characterCode: UInt32) {
        self.fontName = fontName; self.characterCode = characterCode
    }
}

/// Ruby annotation (furigana). Base text contributes to plainText; annotation remains separately accessible.
public struct RubyText: Sendable {
    public var base: [Inline]
    public var annotation: [Inline]
    public var alignment: String?
    /// Source annotation position, such as above/below, when explicitly declared.
    public var position: String?
    public var annotationSize: Double?
    public var baseSize: Double?
    public var language: String?
    public var rawProperties: [String] = []
    public init(base: [Inline], annotation: [Inline]) { self.base = base; self.annotation = annotation }
}
public struct TabStop: Sendable, Equatable {
    public var position: Double
    public var alignment: String
    public var leader: String?
    public init(position: Double, alignment: String = "left", leader: String? = nil) { self.position = position; self.alignment = alignment; self.leader = leader }
}
public struct SectionColumn: Sendable, Equatable {
    public var width: Double?
    public var spacingAfter: Double?
    public init(width: Double? = nil, spacingAfter: Double? = nil) { self.width = width; self.spacingAfter = spacingAfter }
}
/// Font metadata and optional obfuscated embedded-font assets; loading/registration is explicitly caller-owned.
public struct DocumentFont: Sendable {
    public var name: String
    public var alternateName: String?
    public var family: String?
    public var charset: String?
    public var pitch: String?
    public var panose: String?
    public var embeddedFaces: [EmbeddedFont] = []
    public init(name: String) { self.name = name }
}
public struct EmbeddedFont: Sendable {
    public var assetPath: String
    public var key: String?
    public var face: String
    public var isSubset: Bool
    public init(assetPath: String, key: String? = nil, face: String = "regular", isSubset: Bool = false) { self.assetPath = assetPath; self.key = key; self.face = face; self.isSubset = isSubset }
}
/// Font and color theme defaults plus script-specific font substitutions.
public struct DocumentTheme: Sendable {
    public var colors: [String: String] = [:]
    public var majorFonts: [String: String] = [:]
    public var minorFonts: [String: String] = [:]
    public init() {}
}
