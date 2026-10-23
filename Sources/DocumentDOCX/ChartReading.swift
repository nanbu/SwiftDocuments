import Foundation
import DocumentCore

func isChartNamespace(_ namespace: String) -> Bool {
    ["http://schemas.openxmlformats.org/drawingml/2006/chart", "http://purl.oclc.org/ooxml/drawingml/chart"].contains(namespace)
}

extension StoryReader {
    /// Foundation XMLParser forbids nested parsing on the same thread. Prepare related charts
    /// before the body parser invokes its streaming callback; share their source trees per read.
    func prepareCharts() throws {
        for reference in relationships.values.sorted(by: { $0.id < $1.id }) where reference.type == "chart" {
            try Task.checkCancellation()
            guard let path = reference.path, references.charts[path] == nil else { continue }
            references.charts[path] = try readChart(path, reference: reference)
        }
    }
    func chart(_ node: MarkupNode) throws -> Chart {
        guard let id = node.rel("id") else { throw DocumentError.invalidRelationship(part: part, detail: "missing chart relationship ID") }
        let reference = try relationship(id, expected: "chart")
        let target = PartReference(relationshipID: id, path: reference.path, externalTarget: reference.isExternal ? reference.target : nil)
        guard let path = reference.path else {
            warnings.add(.unsupportedContent, part: part, element: "chart", message: "External chart retained without fetching its target.")
            return Chart(part: target)
        }
        guard var value = references.charts[path] else { throw DocumentError.invalidRelationship(part: part, detail: "chart was not prepared before streaming") }
        value.part = target
        return value
    }
    private func readChart(_ path: String, reference: Relationship) throws -> Chart {
        let root = try SourceXMLNode(XMLTree.parse(package.archive.read(path), part: path, limits: options.limits, preserveSourceNames: true))
        guard root.name == "chartSpace", isChartNamespace(root.namespace) else { throw DocumentError.invalidXML(part: path, detail: "expected chartSpace") }
        let namespace = root.namespace
        func one(_ node: SourceXMLNode?, _ name: String) throws -> SourceXMLNode? {
            let matches = node?.children.filter { $0.namespace == namespace && $0.name == name } ?? []
            guard matches.count <= 1 else { throw DocumentError.invalidXML(part: path, detail: "duplicate chart element \(name)") }
            return matches.first
        }
        func value(_ node: SourceXMLNode?, _ name: String) throws -> String? { try one(node, name)?.attributes["val"] }
        func finite(_ text: String?) throws -> Double? {
            guard let text else { return nil }
            guard let number = Double(text), number.isFinite else { throw DocumentError.invalidXML(part: path, detail: "non-finite / invalid chart axis number") }
            return number
        }
        func nonnegative(_ text: String?) throws -> Int? {
            guard let text else { return nil }
            guard let result = Int(text), result >= 0 else { throw DocumentError.invalidXML(part: path, detail: "invalid chart index/count") }
            return result
        }
        func data(_ container: SourceXMLNode?) throws -> ChartData? {
            guard let container else { return nil }
            let sources: [String: ChartData.Source] = ["strCache": .stringCache, "numCache": .numberCache,
                "strLit": .stringLiteral, "numLit": .numberLiteral, "multiLvlStrCache": .multiLevelStringCache]
            let refs = container.children.filter { $0.namespace == namespace && ["strRef", "numRef", "multiLvlStrRef"].contains($0.name) }
            guard refs.count <= 1 else { throw DocumentError.invalidXML(part: path, detail: "duplicate chart data reference") }
            let reference = refs.first
            let caches = (reference ?? container).children.filter { $0.namespace == namespace && sources[$0.name] != nil }
            guard caches.count <= 1 else { throw DocumentError.invalidXML(part: path, detail: "duplicate chart data cache") }
            let formula = try one(reference, "f")?.text
            guard let cache = caches.first, let source = sources[cache.name] else {
                guard let reference else {
                    warnings.add(.unsupportedContent, part: path, element: container.name, message: "Unrecognized chart data source retained.")
                    return nil
                }
                warnings.add(.unsupportedContent, part: path, element: reference.name, message: "Chart formula retained without a cached value; formulas are not evaluated.")
                let source: ChartData.Source = reference.name == "numRef" ? .numberReference : reference.name == "multiLvlStrRef" ? .multiLevelStringReference : .stringReference
                return ChartData(source: source, formula: formula, properties: container)
            }
            let count = try nonnegative(value(cache, "ptCount"))
            func points(_ parent: SourceXMLNode) throws -> [ChartPoint] {
                var result: [ChartPoint] = [], indices = Set<Int>()
                for point in parent.children where point.namespace == namespace && point.name == "pt" {
                    try Task.checkCancellation()
                    guard let index = try nonnegative(point.attributes["idx"]), indices.insert(index).inserted,
                          let lexical = try one(point, "v") else { throw DocumentError.invalidXML(part: path, detail: "missing / duplicate chart point index or value") }
                    let value = ChartPoint(index: index, text: lexical.text)
                    result.append(value)
                    if [.numberCache, .numberLiteral].contains(source), value.number == nil {
                        warnings.add(.unsupportedContent, part: path, element: "chartNumericPoint", message: "Nonnumeric cached chart value retained as lexical text.")
                    }
                    if let count, index >= count {
                        warnings.add(.invalidReference, part: path, element: "ptCount", message: "Chart point index exceeds the declared count; sparse source indices retained.")
                    }
                }
                return result
            }
            return try ChartData(source: source, formula: formula, pointCount: count, formatCode: one(cache, "formatCode")?.text,
                                 points: points(cache), levels: source == .multiLevelStringCache ? cache.children.filter { $0.namespace == namespace && $0.name == "lvl" }.map(points) : nil,
                                 properties: container)
        }
        guard let chart = try one(root, "chart"), let plot = try one(chart, "plotArea") else {
            throw DocumentError.invalidXML(part: path, detail: "missing chart / plotArea")
        }
        var groups: [ChartGroup] = [], axes: [ChartAxis] = []
        let kinds: Set<String> = ["barChart", "lineChart", "pieChart", "areaChart", "scatterChart", "bubbleChart", "doughnutChart", "radarChart", "stockChart", "surfaceChart", "bar3DChart", "line3DChart", "pie3DChart", "area3DChart", "surface3DChart", "ofPieChart"]
        for group in plot.children where group.namespace == namespace {
            try Task.checkCancellation()
            if group.name.hasSuffix("Chart") {
                if !kinds.contains(group.name) { warnings.add(.unsupportedContent, part: path, element: group.name, message: "Unknown chart group retained in source properties.") }
                var series: [ChartSeries] = []
                for node in group.children where node.namespace == namespace && node.name == "ser" {
                    var item = ChartSeries()
                    item.index = try nonnegative(value(node, "idx")); item.order = try nonnegative(value(node, "order"))
                    let title = try one(node, "tx")
                    item.title = try one(title, "v")?.text
                    if try one(title, "strRef") != nil { item.titleData = try data(title) }
                    item.categories = try data(one(node, "cat")); item.values = try data(one(node, "val"))
                    item.xValues = try data(one(node, "xVal")); item.yValues = try data(one(node, "yVal"))
                    item.bubbleSizes = try data(one(node, "bubbleSize")); item.properties = node
                    series.append(item)
                }
                groups.append(try ChartGroup(kind: group.name, grouping: value(group, "grouping"), orientation: value(group, "barDir"), series: series,
                                             axisIDs: group.children.filter { $0.namespace == namespace && $0.name == "axId" }.compactMap { $0.attributes["val"] }, properties: group))
            } else if ["catAx", "valAx", "dateAx", "serAx"].contains(group.name) {
                let scale = try one(group, "scaling")
                var axis = ChartAxis(kind: group.name)
                axis.id = try value(group, "axId"); axis.crossAxisID = try value(group, "crossAx"); axis.position = try value(group, "axPos")
                axis.minimum = try finite(value(scale, "min")); axis.maximum = try finite(value(scale, "max")); axis.logarithmicBase = try finite(value(scale, "logBase"))
                axis.numberFormat = try one(group, "numFmt")?.attributes["formatCode"]
                axis.isDeleted = try value(group, "delete").map { ["1", "true", "on"].contains($0) }
                axis.properties = group; axes.append(axis)
            } else if !["layout", "spPr", "dTable", "extLst"].contains(group.name) {
                warnings.add(.unsupportedContent, part: path, element: group.name, message: "Uninterpreted plot-area content retained.")
            }
        }
        var external: PartReference?
        if let node = try one(root, "externalData") {
            let id = node.attributes[XMLNamespace.relationship + "|id"] ?? node.attributes[XMLNamespace.strictRelationship + "|id"]
            guard let id, let target = try package.relationships(from: path)[id] else {
                throw DocumentError.invalidRelationship(part: path, detail: "missing chart workbook relationship")
            }
            external = PartReference(relationshipID: id, path: target.path, externalTarget: target.isExternal ? target.target : nil)
        }
        let title = try one(chart, "title")?.descendants(named: "t").filter {
            ["http://schemas.openxmlformats.org/drawingml/2006/main", "http://purl.oclc.org/ooxml/drawingml/main"].contains($0.namespace)
        }.map(\.text).joined()
        warnings.add(.uninterpretedFormatting, part: path, element: "chartAppearance", message: "Chart appearance, labels and advanced properties retained in source XML; rendering is the caller's responsibility.")
        return try Chart(part: PartReference(relationshipID: reference.id, path: path), groups: groups, axes: axes, title: title,
                         legendPosition: value(one(chart, "legend"), "legendPos"), externalData: external, properties: root)
    }
}
