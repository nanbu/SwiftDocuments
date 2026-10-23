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
    package final class SourceNames {
        package let qualifiedName: String
        package let attributeNames: [String: String]
        package let namespaceBindings: [String: String]
        package init(qualifiedName: String, attributeNames: [String: String], namespaceBindings: [String: String]) {
            self.qualifiedName = qualifiedName; self.attributeNames = attributeNames; self.namespaceBindings = namespaceBindings
        }
    }
    package var sourceNames: SourceNames?
    package enum Content { case text(String), node(MarkupNode) }
    package let name: String
    package let namespace: String
    package let attributes: [String: String]
    /// Only bindings referenced by QName-valued attributes, avoiding a full scope copy per node.
    package var namespaceBindings: [String: String] = [:]
    package var content: [Content] = []
    package init(name: String, namespace: String, attributes: [String: String]) { self.name = name; self.namespace = namespace; self.attributes = attributes }
    package var isWord: Bool { namespace == XMLNamespace.word || namespace == XMLNamespace.strictWord }
    package var children: [MarkupNode] { content.compactMap { if case .node(let n) = $0 { n } else { nil } } }
    package var text: String {
        if content.count == 1 { return switch content[0] { case .text(let value): value; case .node(let node): node.text } }
        var result = ""
        for item in content { switch item { case .text(let value): result += value; case .node(let node): result += node.text } }
        return result
    }
    package func child(_ name: String) -> MarkupNode? {
        for item in content { if case .node(let node) = item, node.name == name, node.isWord { return node } }
        return nil
    }
    package func wordChildren(_ name: String) -> [MarkupNode] {
        content.compactMap { if case .node(let node) = $0, node.name == name, node.isWord { node } else { nil } }
    }
    package func attr(_ name: String) -> String? { attributes["\(XMLNamespace.word)|\(name)"] ?? attributes["\(XMLNamespace.strictWord)|\(name)"] ?? attributes[name] }
    package func rel(_ name: String) -> String? { attributes["\(XMLNamespace.relationship)|\(name)"] ?? attributes["\(XMLNamespace.strictRelationship)|\(name)"] }
    package var value: String? { attr("val") }
    package static func boolean(_ source: String?) -> Bool? {
        guard let source else { return true }
        switch source { case "1", "true", "on": return true; case "0", "false", "off": return false; default: return nil }
    }
    package var onOffValue: Bool? { Self.boolean(value) }
    package var on: Bool { onOffValue ?? false }
    /// A namespace-correct reconstruction, without starting a nested Foundation XMLParser.
    package var normalizedNames: SourceNames {
        var bindings = namespaceBindings
        bindings["xml"] = "http://www.w3.org/XML/1998/namespace"
        var prefix = "n"
        while bindings[prefix] != nil { prefix = "_" + prefix }
        if !namespace.isEmpty { bindings[prefix] = namespace }
        var names: [String: String] = [:], index = 0
        for key in attributes.keys.sorted() {
            let components = key.split(separator: "|", maxSplits: 1).map(String.init)
            if components.count == 2 {
                if components[0] == "http://www.w3.org/XML/1998/namespace" { names[key] = "xml:" + components[1]; continue }
                while bindings["a\(index)"] != nil { index += 1 }
                bindings["a\(index)"] = components[0]
                names[key] = "a\(index):" + components[1]; index += 1
            } else { names[key] = key }
        }
        return SourceNames(qualifiedName: namespace.isEmpty ? name : prefix + ":" + name,
                           attributeNames: names, namespaceBindings: bindings)
    }
    package func descendants(_ name: String, namespaceSuffix: String? = nil) -> [MarkupNode] {
        var result: [MarkupNode] = [], pending = [content.makeIterator()]
        while !pending.isEmpty {
            guard let item = pending[pending.count - 1].next() else { pending.removeLast(); continue }
            if case .node(let node) = item {
                if node.name == name && (namespaceSuffix.map { node.namespace.hasSuffix($0) } ?? true) { result.append(node) }
                pending.append(node.content.makeIterator())
            }
        }
        return result
    }
    package var xml: String {
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: ">", with: "&gt;") }
        let names = normalizedNames, tag = names.qualifiedName
        var declarations = ""
        for (binding, uri) in names.namespaceBindings.sorted(by: { $0.key < $1.key }) where binding != "xml" {
            declarations += " xmlns\(binding.isEmpty ? "" : ":" + binding)=\"\(escape(uri))\""
        }
        var attrs = ""
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            attrs += " \(names.attributeNames[key]!)=\"\(escape(value))\""
        }
        let body = content.map { switch $0 { case .text(let s): escape(s); case .node(let n): n.xml } }.joined()
        return "<\(tag)\(declarations)\(attrs)>\(body)</\(tag)>"
    }
}

