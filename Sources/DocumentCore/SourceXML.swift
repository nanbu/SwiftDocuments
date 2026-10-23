import Foundation

/// Immutable source XML with original qualified names, namespace scope and ordered mixed content.
public struct SourceXMLNode: Sendable, Equatable, Codable {
    public enum Content: Sendable, Equatable, Codable { case text(String), element(SourceXMLNode) }
    public let name: String
    public let namespace: String
    public let qualifiedName: String
    public let namespaceBindings: [String: String]
    /// Namespaced attribute keys use URI|localName, matching the companion libraries.
    public let attributes: [String: String]
    /// Attribute key to original qualified name.
    public let attributeNames: [String: String]
    public let content: [Content]
    public var children: [SourceXMLNode] { content.compactMap { if case .element(let node) = $0 { node } else { nil } } }
    public var text: String { content.map { switch $0 { case .text(let text): text; case .element(let node): node.text } }.joined() }
    public func descendants(named name: String, namespace: String? = nil) -> [SourceXMLNode] {
        var result: [SourceXMLNode] = [], pending = [content.makeIterator()]
        while !pending.isEmpty {
            guard let item = pending[pending.count - 1].next() else { pending.removeLast(); continue }
            if case .element(let node) = item {
                if node.name == name && (namespace == nil || node.namespace == namespace) { result.append(node) }
                pending.append(node.content.makeIterator())
            }
        }
        return result
    }
    package init(_ node: MarkupNode) throws {
        try Task.checkCancellation()
        let names = node.sourceNames ?? node.normalizedNames
        name = node.name; namespace = node.namespace; qualifiedName = names.qualifiedName
        namespaceBindings = names.namespaceBindings
        attributes = node.attributes; attributeNames = names.attributeNames
        content = try node.content.map { switch $0 { case .text(let value): .text(value); case .node(let child): .element(try SourceXMLNode(child)) } }
    }
}
public struct SourceXMLReadResult: Sendable {
    public let part: String
    public let root: SourceXMLNode
    public let warnings: [ReadWarning]
    package init(part: String, root: SourceXMLNode) {
        self.part = part; self.root = root
        warnings = [ReadWarning(code: .unsupportedContent, part: part, element: root.name,
                                message: "Original XML structure; semantic interpretation and rendering are not implied.")]
    }
}
extension Document {
    /// Read an original XML part on demand without interpreting or fetching external resources.
    public func readSourceXML(at path: String) throws -> SourceXMLReadResult { try sourceXMLSync(at: path) }
    @concurrent public func readSourceXML(at path: String) async throws -> SourceXMLReadResult { try sourceXMLSync(at: path) }
    private func sourceXMLSync(at path: String) throws -> SourceXMLReadResult {
        try Task.checkCancellation()
        let data = try asset(at: path)
        let node = try XMLTree.parse(data, part: path, limits: parsingLimits, preserveSourceNames: true)
        return try SourceXMLReadResult(part: path, root: SourceXMLNode(node))
    }
}
