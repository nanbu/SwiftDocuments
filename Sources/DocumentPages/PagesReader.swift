import Foundation
import DocumentCore

/// Reads modern direct-Index Pages text, basic formatting, anchored tables and inline images; unsupported objects remain original assets.
public struct PagesCodec: DocumentCodec {
    public let format = DocumentFormat.pages
    public init() {}
    public func read(_ data: Data, options: ReadOptions = .init()) throws -> ReadResult {
        var blocks: [Block] = []
        var result = try scan(data, options: options) { blocks.append($0) }
        result.document.blocks = blocks
        return ReadResult(document: result.document)
    }
    public func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary {
        let reader = try PagesReader(data, options: ReadOptions(limits: limits))
        return DocumentSummary(format: .pages, metadata: DocumentMetadata(), parts: reader.parts)
    }
    public func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try PagesReader(data, options: options).scan(onBlock)
    }
}
extension Codec { public static let pages = Codec(PagesCodec()) }

final class PagesReader {
    let archive: PackageArchive
    let options: ReadOptions
    let warnings = WarningCollector()
    let budget: IWABudget
    var objects: [UInt64: IWAObject] = [:]
    var parsed: [UInt64: Proto] = [:]
    var styles: [String: DocumentStyle] = [:]
    var resolvedStyles: [UInt64: DocumentStyle] = [:]
    var characterResets: [UInt64: Set<Int>] = [:]
    var used: Set<UInt64> = []
    var diagnosed: Set<String> = []
    var storages: [UInt64: [Block]] = [:]
    var activeContent: Set<UInt64> = []
    var sectionIDs: Set<UInt64> = []
    var seenStories: Set<String> = []
    var tables: [UInt64: Table] = [:]
    var imageResources: [UInt64: (path: String, name: String)]?
    init(_ data: Data, options: ReadOptions) throws {
        self.options = options; budget = IWABudget(options.limits)
        archive = try PackageArchive(data, limits: options.limits)
        guard archive.entries["Index/Document.iwa"] != nil else { throw DocumentError.corruptedPackage("codec / MIME mismatch") }
        guard let root = try iwaObjects(archive.read("Index/Document.iwa"), part: "Index/Document.iwa", budget: budget, firstOnly: true).first,
              root.id == 1, root.type == 10000 else { throw DocumentError.corruptedPackage("codec / MIME mismatch") }
    }
    var parts: [PackagePart] {
        archive.paths.filter { !$0.hasSuffix("/") }.map { path in
            let entry = archive.entries[path]!
            return PackagePart(path: path, contentType: nil, compressedSize: entry.compressedSize, expandedSize: entry.expandedSize)
        }
    }
    func object(_ id: UInt64, type: UInt64? = nil) throws -> Proto {
        guard let record = objects[id], type == nil || record.type == type else { throw DocumentError.corruptedPackage("missing / wrong-type IWA object \(id)") }
        used.insert(id)
        if let cached = parsed[id] { return cached }
        let message = try Proto(record.bytes, budget: budget); parsed[id] = message
        return message
    }
    func unknown(_ message: Proto, known: Set<Int>, record: IWAObject, formatting: Bool = false, path: String = "") {
        for field in message.fields.keys.sorted() where !known.contains(field) {
            let element = "IWA.\(record.type)\(path).field\(field)"
            warnings.add(formatting ? .uninterpretedFormatting : .unsupportedContent, part: record.part, element: element, message: "Uninterpreted IWA field retained in original part.", count: message.fields[field]!.count)
        }
        if record.additionalMessages && diagnosed.insert("\(record.id):additionalMessages").inserted { warnings.add(.unsupportedContent, part: record.part, element: "IWA.additionalMessages", message: "Additional object messages retained in original IWA part.") }
    }
    func reference(_ message: Proto, _ field: Int, record: IWAObject, path: String = "") throws -> UInt64? {
        guard let value = try message.message(field, budget: budget) else { return nil }
        unknown(value, known: [1], record: record, path: path + ".field\(field)")
        guard let id = try value.integer(1), id > 0 else { throw DocumentError.corruptedPackage("invalid IWA object reference") }
        return id
    }
    func scan(_ callback: (Block) throws -> Void) throws -> ScanResult {
        // Inspection uses a separate bounded root probe; reset its decoded-byte accounting before the complete graph.
        budget.decodedBytes = 0; budget.fields = 0
        for part in archive.paths.filter({ $0.hasPrefix("Index/") && $0.hasSuffix(".iwa") }) {
            for record in try iwaObjects(archive.read(part), part: part, budget: budget) {
                guard objects.updateValue(record, forKey: record.id) == nil else { throw DocumentError.corruptedPackage("duplicate IWA object ID") }
            }
        }
        let root = try object(1, type: 10000)
        var document = Document(); document.sourceFormat = .pages; document.packageParts = parts
        document.attach(archive, limits: options.limits)
        unknown(root, known: [4, 5, 30, 31, 32, 33, 34, 35, 36, 37, 42], record: objects[1]!)
        var section = Section()
        section.pageWidth = try root.float(30); section.pageHeight = try root.float(31)
        section.margins["left"] = try root.float(32); section.margins["right"] = try root.float(33)
        section.margins["top"] = try root.float(34); section.margins["bottom"] = try root.float(35)
        section.margins["header"] = try root.float(36); section.margins["footer"] = try root.float(37)
        if let orientation = try root.integer(42) {
            if orientation <= 1 { section.orientation = orientation == 1 ? .landscape : .portrait }
            else { warnValue("orientation", record: objects[1]!) }
        }
        document.sections = [section]
        for id in objects.keys.sorted() where objects[id]!.type == 2021 || objects[id]!.type == 2022 { _ = try style(id) }
        var count = 0
        if let body = try reference(root, 4, record: objects[1]!) {
            let message = try object(body, type: 2001)
            guard try message.integer(1) == 0 else { throw DocumentError.corruptedPackage("Pages body reference is not BODY storage") }
            for block in try storage(body, cache: false) {
                try Task.checkCancellation(); try callback(block); try Task.checkCancellation(); count += 1
            }
        } else {
            var positioned = try [reference(root, 3, record: objects[1]!), reference(root, 20, record: objects[1]!)].compactMap { $0 }
            for bytes in try root.allData(48) {
                let reference = try Proto(bytes, budget: budget)
                unknown(reference, known: [1], record: objects[1]!, path: ".field48")
                guard let id = try reference.integer(1), id > 0 else { throw DocumentError.corruptedPackage("invalid Pages page-template reference") }
                positioned.append(id)
            }
            guard !positioned.isEmpty else { throw DocumentError.corruptedPackage("Pages document has neither body nor positioned content") }
            for id in positioned where objects[id] == nil { throw DocumentError.corruptedPackage("missing Pages positioned-content object") }
            warnings.add(.unsupportedContent, part: "Index/Document.iwa", element: "Pages.positionedContent", message: "No body storage: positioned layout objects remain original IWA data.")
        }
        // Only section-template references establish header/footer ownership; orphan storages never become stories.
        if let id = try reference(root, 5, record: objects[1]!) {
            sectionIDs.insert(id)
        }
        // Storage section boundaries are the ownership route used by Pages 15.4.
        var readSections = Set<UInt64>()
        while let id = sectionIDs.subtracting(readSections).min() {
            readSections.insert(id); try readSection(id, document: &document)
        }
        for id in objects.keys.sorted() where !used.contains(id) {
            let record = objects[id]!
            warnings.add(.unsupportedContent, part: record.part, element: "IWA.\(record.type)", message: "Unprojected IWA object retained in original part.")
        }
        document.styles = styles; document.readWarnings = warnings.result
        return ScanResult(document: document, blocksRead: count)
    }
    func readSection(_ id: UInt64, document: inout Document) throws {
        let value = try object(id, type: 10011)
        unknown(value, known: [23, 24, 25], record: objects[id]!)
        var seenTemplates = Set<UInt64>()
        for field in [23, 24, 25] {
            guard let templateID = try reference(value, field, record: objects[id]!) else { continue }
            guard seenTemplates.insert(templateID).inserted else { continue }
            let template = try object(templateID, type: 10143)
            unknown(template, known: [1, 2], record: objects[templateID]!)
            for kind in [1, 2] {
                for bytes in try template.allData(kind) {
                    let reference = try Proto(bytes, budget: budget)
                    unknown(reference, known: [1], record: objects[templateID]!, path: ".field\(kind)")
                    guard let storageID = try reference.integer(1), storageID > 0 else { throw DocumentError.corruptedPackage("missing Pages header reference") }
                    guard let record = objects[storageID], record.type == 2001 else { throw DocumentError.corruptedPackage("missing / wrong-type IWA object \(storageID)") }
                    guard seenStories.insert("\(kind):\(storageID)").inserted else { continue }
                    if options.includeRelatedStories {
                        document.stories.append(Story(id: String(storageID), kind: kind == 1 ? .header : .footer, sourcePart: objects[storageID]?.part ?? "Index/Document.iwa", blocks: try storage(storageID)))
                    } else { used.insert(storageID); warnings.add(.storiesOmitted, part: objects[storageID]?.part ?? "Index/Document.iwa", element: "Pages.headerFooter", message: "Related stories omitted by ReadOptions.") }
                }
            }
        }
    }
    func warnValue(_ field: String, record: IWAObject) {
        warnings.add(.uninterpretedFormatting, part: record.part, element: "Pages." + field, message: "Unsupported explicit property value retained in original part.")
    }
    func character(_ message: Proto, record: IWAObject) throws -> TextFormatting {
        unknown(message, known: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 35, 36, 37], record: record, formatting: true, path: ".field11")
        var f = TextFormatting()
        f.bold = try message.boolean(1); f.italic = try message.boolean(2)
        f.fontSize = try message.float(3); f.fontName = try message.string(5); f.language = try message.string(9)
        f.position = try message.float(14); f.kerning = try message.float(15)
        if let value = try message.integer(13) {
            if value <= 2 { f.allCaps = value == 1; f.smallCaps = value == 2 }
            else { warnValue("capitalization", record: record) }
        }
        f.rightToLeft = try writingDirection(message, field: 35, record: record)
        f.emphasis = try message.string(37)
        if let value = try message.integer(10) {
            if value <= 2 { f.verticalAlignment = value == 1 ? .superscript : value == 2 ? .subscript : .baseline }
            else { warnValue("verticalAlignment", record: record) }
        }
        if let value = try message.integer(11) {
            if value <= 3 { f.underline = ["none", "single", "double", "wave"][Int(value)] }
            else { warnValue("underline", record: record) }
        }
        if let value = try message.integer(12) {
            if value <= 3 { f.strike = value != 0 }
            if value > 1 { warnValue("strikethrough", record: record) }
        }
        if let color = try message.message(7, budget: budget) {
            unknown(color, known: [1, 3, 4, 5, 12], record: record, formatting: true, path: ".field11.field7")
            if try color.integer(1) == 1, try color.integer(12) ?? 1 == 1,
               let r = try color.float(3), let g = try color.float(4), let b = try color.float(5), [r, g, b].allSatisfy({ (0...1).contains($0) }) {
                f.color = [r, g, b].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
            } else { warnings.add(.uninterpretedFormatting, part: record.part, element: "Pages.color", message: "Unsupported color space retained in original part.") }
        }
        return f
    }
    func writingDirection(_ message: Proto, field: Int, record: IWAObject) throws -> Bool? {
        guard let value = try message.integer(field) else { return nil }
        if value <= 1 { return value == 1 }
        if value != UInt64.max { warnValue("writingDirection", record: record) }
        return nil
    }
    func clearCharacterProperties(_ fields: Set<Int>, in formatting: inout TextFormatting) {
        if fields.contains(4) { formatting.fontName = nil }
        if fields.contains(6) { formatting.color = nil }
        if fields.contains(8) { formatting.language = nil }
        if fields.contains(36) { formatting.emphasis = nil }
        if fields.contains(35) { formatting.rightToLeft = nil }
    }
    func style(_ id: UInt64, seen: Set<UInt64> = []) throws -> DocumentStyle {
        if let cached = resolvedStyles[id] { return cached }
        guard seen.count < min(128, options.limits.maxXMLDepth) else { throw DocumentError.limitExceeded("Pages style depth") }
        guard !seen.contains(id) else { throw DocumentError.corruptedPackage("Pages style inheritance cycle") }
        let value = try object(id)
        let record = objects[id]!
        guard record.type == 2021 || record.type == 2022 else { throw DocumentError.corruptedPackage("invalid Pages style reference") }
        let superStyle = try value.message(1, budget: budget)
        if let superStyle { unknown(superStyle, known: [1, 3], record: record, formatting: true, path: ".field1") }
        let parent = try superStyle.flatMap { try reference($0, 3, record: record, path: ".field1") }
        var result = DocumentStyle(id: String(id), name: try superStyle?.string(1) ?? String(id), kind: record.type == 2021 ? "character" : "paragraph", basedOn: parent.map(String.init))
        var declared = result
        var resets = Set<Int>()
        if let parent {
            let inherited = try style(parent, seen: seen.union([id])); result.text = inherited.text; result.paragraph = inherited.paragraph
            resets = characterResets[parent] ?? []
        }
        if let properties = try value.message(11, budget: budget) {
            declared.text = try character(properties, record: record); result.text.merge(declared.text)
            for (flag, hasValue) in [(4, declared.text.fontName != nil), (6, declared.text.color != nil), (8, declared.text.language != nil), (36, declared.text.emphasis != nil)] {
                if try properties.boolean(flag) == true { resets.insert(flag) }
                else if hasValue { resets.remove(flag) }
            }
            if try properties.integer(35) == UInt64.max { resets.insert(35) }
            else if declared.text.rightToLeft != nil { resets.remove(35) }
            clearCharacterProperties(resets, in: &result.text)
            clearCharacterProperties(resets, in: &declared.text)
        }
        if let p = try value.message(12, budget: budget) {
            unknown(p, known: [1, 7, 9, 10, 11, 12, 13, 14, 19, 20, 21, 24, 25, 26, 27, 38], record: record, formatting: true, path: ".field12")
            var f = ParagraphFormatting()
            if let alignment = try p.integer(1) {
                f.alignment = [0: .left, 1: .right, 2: .center, 3: .justified, 4: .start][alignment]
                if f.alignment == nil { warnValue("alignment", record: record) }
            }
            f.firstLineIndent = try p.float(7); f.indentLeft = try p.float(11); f.indentRight = try p.float(19)
            f.spacingAfter = try p.float(20); f.spacingBefore = try p.float(21)
            f.keepTogether = try p.boolean(9); f.keepWithNext = try p.boolean(10); f.pageBreakBefore = try p.boolean(14); f.widowControl = try p.boolean(26)
            f.rightToLeft = try writingDirection(p, field: 38, record: record)
            if let level = try p.integer(27) {
                guard level <= UInt64(Int.max) else { throw DocumentError.corruptedPackage("invalid Pages outline level") }; f.outlineLevel = Int(level)
            }
            if let tabs = try p.message(25, budget: budget) {
                unknown(tabs, known: [1], record: record, formatting: true, path: ".field12.field25")
                f.tabs = []
                for bytes in try tabs.allData(1) {
                    let tab = try Proto(bytes, budget: budget)
                    unknown(tab, known: [1, 2, 3], record: record, formatting: true, path: ".field12.field25.field1")
                    let alignment = try tab.integer(2) ?? 0
                    guard let position = try tab.float(1), alignment <= 3 else { warnValue("tabStop", record: record); continue }
                    f.tabs?.append(TabStop(position: position, alignment: ["left", "center", "right", "decimal"][Int(alignment)], leader: try tab.string(3)))
                }
            }
            if let line = try p.message(13, budget: budget) {
                unknown(line, known: [1, 2], record: record, formatting: true, path: ".field12.field13")
                let amount = try line.float(2), mode = try line.integer(1) ?? 0
                if let amount, mode <= 2 { f.lineSpacing = amount; f.lineSpacingRule = mode == 0 ? .multiple : mode == 1 ? .atLeast : .exact }
                else { warnValue("lineSpacing", record: record) }
            }
            declared.paragraph = f; result.paragraph.merge(f)
            if try p.boolean(12) == true { result.paragraph.lineSpacing = nil; result.paragraph.lineSpacingRule = nil; declared.paragraph.lineSpacing = nil; declared.paragraph.lineSpacingRule = nil }
            if try p.boolean(24) == true { result.paragraph.tabs = nil; declared.paragraph.tabs = nil }
            if try p.integer(38) == UInt64.max { result.paragraph.rightToLeft = nil }
        }
        unknown(value, known: [1, 11, 12], record: record, formatting: true)
        styles[result.id] = declared; resolvedStyles[id] = result; characterResets[id] = resets
        return result
    }
    func boundaries(_ message: Proto, field: Int, text: String, record: IWAObject) throws -> [(Int, UInt64?)] {
        guard let table = try message.message(field, budget: budget) else { return [] }
        unknown(table, known: [1], record: record, path: ".field\(field)")
        var result: [(Int, UInt64?)] = [], previous = -1
        let units = Array(text.utf16)
        for entry in try table.allData(1) {
            let value = try Proto(entry, budget: budget)
            unknown(value, known: [1, 2], record: record, path: ".field\(field).field1")
            guard let raw = try value.integer(1), raw <= UInt64(units.count), Int(raw) > previous else { throw DocumentError.corruptedPackage("invalid Pages text boundary") }
            let offset = Int(raw)
            if offset > 0 && offset < units.count && (0xD800...0xDBFF).contains(units[offset - 1]) && (0xDC00...0xDFFF).contains(units[offset]) { throw DocumentError.corruptedPackage("Pages boundary splits surrogate pair") }
            let styleID = try reference(value, 2, record: record, path: ".field\(field).field1")
            if let styleID {
                if field == 5 || field == 8 {
                    guard objects[styleID]?.type == (field == 5 ? 2022 : 2021) else { throw DocumentError.corruptedPackage("invalid Pages style reference") }
                    _ = try style(styleID)
                } else {
                    _ = try object(styleID, type: field == 17 ? 10011 : nil)
                    if field == 17 { sectionIDs.insert(styleID) }
                }
            }
            result.append((offset, styleID)); previous = offset
        }
        return result
    }
    func languageBoundaries(_ message: Proto, text: String, record: IWAObject) throws -> [(Int, String?)] {
        guard let table = try message.message(19, budget: budget) else { return [] }
        unknown(table, known: [1], record: record, path: ".field19")
        let units = Array(text.utf16)
        var result: [(Int, String?)] = [], previous = -1
        for bytes in try table.allData(1) {
            let entry = try Proto(bytes, budget: budget)
            unknown(entry, known: [1, 2], record: record, path: ".field19.field1")
            guard let raw = try entry.integer(1), raw <= UInt64(units.count), Int(raw) > previous else { throw DocumentError.corruptedPackage("invalid Pages language boundary") }
            let offset = Int(raw)
            if offset > 0 && offset < units.count && (0xD800...0xDBFF).contains(units[offset - 1]) && (0xDC00...0xDFFF).contains(units[offset]) { throw DocumentError.corruptedPackage("Pages boundary splits surrogate pair") }
            result.append((offset, try entry.string(2))); previous = offset
        }
        return result
    }
    func storage(_ id: UInt64, cache: Bool = true) throws -> [Block] {
        try enterContent(id)
        defer { activeContent.remove(id) }
        if let cached = storages[id] { return cached }
        let message = try object(id, type: 2001), record = objects[id]!
        unknown(message, known: [1, 3, 5, 8, 9, 17, 19], record: record)
        let chunks = try message.allData(3)
        var text = ""
        for chunk in chunks { guard let value = String(bytes: chunk, encoding: .utf8) else { throw DocumentError.corruptedPackage("invalid Pages text UTF-8") }; text += value }
        let paragraphStyles = try boundaries(message, field: 5, text: text, record: record), characterStyles = try boundaries(message, field: 8, text: text, record: record)
        let languages = try languageBoundaries(message, text: text, record: record)
        let units = Array(text.utf16)
        _ = try boundaries(message, field: 17, text: text, record: record)
        let anchors = try boundaries(message, field: 9, text: text, record: record)
        var attachments: [Int: UInt64] = [:]
        for (offset, target) in anchors {
            guard offset < units.count else { throw DocumentError.corruptedPackage("Pages attachment outside storage text") }
            if units[offset] == 0xFFFC {
                guard let target else { throw DocumentError.corruptedPackage("missing Pages attachment reference") }
                attachments[offset] = target
            } else {
                warnings.add(.unsupportedContent, part: record.part, element: "IWA.2001.field9", message: "Non-marker attachment variant retained in original IWA part.")
            }
        }
        var result: [Block] = [], start = 0, paraIndex = 0, charIndex = 0, languageIndex = 0
        func active<Value>(_ values: [(Int, Value?)], index: inout Int, at offset: Int) -> Value? {
            while index + 1 < values.count && values[index + 1].0 <= offset { index += 1 }
            return values.indices.contains(index) && values[index].0 <= offset ? values[index].1 : nil
        }
        repeat {
            try budget.charge()
            var end = start
            while end < units.count && units[end] != 10 && units[end] != 13 && units[end] != 0x2029 { end += 1 }
            var tableBlock: Table?
            var isolatedInline: Inline?
            if end == start + 1, let target = attachments[start] {
                switch try attachment(target, allowTable: true) {
                case .table(let table): tableBlock = table
                case .inline(let inline): isolatedInline = inline
                }
            }
            var p = Paragraph()
            if let styleID = active(paragraphStyles, index: &paraIndex, at: start) {
                let value = try style(styleID); p.styleID = value.id; p.formatting = value.paragraph; p.defaultTextFormatting = value.text
            }
            var position = start
            while position < end && tableBlock == nil {
                try budget.charge()
                let paraID = active(paragraphStyles, index: &paraIndex, at: position)
                let charID = active(characterStyles, index: &charIndex, at: position)
                var f = p.defaultTextFormatting
                if let paraID { f = try style(paraID).text }
                if let charID { f.merge(try style(charID).text); clearCharacterProperties(characterResets[charID] ?? [], in: &f) }
                if let language = active(languages, index: &languageIndex, at: position) { f.language = language }
                func nextBoundary<Value>(_ values: [(Int, Value?)], _ index: Int) -> Int {
                    if values.indices.contains(index), values[index].0 > position { return values[index].0 }
                    return values.indices.contains(index + 1) ? values[index + 1].0 : end
                }
                let nextPara = nextBoundary(paragraphStyles, paraIndex)
                let nextChar = nextBoundary(characterStyles, charIndex)
                var stop = min(end, nextPara, nextChar, nextBoundary(languages, languageIndex))
                if stop <= position { stop = end }
                var cursor = position, runStart = cursor
                while cursor < stop {
                    let control: Inline?
                    switch units[cursor] { case 9: control = .tab; case 5: control = .lineBreak(.page); case 11, 0x2028: control = .lineBreak(.line); default: control = nil }
                    if let target = attachments[cursor] {
                        if runStart < cursor { p.inlines.append(.text(TextRun(String(decoding: units[runStart..<cursor], as: UTF16.self), formatting: f))) }
                        if cursor == start, let isolatedInline { p.inlines.append(isolatedInline) }
                        else if case .inline(let inline) = try attachment(target, allowTable: false) { p.inlines.append(inline) }
                        cursor += 1; runStart = cursor
                    } else if let control {
                        if runStart < cursor { p.inlines.append(.text(TextRun(String(decoding: units[runStart..<cursor], as: UTF16.self), formatting: f))) }
                        p.inlines.append(control); cursor += 1; runStart = cursor
                    } else { cursor += 1 }
                }
                if runStart < stop { p.inlines.append(.text(TextRun(String(decoding: units[runStart..<stop], as: UTF16.self), formatting: f))) }
                position = stop
            }
            result.append(tableBlock.map(Block.table) ?? .paragraph(p))
            if end >= units.count { break }
            start = end + 1
            if units[end] == 13 && start < units.count && units[start] == 10 { start += 1 }
        } while start < units.count
        if cache { storages[id] = result }
        return result
    }
    func enterContent(_ id: UInt64) throws {
        guard !activeContent.contains(id) else { throw DocumentError.corruptedPackage("Pages content reference cycle") }
        guard activeContent.count < options.limits.maxXMLDepth else { throw DocumentError.limitExceeded("Pages content depth") }
        activeContent.insert(id)
    }
}
