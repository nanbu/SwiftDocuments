import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

package enum XMLNamespace {
    package static let word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    package static let strictWord = "http://purl.oclc.org/ooxml/wordprocessingml/main"
    package static let relationship = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    package static let strictRelationship = "http://purl.oclc.org/ooxml/officeDocument/relationships"
    package static let packageRelationship = "http://schemas.openxmlformats.org/package/2006/relationships"
    package static let contentTypes = "http://schemas.openxmlformats.org/package/2006/content-types"
}
package final class MarkupNode {
    package enum Content { case text(String), node(MarkupNode) }
    package let name: String
    package let namespace: String
    package let attributes: [String: String]
    package var content: [Content] = []
    package init(name: String, namespace: String, attributes: [String: String]) { self.name = name; self.namespace = namespace; self.attributes = attributes }
    package var isWord: Bool { namespace == XMLNamespace.word || namespace == XMLNamespace.strictWord }
    package var children: [MarkupNode] { content.compactMap { if case .node(let n) = $0 { n } else { nil } } }
    package var text: String { content.map { switch $0 { case .text(let s): s; case .node(let n): n.text } }.joined() }
    package func child(_ name: String) -> MarkupNode? { children.first { $0.name == name && $0.isWord } }
    package func wordChildren(_ name: String) -> [MarkupNode] { children.filter { $0.name == name && $0.isWord } }
    package func attr(_ name: String) -> String? { attributes["\(XMLNamespace.word)|\(name)"] ?? attributes["\(XMLNamespace.strictWord)|\(name)"] ?? attributes[name] }
    package func rel(_ name: String) -> String? { attributes["\(XMLNamespace.relationship)|\(name)"] ?? attributes["\(XMLNamespace.strictRelationship)|\(name)"] }
    package var value: String? { attr("val") }
    package var on: Bool { !["0", "false", "off"].contains(value ?? "true") }
    package func descendants(_ name: String, namespaceSuffix: String? = nil) -> [MarkupNode] {
        children.flatMap { node -> [MarkupNode] in
            let match = node.name == name && (namespaceSuffix.map { node.namespace.hasSuffix($0) } ?? true)
            return (match ? [node] : []) + node.descendants(name, namespaceSuffix: namespaceSuffix)
        }
    }
    package var xml: String {
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: ">", with: "&gt;") }
        let tag = namespace.isEmpty ? name : "n:\(name)"
        var declarations = namespace.isEmpty ? "" : " xmlns:n=\"\(escape(namespace))\""
        var attrs = "", i = 0
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            let split = key.split(separator: "|", maxSplits: 1).map(String.init)
            if split.count == 2 {
                declarations += " xmlns:a\(i)=\"\(escape(split[0]))\""
                attrs += " a\(i):\(split[1])=\"\(escape(value))\""; i += 1
            } else { attrs += " \(key)=\"\(escape(value))\"" }
        }
        let body = content.map { switch $0 { case .text(let s): escape(s); case .node(let n): n.xml } }.joined()
        return "<\(tag)\(declarations)\(attrs)>\(body)</\(tag)>"
    }
}

/// SAX builds one top-level body block at a time when a callback is supplied.
package enum XMLTree {
    package static func parse(_ data: Data, part: String, limits: PackageLimits, onBodyChild: ((MarkupNode) throws -> Void)? = nil) throws -> MarkupNode {
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            for declaration in ["<!DOCTYPE", "<!ENTITY"] {
                if let pattern = declaration.data(using: encoding), data.range(of: pattern) != nil { throw DocumentError.invalidXML(part: part, detail: "DTD / entities are forbidden") }
            }
        }
        let delegate = TreeDelegate(part: part, limits: limits, callback: onBodyChild)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        let success = parser.parse()
        if let error = delegate.failure { throw error }
        guard success, let root = delegate.root else { throw DocumentError.invalidXML(part: part, detail: parser.parserError?.localizedDescription ?? "empty XML") }
        return root
    }
}
private final class TreeDelegate: NSObject, XMLParserDelegate {
    let part: String
    let limits: PackageLimits
    let callback: ((MarkupNode) throws -> Void)?
    var root: MarkupNode?
    var stack: [MarkupNode] = []
    var prefixes: [String: [String]] = ["xml": ["http://www.w3.org/XML/1998/namespace"]]
    var failure: (any Error)?
    var nodes = 0
    init(part: String, limits: PackageLimits, callback: ((MarkupNode) throws -> Void)?) { self.part = part; self.limits = limits; self.callback = callback }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) { prefixes[prefix, default: []].append(namespaceURI) }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = prefixes[prefix]?.popLast() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        nodes += 1
        guard nodes <= limits.maxXMLNodes, stack.count < limits.maxXMLDepth else { failure = DocumentError.limitExceeded("XML depth / node count in \(part)"); parser.abortParsing(); return }
        var attrs: [String: String] = [:]
        for (key, value) in attributeDict {
            let split = key.split(separator: ":", maxSplits: 1).map(String.init)
            if split.count == 2 {
                guard let uri = prefixes[split[0]]?.last else { failure = DocumentError.invalidXML(part: part, detail: "unbound attribute prefix"); parser.abortParsing(); return }
                attrs["\(uri)|\(split[1])"] = value
            } else { attrs[key] = value }
        }
        let node = MarkupNode(name: elementName, namespace: namespaceURI ?? "", attributes: attrs)
        if let parent = stack.last { parent.content.append(.node(node)) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let node = stack.last else { return }
        // Formatting whitespace must not accumulate on the body between emitted blocks.
        // Unknown mixed content keeps every text segment, including spaces between child elements.
        if node.isWord, !["t", "delText", "instrText", "delInstrText"].contains(node.name), string.allSatisfy(\.isWhitespace) { return }
        node.content.append(.text(string))
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard failure == nil, let node = stack.popLast() else { return }
        if stack.count == 2, let parent = stack.last, parent.isWord, parent.name == "body", stack.first?.isWord == true, stack.first?.name == "document", let callback {
            do { try callback(node); parent.content.removeLast() }
            catch { failure = error; parser.abortParsing() }
        }
    }
}
