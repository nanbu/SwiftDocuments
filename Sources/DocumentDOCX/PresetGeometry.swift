import Foundation
import DocumentCore

private struct PresetGuide: Decodable, Sendable { let name: String; let formula: String }
private struct PresetCommand: Decodable, Sendable { let name: String; let arguments: [String] }
private struct PresetPath: Decodable, Sendable { let width: Double?; let height: Double?; let fill: String?; let stroke: Bool?; let extrusionOK: Bool?; let commands: [PresetCommand] }
private struct PresetDefinition: Decodable, Sendable { let adjustments: [PresetGuide]; let guides: [PresetGuide]; let paths: [PresetPath] }
enum PresetGeometry {
    static func names() throws -> [String] { try definitions.get().keys.sorted() }
    // Bundled, generated, immutable data is decoded once, only if a drawing uses a preset.
    private static let definitions: Result<[String: PresetDefinition], any Error> = Result {
        guard let url = Bundle.module.url(forResource: "preset-geometries", withExtension: "json", subdirectory: "Resources") else { throw DocumentError.missingPart("bundled preset geometries") }
        return try JSONDecoder().decode([String: PresetDefinition].self, from: Data(contentsOf: url))
    }
    static func read(_ name: String, adjustments overrides: [GeometryGuide]) throws -> DrawingGeometry? {
        guard let definition = try definitions.get()[name] else { return nil }
        var result = DrawingGeometry(); result.preset = name
        let replacements = Dictionary(overrides.map { ($0.name, $0.formula) }, uniquingKeysWith: { _, new in new })
        result.adjustments = definition.adjustments.map { GeometryGuide(name: $0.name, formula: replacements[$0.name] ?? $0.formula) }
        result.guides = definition.guides.map { GeometryGuide(name: $0.name, formula: $0.formula) }
        result.paths = try definition.paths.map { source in
            var path = GeometryPath(); path.width = source.width; path.height = source.height; path.fill = source.fill; path.stroke = source.stroke
            path.extrusionOK = source.extrusionOK
            path.commands = try source.commands.map { try geometryCommand($0.name, arguments: $0.arguments) }
            return path
        }
        return result
    }
}
func geometryCommand(_ name: String, arguments a: [String]) throws -> GeometryPathCommand {
    func point(_ index: Int) -> GeometryPoint { GeometryPoint(x: a[index], y: a[index+1]) }
    switch (name, a.count) {
    case ("moveTo", 2): return .move(point(0))
    case ("lnTo", 2): return .line(point(0))
    case ("quadBezTo", 4): return .quadratic(control: point(0), end: point(2))
    case ("cubicBezTo", 6): return .cubic(control1: point(0), control2: point(2), end: point(4))
    case ("arcTo", 4): return .arc(widthRadius: a[0], heightRadius: a[1], startAngle: a[2], sweepAngle: a[3])
    case ("close", 0): return .close
    default: return .unsupported(name)
    }
}
