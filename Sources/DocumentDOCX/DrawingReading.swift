import Foundation
import DocumentCore

private let drawingNamespaces: Set<String> = [
    "http://schemas.openxmlformats.org/drawingml/2006/main", "http://purl.oclc.org/ooxml/drawingml/main",
    "http://schemas.openxmlformats.org/drawingml/2006/picture", "http://purl.oclc.org/ooxml/drawingml/picture",
    "http://schemas.microsoft.com/office/word/2010/wordprocessingShape",
    "http://schemas.microsoft.com/office/word/2010/wordprocessingGroup",
    "http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas"
]
private let placementNamespaces: Set<String> = [
    "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
    "http://purl.oclc.org/ooxml/drawingml/wordprocessingDrawing"
]
private let percentagePlacementNamespace = "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"
func supportedCompatibilityNamespace(_ namespace: String) -> Bool {
    drawingNamespaces.contains(namespace) || isMathNamespace(namespace) || isChartNamespace(namespace) || [XMLNamespace.word, XMLNamespace.strictWord, "http://schemas.microsoft.com/office/drawing/2016/SVG/main"].contains(namespace)
}
extension MarkupNode {
    var drawingVocabulary: Bool { drawingNamespaces.contains(namespace) }
    func drawingChild(_ name: String) -> MarkupNode? { children.first { $0.name == name && $0.drawingVocabulary } }
    func drawingMainChild(_ name: String) -> MarkupNode? { children.first { $0.name == name && $0.mainDrawingVocabulary } }
}
private func number(_ value: String?) -> Double? { value.flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil } }
private func emu(_ value: String?) -> Double? { wordLength(value, unitsPerPoint: 12700) }

