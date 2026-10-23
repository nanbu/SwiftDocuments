import Foundation
import Testing
import SwiftDocuments
@testable import DocumentDOCX

@Suite struct GeometryTests {
    @Test func presetPathsKeepExplicitExtrusionFlags() throws {
        let loadedArc = try PresetGeometry.read("arc", adjustments: [])
        let arc = try #require(loadedArc)
        #expect(arc.paths.first?.extrusionOK == false)
        let loadedStorage = try PresetGeometry.read("flowChartOfflineStorage", adjustments: [])
        let storage = try #require(loadedStorage)
        #expect(storage.paths[2].extrusionOK == true)
    }
    @Test func everyBundledPresetEvaluatesAtMultipleAspectRatios() throws {
        let names = try PresetGeometry.names()
        #expect(names.count == 187)
        for name in names {
            let loaded = try PresetGeometry.read(name, adjustments: [])
            let geometry = try #require(loaded)
            for (width, height) in [(240.0, 120.0), (120.0, 240.0), (120.0, 120.0)] {
                let result = try GeometryEvaluator.evaluate(geometry, width: width, height: height)
                #expect(!result.paths.isEmpty, Comment(rawValue: name))
            }
        }
    }
    @Test(arguments: ["rect", "ellipse", "roundRect", "triangle", "hexagon", "star5", "rightArrow", "heart", "cloud", "arc"])
    func presetGeometryProducesFinitePaths(_ name: String) throws {
        let loaded = try PresetGeometry.read(name, adjustments: [])
        let geometry = try #require(loaded)
        let result = try GeometryEvaluator.evaluate(geometry, width: 240, height: 120)
        #expect(!result.paths.isEmpty && result.paths.contains { !$0.commands.isEmpty })
        #expect(result.guides.values.allSatisfy { $0.isFinite })
    }
    @Test func customGeometryRejectsUnknownGuidesAndOperations() throws {
        var g = DrawingGeometry(); g.guides = [GeometryGuide(name: "x", formula: "val missing")]
        #expect(throws: DocumentError.self) { try GeometryEvaluator.evaluate(g, width: 100, height: 50) }
        g.guides = [GeometryGuide(name: "x", formula: "*/ w 1 0")]
        #expect(throws: DocumentError.self) { try GeometryEvaluator.evaluate(g, width: 100, height: 50) }
        g.guides = [GeometryGuide(name: "x", formula: "unknown w")]
        #expect(throws: DocumentError.self) { try GeometryEvaluator.evaluate(g, width: 100, height: 50) }
    }
    @Test func customGeometryEvaluatesGuidesCurvesAndPolarArcs() throws {
        var g = DrawingGeometry(); g.guides = [GeometryGuide(name: "half", formula: "*/ w 1 2")]
        var path = GeometryPath()
        path.commands = [.move(GeometryPoint(x: "w", y: "vc")), .arc(widthRadius: "half", heightRadius: "vc", startAngle: "0", sweepAngle: "cd4"), .close]
        g.paths = [path]
        let evaluated = try GeometryEvaluator.evaluate(g, width: 100, height: 50)
        #expect(evaluated.guides["half"] == 50)
        guard case .arc(let arc) = evaluated.paths[0].commands[1] else { Issue.record("Expected arc"); return }
        #expect(abs(arc.center.x - 50) < 0.000001 && abs(arc.center.y - 25) < 0.000001)
        #expect(abs(arc.end.x - 50) < 0.000001 && abs(arc.end.y - 50) < 0.000001)
        #expect(throws: DocumentError.self) { try GeometryEvaluator.evaluate(g, width: 100, height: 50, maxOperations: 1) }
    }
}
