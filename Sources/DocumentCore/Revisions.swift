import Foundation

/// An immutable previous-formatting snapshot with independent mutable value semantics.
public struct FormattingChange<Value: Sendable>: Sendable {
    private final class Storage: Sendable {
        let revision: Revision
        let previous: Value
        let source: SourceXMLNode?
        init(revision: Revision, previous: Value, source: SourceXMLNode?) { self.revision = revision; self.previous = previous; self.source = source }
    }
    private var storage: Storage
    public var revision: Revision {
        get { storage.revision }
        set { storage = Storage(revision: newValue, previous: previous, source: source) }
    }
    public var previous: Value {
        get { storage.previous }
        set { storage = Storage(revision: revision, previous: newValue, source: source) }
    }
    public var source: SourceXMLNode? {
        get { storage.source }
        set { storage = Storage(revision: revision, previous: previous, source: newValue) }
    }
    public init(revision: Revision, previous: Value, source: SourceXMLNode? = nil) { storage = Storage(revision: revision, previous: previous, source: source) }
}
public typealias TextFormattingChange = FormattingChange<TextFormatting>
public typealias ParagraphFormattingChange = FormattingChange<ParagraphFormatting>
public typealias TableFormattingChange = FormattingChange<TableFormatting>
public typealias TableRowFormattingChange = FormattingChange<TableRowFormatting>
public typealias TableCellFormattingChange = FormattingChange<TableCellFormatting>
public typealias TableColumnChange = FormattingChange<[TableColumn]>

public struct TableColumn: Sendable {
    public var width: Double?
    public var sourceWidth: String?
    public var rawProperties: [String] = []
    public init(width: Double? = nil, sourceWidth: String? = nil) { self.width = width; self.sourceWidth = sourceWidth }
}

public struct TableFormatting: Sendable {
    public var styleID: String?
    public var preferredWidth: TableWidth?
    public var alignment: TableAlignment?
    public var layout: TableLayout?
    public var indentation: TableWidth?
    public var cellSpacing: TableWidth?
    public var rightToLeft: Bool?
    public var shading: String?
    public var borders: [TableBorderEdge: TableBorder] = [:]
    public var cellMargins: [TableCellEdge: TableWidth] = [:]
    public var rawProperties: [String] = []
    public init() {}
}
public enum TableRowHeightRule: String, Sendable { case automatic, exact, minimum }
public struct TableRowFormatting: Sendable {
    public var isHeader = false
    public var height: Double?
    public var heightRule: TableRowHeightRule?
    public var preventSplit: Bool?
    public var omittedLeadingColumns = 0
    public var omittedTrailingColumns = 0
    public var leadingWidth: TableWidth?
    public var trailingWidth: TableWidth?
    public var rawProperties: [String] = []
    public init() {}
}
public struct TableCellFormatting: Sendable {
    public var columnSpan = 1
    public var rowSpan = 1
    public var isCovered = false
    public var verticalMerge: VerticalMerge?
    public var preferredWidth: TableWidth?
    public var verticalAlignment: String?
    public var shading: String?
    public var borders: [TableBorderEdge: TableBorder] = [:]
    public var margins: [TableCellEdge: TableWidth] = [:]
    public var textDirection: String?
    public var noWrap: Bool?
    public var fitText: Bool?
    public var rawProperties: [String] = []
    public init() {}
}
/// A recorded merge/split of this cell with the preceding physical row.
public struct CellMergeChange: Sendable {
    private final class Storage: Sendable {
        let revision: Revision
        let previous: Bool
        let current: Bool
        let source: SourceXMLNode?
        init(revision: Revision, previous: Bool, current: Bool, source: SourceXMLNode?) {
            self.revision = revision; self.previous = previous; self.current = current; self.source = source
        }
    }
    private var storage: Storage
    public var revision: Revision {
        get { storage.revision }
        set { storage = Storage(revision: newValue, previous: wasMergedWithPrevious, current: isMergedWithPrevious, source: source) }
    }
    public var wasMergedWithPrevious: Bool {
        get { storage.previous }
        set { storage = Storage(revision: revision, previous: newValue, current: isMergedWithPrevious, source: source) }
    }
    public var isMergedWithPrevious: Bool {
        get { storage.current }
        set { storage = Storage(revision: revision, previous: wasMergedWithPrevious, current: newValue, source: source) }
    }
    public var source: SourceXMLNode? {
        get { storage.source }
        set { storage = Storage(revision: revision, previous: wasMergedWithPrevious, current: isMergedWithPrevious, source: newValue) }
    }
    public init(revision: Revision, wasMergedWithPrevious: Bool, isMergedWithPrevious: Bool, source: SourceXMLNode? = nil) {
        storage = Storage(revision: revision, previous: wasMergedWithPrevious, current: isMergedWithPrevious, source: source)
    }
}

extension Table {
    public var formatting: TableFormatting {
        get {
            var result = TableFormatting(); result.styleID = styleID; result.preferredWidth = preferredWidth
            result.alignment = alignment; result.layout = layout; result.indentation = indentation
            result.cellSpacing = cellSpacing; result.rightToLeft = rightToLeft; result.shading = shading
            result.borders = borders; result.cellMargins = cellMargins; result.rawProperties = properties; return result
        }
        set {
            styleID = newValue.styleID; preferredWidth = newValue.preferredWidth; properties = newValue.rawProperties
            alignment = newValue.alignment; layout = newValue.layout; indentation = newValue.indentation
            cellSpacing = newValue.cellSpacing; rightToLeft = newValue.rightToLeft; shading = newValue.shading
            borders = newValue.borders; cellMargins = newValue.cellMargins
        }
    }
}
extension TableRow {
    public var formatting: TableRowFormatting {
        get {
            var result = TableRowFormatting(); result.isHeader = isHeader; result.height = height; result.heightRule = heightRule
            result.preventSplit = preventSplit; result.omittedLeadingColumns = omittedLeadingColumns; result.omittedTrailingColumns = omittedTrailingColumns
            result.leadingWidth = leadingWidth; result.trailingWidth = trailingWidth
            result.rawProperties = properties; return result
        }
        set {
            isHeader = newValue.isHeader; height = newValue.height; heightRule = newValue.heightRule; properties = newValue.rawProperties
            preventSplit = newValue.preventSplit; omittedLeadingColumns = newValue.omittedLeadingColumns; omittedTrailingColumns = newValue.omittedTrailingColumns
            leadingWidth = newValue.leadingWidth; trailingWidth = newValue.trailingWidth
        }
    }
}
extension TableCell {
    public var formatting: TableCellFormatting {
        get {
            var result = TableCellFormatting(); result.columnSpan = columnSpan; result.verticalMerge = verticalMerge
            result.rowSpan = rowSpan; result.isCovered = isCovered
            result.preferredWidth = preferredWidth; result.verticalAlignment = verticalAlignment; result.shading = shading
            result.borders = borders; result.margins = margins; result.textDirection = textDirection
            result.noWrap = noWrap; result.fitText = fitText
            result.rawProperties = properties; return result
        }
        set {
            columnSpan = newValue.columnSpan; verticalMerge = newValue.verticalMerge; preferredWidth = newValue.preferredWidth
            verticalAlignment = newValue.verticalAlignment; shading = newValue.shading; properties = newValue.rawProperties
            rowSpan = newValue.rowSpan; isCovered = newValue.isCovered
            borders = newValue.borders; margins = newValue.margins; textDirection = newValue.textDirection
            noWrap = newValue.noWrap; fitText = newValue.fitText
        }
    }
}
