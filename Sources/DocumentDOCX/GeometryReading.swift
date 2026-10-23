import Foundation
import DocumentCore

extension MarkupNode {
    var mainDrawingVocabulary: Bool {
        namespace == "http://schemas.openxmlformats.org/drawingml/2006/main" ||
        namespace == "http://purl.oclc.org/ooxml/drawingml/main"
    }
    // DrawingML attributes are unqualified; Word-qualified names are extensions here.
    func drawingAttribute(_ name: String) -> String? { attributes[name] }
}

extension StoryReader {
    func drawingGeometry(_ node: MarkupNode?) throws -> DrawingGeometry? {
        guard let node else { return nil }
        var geometry = DrawingGeometry(); geometry.preset = node.drawingAttribute("prst"); geometry.rawXML = node.xml
        var diagnosed = Set<ObjectIdentifier>()
        func warn(_ n: MarkupNode) {
            if diagnosed.insert(ObjectIdentifier(n)).inserted { properties.unparsed(n, part: part) }
        }
        func invalid(_ detail: String) -> DocumentError { .invalidXML(part: part, detail: "DrawingML geometry: " + detail) }
        func extensions(_ n: MarkupNode, attributes: Set<String> = []) {
            let text = n.content.contains { if case .text(let value) = $0 { return !value.allSatisfy(\.isWhitespace) }; return false }
            if text || n.attributes.keys.contains(where: { !attributes.contains($0) }) { warn(n) }
        }
        func required(_ n: MarkupNode, _ name: String) throws -> String {
            guard let value = n.drawingAttribute(name), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw invalid("missing \(name) on \(n.name)")
            }
            return value
        }
        func child(_ parent: MarkupNode, _ name: String) throws -> MarkupNode? {
            let matches = parent.children.filter { $0.namespace == node.namespace && $0.name == name }
            guard matches.count <= 1 else { throw invalid("duplicate \(name)") }
            return matches.first
        }
        func unknownChildren(_ parent: MarkupNode, known: Set<String>) {
            for value in parent.children where value.namespace != node.namespace || !known.contains(value.name) {
                warn(value)
            }
        }
        extensions(node, attributes: node.name == "prstGeom" ? ["prst"] : [])
        unknownChildren(node, known: ["avLst", "gdLst", "pathLst"])
        var names = Set<String>()
        func guides(_ name: String) throws -> [GeometryGuide] {
            guard let list = try child(node, name) else { return [] }
            extensions(list); unknownChildren(list, known: ["gd"])
            return try list.children.filter { $0.namespace == node.namespace && $0.name == "gd" }.map { guide in
                try Task.checkCancellation()
                extensions(guide, attributes: ["name", "fmla"]); unknownChildren(guide, known: [])
                let name = try required(guide, "name"), formula = try required(guide, "fmla")
                guard names.insert(name).inserted else { throw invalid("duplicate guide \(name)") }
                return GeometryGuide(name: name, formula: formula)
            }
        }
        geometry.adjustments = try guides("avLst"); geometry.guides = try guides("gdLst")
        if node.name == "prstGeom" {
            let preset = try required(node, "prst")
            if var resolved = try PresetGeometry.read(preset, adjustments: geometry.adjustments) {
                resolved.rawXML = geometry.rawXML
                let supported = Set(resolved.adjustments.map(\.name))
                if let list = try child(node, "avLst") {
                    for guide in list.children where guide.namespace == node.namespace && guide.name == "gd" && !supported.contains(guide.drawingAttribute("name") ?? "") {
                        warn(guide)
                    }
                }
                // These are not part of preset geometry and cannot override its definition.
                for value in node.children where value.namespace == node.namespace && ["gdLst", "pathLst"].contains(value.name) {
                    warn(value)
                }
                return resolved
            }
            warn(node)
        }
        guard let paths = try child(node, "pathLst") else { return geometry }
        extensions(paths); unknownChildren(paths, known: ["path"])
        for source in paths.children where source.namespace == node.namespace && source.name == "path" {
            try Task.checkCancellation()
            var path = GeometryPath(), invalidOptional = false
            func dimension(_ key: String) -> Double? {
                guard let value = source.drawingAttribute(key) else { return nil }
                guard let number = Double(value), number.isFinite, number >= 0 else { invalidOptional = true; return nil }
                return number
            }
            func flag(_ key: String) -> Bool? {
                guard let value = source.drawingAttribute(key) else { return nil }
                switch value {
                case "true", "1": return true
                case "false", "0": return false
                default: invalidOptional = true; return nil
                }
            }
            path.width = dimension("w"); path.height = dimension("h")
            path.stroke = flag("stroke"); path.extrusionOK = flag("extrusionOk")
            if let fill = source.drawingAttribute("fill") {
                if ["none", "norm", "lighten", "lightenLess", "darken", "darkenLess"].contains(fill) { path.fill = fill }
                else { invalidOptional = true }
            }
            let knownAttributes: Set<String> = ["w", "h", "fill", "stroke", "extrusionOk"]
            if invalidOptional { warn(source) }
            else { extensions(source, attributes: knownAttributes) }
            for command in source.children {
                try Task.checkCancellation()
                let arity = ["moveTo": 1, "lnTo": 1, "quadBezTo": 2, "cubicBezTo": 3, "arcTo": 0, "close": 0]
                guard command.namespace == node.namespace, let count = arity[command.name] else {
                    path.commands.append(.unsupported(command.name)); warn(command); continue
                }
                extensions(command, attributes: command.name == "arcTo" ? ["wR", "hR", "stAng", "swAng"] : [])
                unknownChildren(command, known: ["pt"])
                let points = command.children.filter { $0.namespace == node.namespace && $0.name == "pt" }
                guard points.count == count else { throw invalid("invalid point count on \(command.name)") }
                let arguments: [String]
                if command.name == "arcTo" { arguments = try ["wR", "hR", "stAng", "swAng"].map { try required(command, $0) } }
                else {
                    arguments = try points.flatMap { point in
                        extensions(point, attributes: ["x", "y"]); unknownChildren(point, known: [])
                        return try [required(point, "x"), required(point, "y")]
                    }
                }
                path.commands.append(try geometryCommand(command.name, arguments: arguments))
            }
            geometry.paths.append(path)
        }
        return geometry
    }
}
