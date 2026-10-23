import Foundation

/// A cached structured-content region. Interactive behavior and data binding are caller-owned.
public struct ContentControl: Sendable {
    public enum Kind: String, Sendable {
        case richText, plainText, picture, date, checkBox, comboBox, dropDownList, group
        case repeatingSection, repeatingItem, citation, bibliography, equation, documentPart
    }
    public enum EditingLock: String, Sendable { case unlocked, content, control, contentAndControl, native }
    public indirect enum Content: Sendable {
        case blocks([Block]), inlines([Inline])
    }
    public var descriptor: ContentControlDescriptor
    public var content: Content
    public init(descriptor: ContentControlDescriptor = .init(), content: Content) { self.descriptor = descriptor; self.content = content }
    public var plainText: String {
        switch content {
        case .blocks(let values): values.map(\.plainText).joined(separator: "\n")
        case .inlines(let values): values.map(\.plainText).joined()
        }
    }
    public var paragraphs: [Paragraph] {
        switch content {
        case .blocks(let values): values.flatMap(\.paragraphs)
        case .inlines: []
        }
    }
    public var tables: [Table] {
        switch content {
        case .blocks(let values): values.flatMap(\.tables)
        case .inlines: []
        }
    }
    public var runs: [TextRun] {
        if case .inlines(let values) = content { return values.flatMap(\.runs) }
        return paragraphs.flatMap(\.runs)
    }
}
/// Source metadata shared by body/inline controls and controls over physical table ranges.
public struct ContentControlDescriptor: Sendable {
    public var kind: ContentControl.Kind = .richText
    public var id: String?
    public var title: String?
    public var tag: String?
    public var editingLock: ContentControl.EditingLock?
    public var isTemporary: Bool?
    public var isShowingPlaceholder: Bool?
    public var placeholderName: String?
    public var isMultiline: Bool?
    public var binding: ContentBinding?
    public var items: [ContentControlItem] = []
    public var selectedValue: String?
    public var dateValue: String?
    public var dateFormat: String?
    public var dateLanguage: String?
    public var dateCalendar: String?
    public var isChecked: Bool?
    /// Explicit source symbols, never substituted for the cached content by the reader.
    public var checkedSymbol: SymbolCharacter?
    public var uncheckedSymbol: SymbolCharacter?
    public var formatting: TextFormatting?
    public var endFormatting: TextFormatting?
    public var sourcePart: String
    /// Normalized source header, including attributes and properties, with cached content omitted.
    public var sourceHeader: SourceXMLNode?
    public init(sourcePart: String = "") { self.sourcePart = sourcePart }
}
public struct ContentBinding: Sendable, Equatable {
    public var storeID: String?
    public var pathQuery: String?
    public var namespaceMappings: String?
    public init(storeID: String? = nil, pathQuery: String? = nil, namespaceMappings: String? = nil) {
        self.storeID = storeID; self.pathQuery = pathQuery; self.namespaceMappings = namespaceMappings
    }
}
public struct ContentControlItem: Sendable, Equatable {
    public var displayText: String?
    public var value: String?
    public init(displayText: String? = nil, value: String? = nil) { self.displayText = displayText; self.value = value }
}
/// A control over physical row/cell indices in its owning table/row, preserving source order.
public struct ContentControlRange: Sendable {
    public var range: Range<Int>
    public var descriptor: ContentControlDescriptor
    public init(range: Range<Int>, descriptor: ContentControlDescriptor) { self.range = range; self.descriptor = descriptor }
}
