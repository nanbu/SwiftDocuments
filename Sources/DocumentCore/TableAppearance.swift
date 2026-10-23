import Foundation

/// Source border positions. Logical edges remain distinct from physical edges.
public enum TableBorderEdge: String, Sendable, CaseIterable {
    case top, bottom, left, right, start, end
    case insideHorizontal, insideVertical, diagonalDown, diagonalUp
}
/// Cell padding positions, without resolving writing direction.
public enum TableCellEdge: String, Sendable, CaseIterable { case top, bottom, left, right, start, end }
/// One declared border; adjacent-border conflict resolution belongs to layout.
public struct TableBorder: Sendable, Equatable {
    /// Source line style, including explicit "none" / "nil" suppression.
    public var style: String
    /// Line width in points. Decorative art sizes remain sourceWidth only.
    public var width: Double?
    public var spacing: Double?
    public var color: String?
    public var themeColor: String?
    public var themeTint: String?
    public var themeShade: String?
    public var shadow: Bool?
    public var frame: Bool?
    public var sourceWidth: String?
    public var rawProperties: [String] = []
    public init(style: String, width: Double? = nil, color: String? = nil) {
        self.style = style; self.width = width; self.color = color
    }
}
public enum TableAlignment: String, Sendable { case left, center, right, start, end }
public enum TableLayout: String, Sendable { case automatic, fixed }

extension TableFormatting {
    /// Merge declarations independently, so an explicit no-border still overrides a style.
    package mutating func merge(_ other: Self) {
        styleID = other.styleID ?? styleID; preferredWidth = other.preferredWidth ?? preferredWidth
        alignment = other.alignment ?? alignment; layout = other.layout ?? layout
        indentation = other.indentation ?? indentation; cellSpacing = other.cellSpacing ?? cellSpacing
        rightToLeft = other.rightToLeft ?? rightToLeft; shading = other.shading ?? shading
        borders.merge(other.borders) { _, next in next }; cellMargins.merge(other.cellMargins) { _, next in next }
    }
}
extension TableCellFormatting {
    package mutating func mergeAppearance(_ other: Self) {
        shading = other.shading ?? shading; verticalAlignment = other.verticalAlignment ?? verticalAlignment
        preferredWidth = other.preferredWidth ?? preferredWidth
        textDirection = other.textDirection ?? textDirection; noWrap = other.noWrap ?? noWrap; fitText = other.fitText ?? fitText
        borders.merge(other.borders) { _, next in next }; margins.merge(other.margins) { _, next in next }
    }
}