/// SAX builds one top-level body block at a time when a callback is supplied.
package enum XMLTree {
    package static func parse(_ data: Data, part: String, limits: PackageLimits, preserveSourceNames: Bool = false, onBodyChild: ((MarkupNode) throws -> Void)? = nil) throws -> MarkupNode {
        try Task.checkCancellation()
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian, .utf32LittleEndian, .utf32BigEndian] {
            for declaration in ["<!DOCTYPE", "<!ENTITY"] {
                if let pattern = declaration.data(using: encoding), data.range(of: pattern) != nil { throw DocumentError.invalidXML(part: part, detail: "DTD / entities are forbidden") }
            }
        }
        let delegate = TreeDelegate(part: part, limits: limits, preserveSourceNames: preserveSourceNames, callback: onBodyChild)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        let success = parser.parse()
        if let error = delegate.failure { throw error }
        try Task.checkCancellation()
        guard success, parser.parserError == nil, delegate.completed, delegate.stack.isEmpty,
              let root = delegate.root else { throw DocumentError.invalidXML(part: part, detail: parser.parserError?.localizedDescription ?? "incomplete XML") }
        return root
    }
}
private final class TreeDelegate: NSObject, XMLParserDelegate {
    let part: String
    let limits: PackageLimits
    let callback: ((MarkupNode) throws -> Void)?
    let preserveSourceNames: Bool
    var root: MarkupNode?
    var stack: [MarkupNode] = []
    var prefixes: [String: [String]] = ["xml": ["http://www.w3.org/XML/1998/namespace"]]
    var failure: (any Error)?
    var completed = false
    var nodes = 0
    init(part: String, limits: PackageLimits, preserveSourceNames: Bool, callback: ((MarkupNode) throws -> Void)?) { self.part = part; self.limits = limits; self.preserveSourceNames = preserveSourceNames; self.callback = callback }
    private func proceed(_ parser: XMLParser) -> Bool {
        guard failure == nil else { return false }
        if Task.isCancelled { failure = CancellationError(); parser.abortParsing(); return false }
        return true
    }
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
        // Linux Foundation can return true after reporting a recoverable libxml error.
        // Preserve an earlier callback or explicit limit failure when aborting parsing.
        if failure == nil { failure = DocumentError.invalidXML(part: part, detail: parseError.localizedDescription) }
    }
    func parserDidEndDocument(_ parser: XMLParser) { completed = true }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) { prefixes[prefix, default: []].append(namespaceURI) }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = prefixes[prefix]?.popLast() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard proceed(parser) else { return }
        nodes += 1
        guard nodes <= limits.maxXMLNodes, stack.count < limits.maxXMLDepth else { failure = DocumentError.limitExceeded("XML depth / node count in \(part)"); parser.abortParsing(); return }
        var attrs: [String: String] = [:]
        var attributeNames: [String: String] = [:]
        for (key, value) in attributeDict {
            let split = key.split(separator: ":", maxSplits: 1).map(String.init)
            if split.count == 2 {
                guard let uri = prefixes[split[0]]?.last else { failure = DocumentError.invalidXML(part: part, detail: "unbound attribute prefix"); parser.abortParsing(); return }
                attrs["\(uri)|\(split[1])"] = value
                if preserveSourceNames { attributeNames["\(uri)|\(split[1])"] = key }
            } else { attrs[key] = value; if preserveSourceNames { attributeNames[key] = key } }
        }
        let node = MarkupNode(name: elementName, namespace: namespaceURI ?? "", attributes: attrs)
        if preserveSourceNames {
            node.sourceNames = MarkupNode.SourceNames(qualifiedName: qName ?? elementName, attributeNames: attributeNames,
                namespaceBindings: prefixes.compactMapValues { $0.last })
        }
        let compatibility = "http://schemas.openxmlformats.org/markup-compatibility/2006"
        for (key, value) in attrs {
            let local = String(key.split(separator: "|").last!)
            let qname = key == "http://www.w3.org/2001/XMLSchema-instance|type" || key.hasPrefix(compatibility + "|") || (elementName == "Choice" && namespaceURI == compatibility && local == "Requires")
            if qname {
                for token in value.split(whereSeparator: \.isWhitespace) {
                    let binding = String(token.split(separator: ":", maxSplits: 1)[0])
                    if let uri = prefixes[binding]?.last { node.namespaceBindings[binding] = uri }
                }
            }
        }
        if let parent = stack.last { parent.content.append(.node(node)) }
        else {
            guard root == nil else { failure = DocumentError.invalidXML(part: part, detail: "multiple roots"); parser.abortParsing(); return }
            root = node
        }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard proceed(parser) else { return }
        guard let node = stack.last else { return }
        // Formatting whitespace must not accumulate on the body between emitted blocks.
        // Unknown mixed content keeps every text segment, including spaces between child elements.
        if !preserveSourceNames, node.isWord, !["t", "delText", "instrText", "delInstrText"].contains(node.name), string.allSatisfy(\.isWhitespace) { return }
        node.content.append(.text(string))
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard proceed(parser), let node = stack.popLast() else { return }
        guard node.name == elementName, node.namespace == (namespaceURI ?? "") else {
            failure = DocumentError.invalidXML(part: part, detail: "mismatched element boundary")
            parser.abortParsing(); return
        }
        if stack.count == 2, let parent = stack.last, parent.isWord, parent.name == "body", stack.first?.isWord == true, stack.first?.name == "document", let callback {
            do { try callback(node); try Task.checkCancellation(); parent.content.removeLast() }
            catch { failure = error; parser.abortParsing() }
        }
    }
}
