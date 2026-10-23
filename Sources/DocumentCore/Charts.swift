import Foundation

/// An internal part or an unfetched external target. Paths and external URLs remain distinct.
public struct PartReference: Sendable, Equatable, Codable {
    public var relationshipID: String
    public var path: String?
    public var externalTarget: String?
    public init(relationshipID: String, path: String? = nil, externalTarget: String? = nil) {
        self.relationshipID = relationshipID; self.path = path; self.externalTarget = externalTarget
    }
}
/// A sparse, source-indexed chart value. Empty and nonnumeric lexical values are retained.
public struct ChartPoint: Sendable, Equatable, Codable {
    public var index: Int
    public var text: String
    public var number: Double? { guard let value = Double(text), value.isFinite else { return nil }; return value }
    public init(index: Int, text: String) { self.index = index; self.text = text }
}
public struct ChartData: Sendable, Equatable, Codable {
    public enum Source: String, Sendable, Codable {
        case stringCache, numberCache, stringLiteral, numberLiteral, multiLevelStringCache
        case stringReference, numberReference, multiLevelStringReference
    }
    public var source: Source
    public var formula: String?
    public var pointCount: Int?
    public var formatCode: String?
    public var points: [ChartPoint]
    public var levels: [[ChartPoint]]?
    public var properties: SourceXMLNode?
    public init(source: Source, formula: String? = nil, pointCount: Int? = nil, formatCode: String? = nil, points: [ChartPoint] = [], levels: [[ChartPoint]]? = nil, properties: SourceXMLNode? = nil) {
        self.source = source; self.formula = formula; self.pointCount = pointCount; self.formatCode = formatCode
        self.points = points; self.levels = levels; self.properties = properties
    }
}
public struct ChartSeries: Sendable, Equatable, Codable {
    public var index: Int?
    public var order: Int?
    public var title: String?
    public var titleData: ChartData?
    public var categories: ChartData?
    public var values: ChartData?
    public var xValues: ChartData?
    public var yValues: ChartData?
    public var bubbleSizes: ChartData?
    /// Full labels, markers, trendlines, error bars and appearance, sharing the source tree.
    public var properties: SourceXMLNode?
    public init() {}
}
public struct ChartGroup: Sendable, Equatable, Codable {
    public var kind: String
    public var grouping: String?
    public var orientation: String?
    public var series: [ChartSeries]
    public var axisIDs: [String]
    public var properties: SourceXMLNode?
    public init(kind: String, grouping: String? = nil, orientation: String? = nil, series: [ChartSeries] = [], axisIDs: [String] = [], properties: SourceXMLNode? = nil) {
        self.kind = kind; self.grouping = grouping; self.orientation = orientation
        self.series = series; self.axisIDs = axisIDs; self.properties = properties
    }
}
public struct ChartAxis: Sendable, Equatable, Codable {
    public var kind: String
    public var id: String?
    public var crossAxisID: String?
    public var position: String?
    public var minimum: Double?
    public var maximum: Double?
    public var logarithmicBase: Double?
    public var numberFormat: String?
    public var isDeleted: Bool?
    public var properties: SourceXMLNode?
    public init(kind: String) { self.kind = kind }
}
/// Source chart data and structure. No formula evaluation, external fetch or rendering is implied.
public struct Chart: Sendable, Equatable, Codable {
    public var part: PartReference
    public var groups: [ChartGroup]
    public var axes: [ChartAxis]
    public var title: String?
    public var legendPosition: String?
    public var externalData: PartReference?
    public var properties: SourceXMLNode?
    public init(part: PartReference, groups: [ChartGroup] = [], axes: [ChartAxis] = [], title: String? = nil, legendPosition: String? = nil, externalData: PartReference? = nil, properties: SourceXMLNode? = nil) {
        self.part = part; self.groups = groups; self.axes = axes; self.title = title
        self.legendPosition = legendPosition; self.externalData = externalData; self.properties = properties
    }
}
