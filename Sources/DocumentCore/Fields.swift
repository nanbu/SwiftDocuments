import Foundation

/// A field's source metadata, separate from its potentially multi-block cached display.
public struct FieldDefinition: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable { case simple, complex }
    /// Operation-local identity shared by all fragments of this field.
    public var id: String
    /// Enclosing field identity, including nesting on the instruction side.
    public var parentID: String?
    public var kind: Kind
    public var sourcePart: String
    /// Complete explicit instruction text; nested fields are retained separately, never evaluated.
    public var instruction: String
    /// Source state; nil means absent or uninterpreted.
    public var isLocked: Bool?
    public var isDirty: Bool?
    public var hasSeparator: Bool
    /// Whether the source supplied the closing boundary; incomplete fields are also diagnosed.
    public var isComplete: Bool
    /// Original opening marker or simple-field header, excluding cached body content.
    public var source: SourceXMLNode?
    public init(id: String, parentID: String? = nil, kind: Kind = .complex, sourcePart: String,
                instruction: String = "", isLocked: Bool? = nil, isDirty: Bool? = nil,
                hasSeparator: Bool = false, isComplete: Bool = false, source: SourceXMLNode? = nil) {
        self.id = id; self.parentID = parentID; self.kind = kind; self.sourcePart = sourcePart
        self.instruction = instruction; self.isLocked = isLocked; self.isDirty = isDirty
        self.hasSeparator = hasSeparator; self.isComplete = isComplete; self.source = source
    }
}

/// Source boundaries present in one immutable local field fragment.
public struct FieldFragment: Sendable, Equatable, Codable {
    public var definitionID: String
    public var startsHere: Bool
    public var endsHere: Bool
    public var containsSeparator: Bool
    public init(definitionID: String, startsHere: Bool = false, endsHere: Bool = false, containsSeparator: Bool = false) {
        self.definitionID = definitionID; self.startsHere = startsHere; self.endsHere = endsHere
        self.containsSeparator = containsSeparator
    }
}
