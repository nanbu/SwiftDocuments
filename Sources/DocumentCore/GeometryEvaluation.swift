// Adapted from SwiftSlides DrawingGeometryEvaluation.swift (MIT, same project author).
import Foundation

/// Shape-local coordinates, without conversion to page points.
public struct PathPoint: Sendable, Equatable, Codable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
/// A DrawingML arc using polar angles in degrees about the ellipse center.
public struct EvaluatedArc: Sendable, Equatable, Codable {
    public let center: PathPoint
    public let widthRadius: Double
    public let heightRadius: Double
    public let startAngle: Double
    public let sweepAngle: Double
    public let end: PathPoint
}
public enum EvaluatedPathCommand: Sendable, Equatable, Codable {
    case move(PathPoint), line(PathPoint)
    case quadratic(control: PathPoint, end: PathPoint)
    case cubic(control1: PathPoint, control2: PathPoint, end: PathPoint)
    case arc(EvaluatedArc), close
}
public struct EvaluatedGeometryPath: Sendable, Equatable, Codable {
    public let width: Double?
    public let height: Double?
    public let fillMode: String?
    public let stroke: Bool?
    public let extrusionOK: Bool?
    public let commands: [EvaluatedPathCommand]
}
public struct CustomGeometryEvaluation: Sendable, Equatable, Codable {
    public let guides: [String: Double]
    public let adjustments: [String: Double]
    public let paths: [EvaluatedGeometryPath]
}

