import Foundation

/// A preferred table/cell width, distinct from its original format-specific encoding.
public struct TableWidth: Sendable, Equatable {
    public enum Unit: String, Sendable { case points, percent, automatic, none, native }
    /// Points for physical widths; whole percentage points for percentages (50 means 50%).
    public var value: Double?
    public var unit: Unit
    public var sourceValue: String?
    public var sourceUnit: String?
    public init(value: Double? = nil, unit: Unit = .points, sourceValue: String? = nil, sourceUnit: String? = nil) {
        self.value = value; self.unit = unit; self.sourceValue = sourceValue; self.sourceUnit = sourceUnit
    }
}
