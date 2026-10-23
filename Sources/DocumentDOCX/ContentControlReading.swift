import Foundation
import DocumentCore

private let control2010 = "http://schemas.microsoft.com/office/word/2010/wordml"
private let control2013 = "http://schemas.microsoft.com/office/word/2012/wordml"

extension StoryReader {
    func blockControl(_ node: MarkupNode) throws -> ContentControl {
        let descriptor = try controlDescriptor(node), content = try storyBlocks(controlChildren(node))
        if case .paragraph(let paragraph) = content.last, let change = paragraph.paragraphMarkRevision,
           (options.revisions == .final && change.kind == .deletion) || (options.revisions == .original && change.kind == .insertion) {
            warnings.add(.unsupportedContent, part: part, element: "controlParagraphMarkJoin", message: "Cross-control paragraph-mark join retained as a source revision; the control boundary is preserved.")
        }
        return ContentControl(descriptor: descriptor, content: .blocks(content))
    }
    func controlChildren(_ node: MarkupNode) throws -> [MarkupNode] {
        let content = node.wordChildren("sdtContent")
        guard content.count <= 1 else { throw DocumentError.invalidXML(part: part, detail: "duplicate control content") }
        return content.first?.children ?? []
    }
    func controlDescriptor(_ node: MarkupNode) throws -> ContentControlDescriptor {
        guard node.wordChildren("sdtPr").count <= 1, node.wordChildren("sdtEndPr").count <= 1 else {
            throw DocumentError.invalidXML(part: part, detail: "duplicate content control property container")
        }
        var result = ContentControlDescriptor(sourcePart: part)
        func attributes(_ node: MarkupNode, allowed: Set<String>) {
            if node.attributes.keys.contains(where: { key in
                let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                return !allowed.contains(parts.last!) || (parts.count == 2 && (node.isWord ? ![XMLNamespace.word, XMLNamespace.strictWord].contains(parts[0]) : parts[0] != node.namespace))
            }) { properties.unparsed(node, part: part) }
        }
        let header = MarkupNode(name: node.name, namespace: node.namespace, attributes: node.attributes)
        header.namespaceBindings = node.namespaceBindings
        header.content = node.content.filter { if case .node(let child) = $0 { return !(child.isWord && child.name == "sdtContent") }; return true }
        result.sourceHeader = try SourceXMLNode(header)
        if !node.attributes.isEmpty { properties.unparsed(node, part: part) }
        let source = node.child("sdtPr")
        if let source { attributes(source, allowed: []) }
        result.id = source?.child("id")?.value; result.title = source?.child("alias")?.value; result.tag = source?.child("tag")?.value
        if let lock = source?.child("lock") {
            result.editingLock = ["unlocked": .unlocked, "contentLocked": .content, "sdtLocked": .control, "sdtContentLocked": .contentAndControl][lock.value ?? ""] ?? .native
            if result.editingLock == .native { properties.unparsed(lock, part: part) }
        }
        result.isTemporary = source?.child("temporary")?.onOffValue
        result.isShowingPlaceholder = source?.child("showingPlcHdr")?.onOffValue
        result.placeholderName = source?.child("placeholder")?.child("docPart")?.value
        if let formatting = source?.child("rPr") { result.formatting = properties.text(formatting, part: part) }
        if let formatting = node.child("sdtEndPr")?.child("rPr") { result.endFormatting = properties.text(formatting, part: part) }
        if let binding = source?.child("dataBinding") {
            result.binding = ContentBinding(storeID: binding.attr("storeItemID"), pathQuery: binding.attr("xpath"), namespaceMappings: binding.attr("prefixMappings"))
            warnings.add(.unsupportedContent, part: part, element: "dataBinding", message: "Binding metadata and cached content retained; queries are not executed.")
            attributes(binding, allowed: ["storeItemID", "xpath", "prefixMappings"])
            for child in binding.children { properties.unparsed(child, part: part) }
        }
        let kinds: [String: ContentControl.Kind] = ["richText": .richText, "text": .plainText, "picture": .picture, "date": .date,
            "comboBox": .comboBox, "dropDownList": .dropDownList, "group": .group, "citation": .citation,
            "bibliography": .bibliography, "equation": .equation, "docPartObj": .documentPart, "docPartList": .documentPart]
        var selectors: [MarkupNode] = []
        for child in source?.children ?? [] {
            if child.isWord, let kind = kinds[child.name] { result.kind = kind; selectors.append(child) }
            else if child.namespace == control2010, child.name == "checkbox" { result.kind = .checkBox; selectors.append(child) }
            else if child.namespace == control2013, ["repeatingSection", "repeatingSectionItem"].contains(child.name) {
                result.kind = child.name == "repeatingSection" ? .repeatingSection : .repeatingItem; selectors.append(child)
            }
        }
        guard selectors.count <= 1 else { throw DocumentError.invalidXML(part: part, detail: "conflicting content control types") }
        if let type = selectors.first {
            attributes(type, allowed: type.isWord && type.name == "text" ? ["multiLine"] : type.isWord && ["comboBox", "dropDownList"].contains(type.name) ? ["lastValue"] : type.isWord && type.name == "date" ? ["fullDate"] : [])
            if type.isWord, type.name == "text" { result.isMultiline = type.attr("multiLine").flatMap { MarkupNode.boolean($0) } }
            if type.isWord, type.name == "text", type.attr("multiLine") != nil, result.isMultiline == nil { properties.unparsed(type, part: part) }
            if type.isWord, ["comboBox", "dropDownList"].contains(type.name) {
                result.selectedValue = type.attr("lastValue")
                result.items = type.wordChildren("listItem").map { ContentControlItem(displayText: $0.attr("displayText"), value: $0.attr("value")) }
                for item in type.wordChildren("listItem") {
                    attributes(item, allowed: ["displayText", "value"])
                    for child in item.children { properties.unparsed(child, part: part) }
                }
                for child in type.children where !child.isWord || child.name != "listItem" { properties.unparsed(child, part: part) }
            }
            if type.isWord, type.name == "date" {
                result.dateValue = type.attr("fullDate"); result.dateFormat = type.child("dateFormat")?.value
                result.dateLanguage = type.child("lid")?.value; result.dateCalendar = type.child("calendar")?.value
                for child in type.children where child.isWord && ["dateFormat", "lid", "calendar"].contains(child.name) { attributes(child, allowed: ["val"]) }
                for child in type.children where !child.isWord || !["dateFormat", "lid", "calendar"].contains(child.name) { properties.unparsed(child, part: part) }
            }
            if type.namespace == control2010, type.name == "checkbox" {
                func value(_ node: MarkupNode?, _ name: String = "val") -> String? { node?.attributes[control2010 + "|" + name] ?? node?.attributes[name] }
                func child(_ name: String) -> MarkupNode? { type.children.first { $0.namespace == control2010 && $0.name == name } }
                if let checked = child("checked") {
                    result.isChecked = MarkupNode.boolean(value(checked))
                    if result.isChecked == nil { properties.unparsed(checked, part: part) }
                }
                func symbol(_ name: String) -> SymbolCharacter? {
                    guard let node = child(name) else { return nil }
                    guard let font = value(node, "font"), let code = value(node).flatMap({ UInt32($0, radix: 16) }) else { properties.unparsed(node, part: part); return nil }
                    return SymbolCharacter(fontName: font, characterCode: code)
                }
                result.checkedSymbol = symbol("checkedState"); result.uncheckedSymbol = symbol("uncheckedState")
                for child in type.children where child.namespace == control2010 && ["checked", "checkedState", "uncheckedState"].contains(child.name) {
                    attributes(child, allowed: child.name == "checked" ? ["val"] : ["val", "font"])
                    for nested in child.children { properties.unparsed(nested, part: part) }
                }
                for child in type.children where child.namespace != control2010 || !["checked", "checkedState", "uncheckedState"].contains(child.name) { properties.unparsed(child, part: part) }
            }
            if !["comboBox", "dropDownList", "date", "checkbox"].contains(type.name) {
                for child in type.children { properties.unparsed(child, part: part) }
            }
        }
        let simple: Set<String> = ["id", "alias", "tag", "lock", "temporary", "showingPlcHdr"]
        let handled: Set<String> = simple.union(["rPr", "placeholder", "dataBinding"])
        var seen = Set<String>()
        for child in source?.children ?? [] {
            if child.isWord, handled.contains(child.name), !seen.insert(child.name).inserted { throw DocumentError.invalidXML(part: part, detail: "duplicate control property") }
            if selectors.contains(where: { $0 === child }) { continue }
            if !child.isWord || !handled.contains(child.name) { properties.unparsed(child, part: part) }
            else if simple.contains(child.name), properties.hasExtraAttributes(child, allowed: ["val"]) || !child.children.isEmpty { properties.unparsed(child, part: part) }
            if child.isWord, ["temporary", "showingPlcHdr"].contains(child.name), child.onOffValue == nil { properties.unparsed(child, part: part) }
            if child.isWord, ["rPr", "placeholder"].contains(child.name) { attributes(child, allowed: []) }
            if child.isWord, child.name == "placeholder" {
                for nested in child.children {
                    if nested.isWord && nested.name == "docPart" { attributes(nested, allowed: ["val"]) }
                    else { properties.unparsed(nested, part: part) }
                }
            }
        }
        for child in node.children where !(child.isWord && ["sdtPr", "sdtEndPr", "sdtContent"].contains(child.name)) { properties.unparsed(child, part: part) }
        for child in node.child("sdtEndPr")?.children ?? [] where !child.isWord || child.name != "rPr" { properties.unparsed(child, part: part) }
        return result
    }
}
