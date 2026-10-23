import Foundation

/// A format-neutral region to which a table style applies.
public enum TableStyleRegion: String, Sendable, CaseIterable {
    case wholeTable, oddRowBand, evenRowBand, oddColumnBand, evenColumnBand
    case firstColumn, lastColumn, firstRow, lastRow, topLeft, topRight, bottomLeft, bottomRight
}
/// Declared properties for one conditional region, with its source representation.
public struct TableStyleRule: Sendable {
    public var region: TableStyleRegion
    public var paragraph = ParagraphFormatting()
    public var text = TextFormatting()
    public var cell = TableCellFormatting()
    public var row = TableRowFormatting()
    public var table = TableFormatting()
    public var source: SourceXMLNode?
    public init(region: TableStyleRegion) { self.region = region }
}
