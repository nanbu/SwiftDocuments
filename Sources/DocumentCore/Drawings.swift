import Foundation

/// Point-based drawing bounds. Group coordinate spaces retain their source units separately.
public struct DrawingRect: Sendable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
/// Source transform; rotation is in degrees, offset and size in points.
public struct DrawingTransform: Sendable, Equatable {
    public var bounds = DrawingRect()
    public var rotation: Double = 0
    public var flipHorizontal = false
    public var flipVertical = false
    /// Group child coordinate origin and extents in points.
    public var childBounds: DrawingRect?
    public init() {}
}
/// A position relative to page, margin, paragraph, line or another source reference.
public struct DrawingPosition: Sendable, Equatable {
    public var relativeTo: String
    public var offset: Double?
    public var alignment: String?
    public var percentage: Double?
    public init(relativeTo: String, offset: Double? = nil, alignment: String? = nil, percentage: Double? = nil) {
        self.relativeTo = relativeTo; self.offset = offset; self.alignment = alignment; self.percentage = percentage
    }
}
/// Inline/floating placement with source wrapping and stacking information.
public struct DrawingPlacement: Sendable, Equatable {
    public var isFloating = false
    public var horizontal: DrawingPosition?
    public var vertical: DrawingPosition?
    public var wrap: String?
    public var wrapSide: String?
    public var distances: [String: Double] = [:]
    public var behindText = false
    public var allowOverlap = true
    public var layoutInCell = true
    public var relativeHeight: Int?
    public var width: Double?
    public var height: Double?
    public var rawProperties: [String] = []
    public init() {}
}
/// Source color retaining theme references and ordered transforms.
public struct DrawingColor: Sendable, Equatable {
    public var value: String
    public var isTheme: Bool
    public var transforms: [ColorTransform]
    public init(value: String, isTheme: Bool = false, transforms: [ColorTransform] = []) {
        self.value = value; self.isTheme = isTheme; self.transforms = transforms
    }
}
/// A color operation with a source numeric value (OOXML percentages use 100000 as 100%).
public struct ColorTransform: Sendable, Equatable {
    public var name: String
    public var value: Double?
    public init(name: String, value: Double? = nil) { self.name = name; self.value = value }
}
public struct GradientStop: Sendable, Equatable {
    public var position: Double
    public var color: DrawingColor
    public init(position: Double, color: DrawingColor) { self.position = position; self.color = color }
}
public struct DrawingFill: Sendable, Equatable {
    public enum Kind: String, Sendable { case none, solid, gradient, pattern, picture }
    public var kind: Kind
    public var color: DrawingColor?
    public var backgroundColor: DrawingColor?
    public var image: DrawingImage?
    public var gradientStops: [GradientStop] = []
    public var angle: Double?
    public var pattern: String?
    public var rawXML: String?
    public init(kind: Kind, color: DrawingColor? = nil) { self.kind = kind; self.color = color }
}
public struct DrawingLine: Sendable, Equatable {
    public var width: Double?
    public var fill: DrawingFill?
    public var dash: String?
    public var cap: String?
    public var head: String?
    public var tail: String?
    public var rawXML: String?
    public init() {}
}
/// Coordinate expressions remain available for custom/preset guide evaluation.
public struct GeometryGuide: Sendable, Equatable {
    public var name: String, formula: String
    public init(name: String, formula: String) { self.name = name; self.formula = formula }
}
public struct GeometryPath: Sendable, Equatable {
    public var width: Double?, height: Double?
    public var commands: [GeometryPathCommand] = []
    public var fill: String?
    public var stroke: Bool?
    public var extrusionOK: Bool?
    public init() {}
}
public struct GeometryPoint: Sendable, Equatable {
    public var x: String, y: String
    public init(x: String, y: String) { self.x = x; self.y = y }
}
public enum GeometryPathCommand: Sendable, Equatable {
    case move(GeometryPoint), line(GeometryPoint)
    case quadratic(control: GeometryPoint, end: GeometryPoint)
    case cubic(control1: GeometryPoint, control2: GeometryPoint, end: GeometryPoint)
    case arc(widthRadius: String, heightRadius: String, startAngle: String, sweepAngle: String)
    case close, unsupported(String)
}
public struct DrawingGeometry: Sendable, Equatable {
    public var preset: String?
    public var guides: [GeometryGuide] = []
    public var adjustments: [GeometryGuide] = []
    public var paths: [GeometryPath] = []
    public var rawXML: String?
    public init() {}
}
public struct ImageCrop: Sendable, Equatable {
    public var left: Double, top: Double, right: Double, bottom: Double
    public init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}
/// A drawing's preferred image and producer fallback. Bytes are obtained with document.asset(at:).
public struct DrawingImage: Sendable, Equatable {
    public var assetPath: String?
    public var externalURL: String?
    public var contentType: String?
    public var fallbackAssetPath: String?
    public var fallbackExternalURL: String?
    public var crop: ImageCrop?
    public var opacity: Double?
    public init(assetPath: String? = nil, externalURL: String? = nil) { self.assetPath = assetPath; self.externalURL = externalURL }
}
/// An endpoint referencing an object's source identifier and zero-based connection site.
public struct DrawingConnection: Sendable, Equatable {
    public var targetID: String
    public var siteIndex: UInt32
    public init(targetID: String, siteIndex: UInt32) { self.targetID = targetID; self.siteIndex = siteIndex }
}
/// One object in a drawing scene. Children preserve producer order and group/canvas boundaries.
public struct DrawingNode: Sendable {
    public enum Kind: String, Sendable { case shape, connector, image, group, canvas, chart, diagram, ink, unknown }
    public var kind: Kind
    public var id: String?
    public var name: String?
    public var alternativeText: String?
    public var transform = DrawingTransform()
    public var geometry: DrawingGeometry?
    public var fill: DrawingFill?
    public var line: DrawingLine?
    public var startConnection: DrawingConnection?
    public var endConnection: DrawingConnection?
    public var image: DrawingImage?
    public var chart: Chart?
    public var text: [Block] = []
    public var textProperties: [String: String] = [:]
    public var children: [DrawingNode] = []
    public var sourcePart: String?
    public var relatedPart: String?
    public var rawProperties: [String] = []
    public init(kind: Kind) { self.kind = kind }
    public var plainText: String { (text.map(\.plainText) + children.map(\.plainText)).filter { !$0.isEmpty }.joined(separator: "\n") }
}
/// A positioned scene with one original source representation and typed children.
public struct DocumentDrawing: Sendable {
    public var root: DrawingNode
    public var placement: DrawingPlacement
    public var sourcePart: String
    public var rawXML: String
    /// Attribution for the enclosing insertion, deletion or move of this scene.
    public var revision: Revision?
    public init(root: DrawingNode, placement: DrawingPlacement = .init(), sourcePart: String = "", rawXML: String = "", revision: Revision? = nil) {
        self.root = root; self.placement = placement; self.sourcePart = sourcePart; self.rawXML = rawXML; self.revision = revision
    }
}