public enum GeometryEvaluator {
    /// Evaluate the 17 DrawingML operations in the original geometry coordinate units.
    /// Resolve guides in declaration order; reject forward references, cycles and unknown operations.
    public static func evaluate(_ geometry: DrawingGeometry, width: Double, height: Double,
                                adjustments overrides: [String: Double] = [:], maxOperations: Int = 100_000) throws -> CustomGeometryEvaluation {
        guard width.isFinite, height.isFinite, width >= 0, height >= 0, maxOperations > 0 else { throw DocumentError.invalidModel("invalid DrawingML geometry dimensions or operation budget") }
        var remaining = maxOperations
        func charge() throws { try Task.checkCancellation(); remaining -= 1; guard remaining >= 0 else { throw DocumentError.limitExceeded("DrawingML geometry operation budget") } }
        func finite(_ n: Double) throws -> Double { guard n.isFinite else { throw DocumentError.invalidModel("non-finite DrawingML geometry result") }; return n }
        let ss = min(width, height), ls = max(width, height), circle = 21_600_000.0
        var values: [String: Double] = ["l": 0, "t": 0, "r": width, "b": height, "w": width, "h": height, "hc": width / 2, "vc": height / 2, "ss": ss, "ls": ls]
        for divisor in [2, 3, 4, 5, 6, 8, 10, 12, 16, 32] {
            values["wd\(divisor)"] = width / Double(divisor); values["hd\(divisor)"] = height / Double(divisor)
            values["ssd\(divisor)"] = ss / Double(divisor)
        }
        for divisor in [2, 4, 8] { values["cd\(divisor)"] = circle / Double(divisor) }
        for (name, n) in ["3cd4": 3 * circle / 4, "3cd8": 3 * circle / 8, "5cd8": 5 * circle / 8, "7cd8": 7 * circle / 8] { values[name] = n }
        func operand(_ text: String) throws -> Double {
            try charge()
            guard let n = Double(text) ?? values[text] else { throw DocumentError.invalidModel("unresolved DrawingML guide: \(text)") }
            return try finite(n)
        }
        let arity = ["*/": 3, "+-": 3, "+/": 3, "?:": 3, "abs": 1, "at2": 2, "cat2": 3, "cos": 2, "max": 2, "min": 2, "mod": 3, "pin": 3, "sat2": 3, "sin": 2, "sqrt": 1, "tan": 2, "val": 1]
        let toRadians = Double.pi / 10_800_000
        func formula(_ text: String) throws -> Double {
            try charge()
            let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let op = parts.first, let n = arity[op], parts.count == n + 1 else { throw DocumentError.invalidModel("invalid DrawingML guide operation or argument count") }
            let a = try parts.dropFirst().map(operand), x = a[0], y = n > 1 ? a[1] : 0, z = n > 2 ? a[2] : 0
            let result: Double
            switch op {
            case "*/": guard z != 0 else { throw DocumentError.invalidModel("division by zero in DrawingML guide") }; result = x * y / z
            case "+-": result = x + y - z
            case "+/": guard z != 0 else { throw DocumentError.invalidModel("division by zero in DrawingML guide") }; result = (x + y) / z
            case "?:": result = x > 0 ? y : z
            case "abs": result = abs(x)
            case "at2": result = atan2(y, x) / toRadians
            case "cat2": result = x * cos(atan2(z, y))
            case "sat2": result = x * sin(atan2(z, y))
            case "cos": result = x * cos(y * toRadians)
            case "sin": result = x * sin(y * toRadians)
            case "tan": result = x * tan(y * toRadians)
            case "max": result = max(x, y)
            case "min": result = min(x, y)
            case "mod": result = hypot(hypot(x, y), z)
            case "pin": result = y < x ? x : y > z ? z : y
            case "sqrt": result = sqrt(x)
            default: result = x
            }
            return try finite(result)
        }
        var seen = Set(values.keys), adjustmentValues: [String: Double] = [:], guides: [String: Double] = [:]
        guard Set(overrides.keys).isSubset(of: Set(geometry.adjustments.map(\.name))) else { throw DocumentError.invalidModel("unknown geometry adjustment override") }
        for guide in geometry.adjustments + geometry.guides {
            guard !guide.name.isEmpty, seen.insert(guide.name).inserted else { throw DocumentError.invalidModel("duplicate DrawingML guide") }
            let adjustment = geometry.adjustments.contains { $0.name == guide.name }
            let n = try finite(adjustment ? overrides[guide.name] ?? formula(guide.formula) : formula(guide.formula))
            values[guide.name] = n
            if adjustment { adjustmentValues[guide.name] = n } else { guides[guide.name] = n }
        }
        func point(_ p: GeometryPoint) throws -> PathPoint { try .init(x: operand(p.x), y: operand(p.y)) }
        func ellipseOffset(rx: Double, ry: Double, angle: Double) -> PathPoint {
            guard rx > 0, ry > 0 else { return .init(x: 0, y: 0) }
            let a = angle * toRadians, parameter = atan2(rx * sin(a), ry * cos(a))
            return .init(x: rx * cos(parameter), y: ry * sin(parameter))
        }
        var paths: [EvaluatedGeometryPath] = []
        for path in geometry.paths {
            for dimension in [path.width, path.height].compactMap({ $0 }) { guard dimension.isFinite, dimension >= 0 else { throw DocumentError.invalidModel("invalid geometry path dimensions") } }
            var commands: [EvaluatedPathCommand] = [], current: PathPoint?, start: PathPoint?
            for command in path.commands {
                try charge()
                switch command {
                case .move(let p): let p = try point(p); commands.append(.move(p)); current = p; start = p
                case .line(let p): guard current != nil else { throw DocumentError.invalidModel("line before move") }; let p = try point(p); commands.append(.line(p)); current = p
                case .quadratic(let c, let e): guard current != nil else { throw DocumentError.invalidModel("curve before move") }; let e = try point(e); commands.append(try .quadratic(control: point(c), end: e)); current = e
                case .cubic(let c1, let c2, let e): guard current != nil else { throw DocumentError.invalidModel("curve before move") }; let e = try point(e); commands.append(try .cubic(control1: point(c1), control2: point(c2), end: e)); current = e
                case .arc(let wr, let hr, let st, let sw):
                    guard let p = current else { throw DocumentError.invalidModel("arc before move") }
                    let rx = try operand(wr), ry = try operand(hr), a = try operand(st), sweep = try operand(sw)
                    guard rx >= 0, ry >= 0 else { throw DocumentError.invalidModel("negative arc radius") }
                    let offset = ellipseOffset(rx: rx, ry: ry, angle: a), center = PathPoint(x: p.x - offset.x, y: p.y - offset.y)
                    let endOffset = ellipseOffset(rx: rx, ry: ry, angle: try finite(a + sweep))
                    let end = try PathPoint(x: finite(center.x + endOffset.x), y: finite(center.y + endOffset.y))
                    commands.append(.arc(.init(center: center, widthRadius: rx, heightRadius: ry, startAngle: a / 60_000, sweepAngle: sweep / 60_000, end: end))); current = end
                case .close: guard let start else { throw DocumentError.invalidModel("close before move") }; commands.append(.close); current = start
                case .unsupported(let name): throw DocumentError.unsupportedContainer("unsupported path command: \(name)")
                }
            }
            paths.append(.init(width: path.width, height: path.height, fillMode: path.fill, stroke: path.stroke, extrusionOK: path.extrusionOK, commands: commands))
        }
        return .init(guides: guides, adjustments: adjustmentValues, paths: paths)
    }
}