extension StoryReader {
    func drawingTokens(_ source: MarkupNode) throws -> [InlineToken] {
        var containers: [MarkupNode] = []
        func find(_ n: MarkupNode) {
            if ["inline", "anchor"].contains(n.name), placementNamespaces.contains(n.namespace) { containers.append(n) }
            else { for child in n.children { find(child) } }
        }
        find(source)
        guard !containers.isEmpty else { return [.inline(.unsupported(unsupported(source)))] }
        return try containers.map { container in
            try Task.checkCancellation()
            let placement = drawingPlacement(container)
            let graphicData = container.descendants("graphicData").first { $0.mainDrawingVocabulary }
            let nodes = try (graphicData?.children ?? []).flatMap { try drawingNodes($0) }
            guard !nodes.isEmpty else { return .inline(.unsupported(unsupported(container))) }
            var root = nodes[0]
            if nodes.count > 1 { root = DrawingNode(kind: .group); root.children = nodes }
            let props = container.children.first { $0.name == "docPr" && $0.namespace == container.namespace }
            root.id = props?.drawingAttribute("id") ?? root.id; root.name = props?.drawingAttribute("name") ?? root.name
            root.alternativeText = props?.drawingAttribute("descr") ?? props?.drawingAttribute("title") ?? root.alternativeText
            let rawXML = container.xml
            let drawing = DocumentDrawing(root: root, placement: placement, sourcePart: part, rawXML: rawXML)
            if root.kind == .image, let picture = root.image {
                var image = DocumentImage(assetPath: picture.assetPath, externalURL: picture.externalURL, name: root.name,
                    alternativeText: root.alternativeText, width: placement.width, height: placement.height,
                    isFloating: placement.isFloating, rawXML: rawXML)
                image.contentType = picture.contentType; image.fallbackAssetPath = picture.fallbackAssetPath
                image.fallbackExternalURL = picture.fallbackExternalURL
                image.crop = picture.crop; image.drawing = drawing
                return .inline(.image(image))
            }
            return .inline(.drawing(drawing))
        }
    }
    private func drawingPlacement(_ n: MarkupNode) -> DrawingPlacement {
        var result = DrawingPlacement(); result.isFloating = n.name == "anchor"
        var diagnosed = Set<ObjectIdentifier>()
        func preserve(_ node: MarkupNode) {
            if diagnosed.insert(ObjectIdentifier(node)).inserted {
                result.rawProperties.append(node.xml); properties.unparsed(node, part: part)
            }
        }
        func attributes(_ node: MarkupNode, known: Set<String>) {
            if node.attributes.keys.contains(where: { !known.contains($0) }) { preserve(node) }
        }
        func flag(_ key: String, fallback: Bool) -> Bool {
            guard let value = n.drawingAttribute(key) else { return fallback }
            switch value { case "1", "true": return true; case "0", "false": return false
            default: preserve(n); return fallback }
        }
        result.behindText = flag("behindDoc", fallback: false)
        result.allowOverlap = flag("allowOverlap", fallback: true)
        result.layoutInCell = flag("layoutInCell", fallback: true)
        result.relativeHeight = integer(n.drawingAttribute("relativeHeight"))
        for key in ["distT", "distB", "distL", "distR"] { result.distances[key] = emu(n.drawingAttribute(key)) }
        attributes(n, known: ["behindDoc", "allowOverlap", "layoutInCell", "relativeHeight", "distT", "distB", "distL", "distR"])
        for child in n.children {
            guard child.namespace == n.namespace || (child.name == "graphic" && child.mainDrawingVocabulary) else {
                preserve(child); continue
            }
            switch child.name {
            case "extent":
                result.width = emu(child.drawingAttribute("cx")); result.height = emu(child.drawingAttribute("cy"))
                attributes(child, known: ["cx", "cy"])
            case "positionH", "positionV":
                let percentName = child.name == "positionH" ? "pctPosHOffset" : "pctPosVOffset"
                func percent(_ node: MarkupNode) -> Bool { node.namespace == percentagePlacementNamespace && node.name == percentName }
                let percentage = child.children.first(where: percent)
                let fraction = percentage.flatMap { value in
                    let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.hasSuffix("%") ? number(String(text.dropLast())).map { $0 / 100 } : number(text).map { $0 / 100000 }
                }
                if let percentage, fraction == nil { preserve(percentage) }
                let position = DrawingPosition(relativeTo: child.drawingAttribute("relativeFrom") ?? "page",
                    offset: emu(child.children.first { $0.name == "posOffset" && $0.namespace == n.namespace }?.text), alignment: child.children.first { $0.name == "align" && $0.namespace == n.namespace }?.text,
                    percentage: fraction)
                attributes(child, known: ["relativeFrom"])
                for value in child.children where !percent(value) && (value.namespace != n.namespace || !["posOffset", "align"].contains(value.name)) {
                    preserve(value)
                }
                if child.name == "positionH" { result.horizontal = position } else { result.vertical = position }
            case "wrapNone", "wrapSquare", "wrapTight", "wrapThrough", "wrapTopAndBottom":
                result.wrap = String(child.name.dropFirst(4)); result.wrapSide = child.drawingAttribute("wrapText")
                if !child.children.isEmpty { result.rawProperties.append(child.xml) }
            case "docPr": attributes(child, known: ["id", "name", "descr", "title"])
            case "cNvGraphicFramePr", "graphic", "simplePos", "effectExtent": break
            default: preserve(child)
            }
        }
        return result
    }
    private func drawingNodes(_ n: MarkupNode) throws -> [DrawingNode] {
        try Task.checkCancellation()
        let kinds: [String: DrawingNode.Kind] = ["wsp": .shape, "sp": .shape, "cxnSp": .connector, "pic": .image, "wgp": .group, "grpSp": .group, "wpc": .canvas]
        if let declaredKind = kinds[n.name], n.drawingVocabulary {
            let connector = n.namespace == "http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
                ? n.children.first { $0.name == "cNvCnPr" && $0.namespace == n.namespace }
                : n.drawingChild("nvCxnSpPr")?.drawingChild("cNvCxnSpPr")
            let kind: DrawingNode.Kind = connector != nil && declaredKind == .shape ? .connector : declaredKind
            var value = DrawingNode(kind: kind)
            let props = n.drawingChild("spPr") ?? n.drawingChild("grpSpPr")
            value.transform = drawingTransform(props?.drawingMainChild("xfrm"))
            value.geometry = try drawingGeometry(props?.drawingMainChild("prstGeom") ?? props?.drawingMainChild("custGeom"))
            value.fill = try drawingFill(props ?? n.drawingChild("bg"))
            let whole = kind == .canvas ? n.drawingChild("whole") : nil
            value.line = try drawingLine(props?.drawingMainChild("ln") ?? whole?.drawingMainChild("ln"))
            if let whole, !whole.attributes.isEmpty || whole.children.contains(where: { !$0.mainDrawingVocabulary || $0.name != "ln" }) {
                value.rawProperties.append(whole.xml); properties.unparsed(whole, part: part)
            }
            let nonvisual = n.drawingChild("cNvPr") ?? n.children
                .filter { $0.drawingVocabulary && ["nvSpPr", "nvPicPr", "nvCxnSpPr", "nvGrpSpPr"].contains($0.name) }
                .compactMap { $0.drawingChild("cNvPr") }.first
            if let nv = nonvisual { value.id = nv.drawingAttribute("id"); value.name = nv.drawingAttribute("name"); value.alternativeText = nv.drawingAttribute("descr") ?? nv.drawingAttribute("title") }
            if let connector {
                value.startConnection = try drawingConnection(connector, name: "stCxn")
                value.endConnection = try drawingConnection(connector, name: "endCxn")
                value.rawProperties.append(connector.xml)
                if !connector.attributes.isEmpty || connector.children.contains(where: { !$0.mainDrawingVocabulary || !["stCxn", "endCxn"].contains($0.name) }) {
                    properties.unparsed(connector, part: part)
                }
            }
            if kind == .image { value.image = try drawingImage(n.drawingChild("blipFill") ?? n) }
            if let text = n.drawingChild("txbx")?.child("txbxContent") { value.text = try independentStoryBlocks(text.children) }
            if let body = n.drawingChild("bodyPr") {
                value.textProperties = body.attributes
                for child in body.children { value.rawProperties.append(child.xml); properties.unparsed(child, part: part) }
            }
            for child in n.children where child.drawingVocabulary && (child.name == "style" || (child.name == "whole" && kind != .canvas)) {
                value.rawProperties.append(child.xml); properties.unparsed(child, part: part)
            }
            if kind == .group || kind == .canvas {
                for child in n.children where !["nvGrpSpPr", "cNvPr", "cNvGrpSpPr", "grpSpPr", "bg", "whole"].contains(child.name) {
                    value.children += try drawingNodes(child)
                }
            }
            let known: Set<String> = ["spPr", "grpSpPr", "nvSpPr", "nvPicPr", "nvCxnSpPr", "nvGrpSpPr", "cNvPr", "cNvSpPr", "cNvGrpSpPr", "cNvCnPr", "cNvPicPr", "txbx", "bodyPr", "blipFill", "style", "bg", "whole"]
            for child in n.children where !child.drawingVocabulary || (!known.contains(child.name) && kinds[child.name] == nil) {
                value.rawProperties.append(child.xml); properties.unparsed(child, part: part)
            }
            for child in props?.children ?? [] where !child.mainDrawingVocabulary || !["xfrm", "prstGeom", "custGeom", "noFill", "solidFill", "gradFill", "pattFill", "blipFill", "ln"].contains(child.name) {
                value.rawProperties.append(child.xml); properties.unparsed(child, part: part)
            }
            return [value]
        }
        if n.name == "blip", n.drawingVocabulary {
            var image = DrawingNode(kind: .image); image.image = try drawingImage(n); return [image]
        }
        if n.name == "chart", isChartNamespace(n.namespace) {
            var value = DrawingNode(kind: .chart)
            value.chart = try chart(n); value.relatedPart = value.chart?.part.path
            return [value]
        }
        if ["relIds", "contentPart"].contains(n.name) {
            var value = DrawingNode(kind: n.name == "relIds" ? .diagram : .ink)
            if let id = n.rel("id") ?? n.rel("dm"), let relationship = relationships[id] { value.relatedPart = relationship.path }
            value.rawProperties = [n.xml]; _ = unsupported(n); return [value]
        }
        var value = DrawingNode(kind: .unknown); value.rawProperties = [n.xml]; _ = unsupported(n); return [value]
    }
    private func drawingLine(_ n: MarkupNode?) throws -> DrawingLine? {
        guard let n else { return nil }
        var line = DrawingLine(); line.width = emu(n.drawingAttribute("w")); line.fill = try drawingFill(n)
        line.cap = n.drawingAttribute("cap"); line.dash = n.drawingMainChild("prstDash")?.drawingAttribute("val")
        line.head = n.drawingMainChild("headEnd")?.drawingAttribute("type"); line.tail = n.drawingMainChild("tailEnd")?.drawingAttribute("type")
        line.rawXML = n.xml
        for child in n.children where !child.mainDrawingVocabulary || !["noFill", "solidFill", "gradFill", "pattFill", "blipFill", "prstDash", "headEnd", "tailEnd"].contains(child.name) {
            properties.unparsed(child, part: part)
        }
        if n.attributes.keys.contains(where: { !["w", "cap"].contains($0) }) { properties.unparsed(n, part: part) }
        return line
    }
    private func drawingConnection(_ container: MarkupNode, name: String) throws -> DrawingConnection? {
        let nodes = container.children.filter { $0.mainDrawingVocabulary && $0.name == name }
        guard !nodes.isEmpty else { return nil }
        guard nodes.count == 1, let n = nodes.first, let target = n.drawingAttribute("id"), UInt32(target) != nil,
              let index = n.drawingAttribute("idx").flatMap(UInt32.init) else {
            throw DocumentError.invalidXML(part: part, detail: "invalid or duplicate drawing connection: \(name)")
        }
        if n.attributes.keys.contains(where: { !["id", "idx"].contains($0) }) || !n.children.isEmpty { properties.unparsed(n, part: part) }
        return DrawingConnection(targetID: target, siteIndex: index)
    }
    private func drawingTransform(_ n: MarkupNode?) -> DrawingTransform {
        var t = DrawingTransform(); guard let n else { return t }
        let off = n.drawingMainChild("off"), size = n.drawingMainChild("ext")
        t.bounds = DrawingRect(x: emu(off?.drawingAttribute("x")) ?? 0, y: emu(off?.drawingAttribute("y")) ?? 0, width: emu(size?.drawingAttribute("cx")) ?? 0, height: emu(size?.drawingAttribute("cy")) ?? 0)
        t.rotation = (number(n.drawingAttribute("rot")) ?? 0) / 60000
        t.flipHorizontal = ["1", "true"].contains(n.drawingAttribute("flipH") ?? "0"); t.flipVertical = ["1", "true"].contains(n.drawingAttribute("flipV") ?? "0")
        if let childOff = n.drawingMainChild("chOff"), let childSize = n.drawingMainChild("chExt") {
            t.childBounds = DrawingRect(x: emu(childOff.drawingAttribute("x")) ?? 0, y: emu(childOff.drawingAttribute("y")) ?? 0, width: emu(childSize.drawingAttribute("cx")) ?? 0, height: emu(childSize.drawingAttribute("cy")) ?? 0)
        }
        return t
    }
    private func drawingColor(_ n: MarkupNode?) -> DrawingColor? {
        guard let n, n.mainDrawingVocabulary, ["srgbClr", "schemeClr", "sysClr", "prstClr"].contains(n.name), let value = n.drawingAttribute("lastClr") ?? n.drawingAttribute("val") else { return nil }
        for child in n.children where !child.mainDrawingVocabulary { properties.unparsed(child, part: part) }
        return DrawingColor(value: value, isTheme: n.name == "schemeClr", transforms: n.children.filter(\.mainDrawingVocabulary).map { ColorTransform(name: $0.name, value: number($0.drawingAttribute("val"))) })
    }
    private func drawingFill(_ container: MarkupNode?) throws -> DrawingFill? {
        guard let n = container?.children.first(where: { ["noFill", "solidFill", "gradFill", "pattFill", "blipFill"].contains($0.name) && $0.mainDrawingVocabulary }) else { return nil }
        var fill = DrawingFill(kind: n.name == "noFill" ? .none : n.name == "solidFill" ? .solid : n.name == "gradFill" ? .gradient : n.name == "pattFill" ? .pattern : .picture)
        fill.color = drawingColor(n.children.first); fill.rawXML = n.xml; fill.pattern = n.drawingAttribute("prst")
        if n.name == "blipFill" { fill.image = try drawingImage(n) }
        if n.name == "pattFill" {
            fill.color = drawingColor(n.drawingChild("fgClr")?.children.first)
            fill.backgroundColor = drawingColor(n.drawingChild("bgClr")?.children.first)
        }
        for child in n.descendants("hslClr") + n.descendants("scrgbClr") where child.drawingVocabulary { properties.unparsed(child, part: part) }
        fill.angle = number(n.drawingChild("lin")?.drawingAttribute("ang")).map { $0 / 60000 }
        for stop in n.drawingChild("gsLst")?.children ?? [] {
            if let color = drawingColor(stop.children.first) { fill.gradientStops.append(GradientStop(position: (number(stop.drawingAttribute("pos")) ?? 0) / 100000, color: color)) }
        }
        return fill
    }
    private func drawingImage(_ n: MarkupNode) throws -> DrawingImage? {
        let blip = n.name == "blip" ? n : n.descendants("blip").first { $0.drawingVocabulary }
        guard let blip else { return nil }
        let svg = blip.descendants("svgBlip").first { $0.namespace == "http://schemas.microsoft.com/office/drawing/2016/SVG/main" }
        func resolve(_ node: MarkupNode?) throws -> Relationship? {
            guard let id = node?.rel("embed") ?? node?.rel("link") else { return nil }
            return try relationship(id, expected: "image")
        }
        let fallback = try resolve(blip), preferred = try resolve(svg) ?? fallback
        guard let preferred else { return nil }
        var result = DrawingImage(assetPath: preferred.path, externalURL: preferred.isExternal ? preferred.target : nil)
        result.contentType = preferred.path.flatMap { package.type(of: $0) }
        if svg != nil {
            result.fallbackAssetPath = fallback?.path
            if let fallback, fallback.isExternal { result.fallbackExternalURL = fallback.target }
        }
        if let crop = n.drawingChild("srcRect") {
            result.crop = ImageCrop(left: (number(crop.drawingAttribute("l")) ?? 0) / 100000, top: (number(crop.drawingAttribute("t")) ?? 0) / 100000,
                                   right: (number(crop.drawingAttribute("r")) ?? 0) / 100000, bottom: (number(crop.drawingAttribute("b")) ?? 0) / 100000)
        }
        if let alpha = blip.drawingChild("alphaModFix") { result.opacity = (number(alpha.drawingAttribute("amt")) ?? 100000) / 100000 }
        return result
    }
    func legacyDrawingTokens(_ source: MarkupNode) throws -> [InlineToken] {
        func length(_ value: String?) -> Double? {
            guard let value else { return nil }
            let factors = ["pt": 1.0, "in": 72.0, "cm": 72 / 2.54, "mm": 72 / 25.4, "px": 0.75]
            for (unit, scale) in factors where value.hasSuffix(unit) { return number(String(value.dropLast(unit.count))).map { $0 * scale } }
            return number(value)
        }
        func read(_ n: MarkupNode) throws -> DrawingNode {
            var value = DrawingNode(kind: n.name == "group" ? .group : .shape)
            value.id = n.attr("id"); value.name = n.attr("title"); value.alternativeText = n.attr("alt")
            var style: [String: String] = [:]
            for field in (n.attr("style") ?? "").split(separator: ";") {
                let pair = field.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if pair.count == 2 { style[pair[0]] = pair[1] }
            }
            value.transform.bounds = DrawingRect(x: length(style["left"]) ?? 0, y: length(style["top"]) ?? 0, width: length(style["width"]) ?? 0, height: length(style["height"]) ?? 0)
            value.transform.rotation = number(style["rotation"]) ?? 0
            var geometry = DrawingGeometry(); geometry.preset = ["oval": "ellipse", "rect": "rect", "roundrect": "roundRect", "line": "line"][n.name]
            geometry.rawXML = n.xml; value.geometry = geometry
            if let color = n.attr("fillcolor") { value.fill = DrawingFill(kind: .solid, color: DrawingColor(value: color.trimmingCharacters(in: CharacterSet(charactersIn: "#")))) }
            if let image = n.children.first(where: { $0.name == "imagedata" }), let id = image.rel("id") {
                let reference = try relationship(id, expected: "image"); value.kind = .image
                value.image = DrawingImage(assetPath: reference.path, externalURL: reference.isExternal ? reference.target : nil)
                value.image?.contentType = reference.path.flatMap { package.type(of: $0) }
            }
            if let text = n.descendants("txbxContent").first(where: \.isWord) { value.text = try independentStoryBlocks(text.children) }
            if value.kind == .group {
                value.children = try n.children.filter { $0.namespace == "urn:schemas-microsoft-com:vml" && $0.name != "shapetype" }.map(read)
            }
            value.rawProperties = [n.xml]
            // VML path formulas and producer-specific layout require independent display evidence.
            warnings.add(.uninterpretedFormatting, part: part, element: "VML", message: "VML source, shapes, text and images are retained; detailed paths and placement remain uninterpreted.")
            return value
        }
        let nodes = source.children.filter { $0.namespace == "urn:schemas-microsoft-com:vml" && $0.name != "shapetype" }
        guard !nodes.isEmpty else { return try images(source) }
        return try nodes.map { n in
            let root = try read(n)
            var placement = DrawingPlacement(); placement.width = root.transform.bounds.width; placement.height = root.transform.bounds.height
            placement.isFloating = (n.attr("style") ?? "").contains("position:absolute")
            return .inline(.drawing(DocumentDrawing(root: root, placement: placement, sourcePart: part, rawXML: n.xml)))
        }
    }
}
