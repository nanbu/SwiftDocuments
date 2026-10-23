import Foundation
import DocumentCore

struct PagesCellDataList {
    var entries: [UInt64: Proto] = [:]
    var hasSegments = false
}

extension PagesReader {
    func table(_ id: UInt64) throws -> Table {
        try enterContent(id)
        defer { activeContent.remove(id) }
        if let cached = tables[id] { return cached }
        let info = try object(id, type: 6000), infoRecord = objects[id]!
        unknown(info, known: [1, 2], record: infoRecord)
        let size = try drawableSize(info, record: infoRecord)
        guard let modelID = try reference(info, 2, record: infoRecord) else { throw DocumentError.corruptedPackage("missing Pages table model") }
        let model = try object(modelID, type: 6001), record = objects[modelID]!
        unknown(model, known: [4, 6, 7, 9, 16, 17], record: record)
        guard let rows = try model.integer(6), let columns = try model.integer(7), rows > 0, columns > 0,
              rows <= UInt64(options.limits.maxXMLNodes), columns <= UInt64(options.limits.maxXMLNodes),
              rows <= UInt64(options.limits.maxXMLNodes) / columns else { throw DocumentError.limitExceeded("Pages table dimensions") }
        let rowCount = Int(rows), columnCount = Int(columns)
        try budget.charge(rowCount * columnCount)
        let headerRows = try model.integer(9) ?? 0
        guard headerRows <= rows else { throw DocumentError.corruptedPackage("invalid Pages header row count") }
        let defaultHeight = try model.double(16), defaultWidth = try model.double(17)
        guard defaultHeight.map({ $0 >= 0 }) ?? true, defaultWidth.map({ $0 >= 0 }) ?? true,
              let store = try model.message(4, budget: budget) else { throw DocumentError.corruptedPackage("invalid Pages table data store") }
        unknown(store, known: [1, 2, 3, 4, 17], record: record, path: ".field4")
        var result = Table()
        result.preferredWidth = size.0.map { TableWidth(value: $0) }
        result.columns = Array(repeating: TableColumn(width: defaultWidth), count: columnCount)
        result.rows = (0..<rowCount).map { index in
            var row = TableRow(); row.height = defaultHeight; row.isHeader = index < Int(headerRows)
            row.cells = Array(repeating: TableCell(), count: columnCount); return row
        }
        if let headers = try store.message(1, budget: budget) {
            unknown(headers, known: [1, 2], record: record, path: ".field4.field1")
            var seen = Set<Int>()
            for bytes in try headers.allData(2) {
                let ref = try Proto(bytes, budget: budget)
                unknown(ref, known: [1], record: record, path: ".field4.field1.field2")
                guard let bucketID = try ref.integer(1), bucketID > 0 else { throw DocumentError.corruptedPackage("invalid Pages row header bucket") }
                for (index, height) in try tableHeaders(bucketID, count: rowCount) {
                    guard seen.insert(index).inserted else { throw DocumentError.corruptedPackage("duplicate Pages row header") }
                    result.rows[index].height = height
                }
            }
        }
        if let columnHeaders = try reference(store, 2, record: record, path: ".field4") {
            for (index, width) in try tableHeaders(columnHeaders, count: columnCount) { result.columns[index].width = width }
        }
        let strings = try tableDataList(store, field: 4, listType: 1, record: record)
        let rich = try tableDataList(store, field: 17, listType: 8, record: record)
        guard let tiles = try store.message(3, budget: budget) else { throw DocumentError.corruptedPackage("missing Pages tile storage") }
        unknown(tiles, known: [1, 2], record: record, path: ".field4.field3")
        let tileSize = try tiles.integer(2) ?? 256
        guard tileSize > 0, tileSize <= UInt64(Int.max) else { throw DocumentError.corruptedPackage("invalid Pages tile size") }
        var seenTiles = Set<UInt64>(), seenRows = Set<Int>()
        for bytes in try tiles.allData(1) {
            let entry = try Proto(bytes, budget: budget)
            unknown(entry, known: [1, 2], record: record, path: ".field4.field3.field1")
            guard let index = try entry.integer(1), index <= UInt64(rowCount - 1) / tileSize, seenTiles.insert(index).inserted,
                  let tileID = try reference(entry, 2, record: record) else { throw DocumentError.corruptedPackage("invalid / duplicate Pages tile") }
            let tile = try object(tileID, type: 6002), tileRecord = objects[tileID]!
            unknown(tile, known: [4, 5, 6, 7], record: tileRecord)
            for bytes in try tile.allData(5) {
                let row = try Proto(bytes, budget: budget)
                unknown(row, known: [1, 2, 5, 6, 7, 8], record: tileRecord, path: ".field5")
                guard let local = try row.integer(1), local < tileSize,
                      local < rows - index * tileSize else { throw DocumentError.corruptedPackage("Pages tile row out of bounds") }
                let global = Int(index * tileSize + local)
                guard seenRows.insert(global).inserted else { throw DocumentError.corruptedPackage("duplicate Pages tile row") }
                guard try row.integer(5) ?? tile.integer(6) == 5 else {
                    for column in 0..<columnCount { result.rows[global].cells[column].blocks = [opaqueCell(tileRecord, reason: "cellVersion")] }
                    continue
                }
                guard let buffer = try row.data(6), let offsets = try row.data(7), offsets.count % 2 == 0 else { throw DocumentError.corruptedPackage("missing / invalid Pages cell buffers") }
                try budget.charge(offsets.count / 2)
                let factor = try row.boolean(8) == true ? 4 : 1
                var positions: [(column: Int, offset: Int)] = [], previous = -1
                for column in 0..<(offsets.count / 2) {
                    let value = Int(offsets[column * 2]) | Int(offsets[column * 2 + 1]) << 8
                    if value == 0xFFFF { continue }
                    let offset = value * factor
                    guard value < 0x8000, column < columnCount, offset < buffer.count, offset > previous else { throw DocumentError.corruptedPackage("invalid Pages cell offset") }
                    positions.append((column, offset)); previous = offset
                }
                guard let declared = try row.integer(2), declared == UInt64(positions.count), positions.first?.offset ?? buffer.count == 0 else { throw DocumentError.corruptedPackage("Pages cell count / buffer mismatch") }
                for (position, cell) in positions.enumerated() {
                    let end = position + 1 < positions.count ? positions[position + 1].offset : buffer.count
                    result.rows[global].cells[cell.column].blocks = try tableCell(Array(buffer[cell.offset..<end]), strings: strings, rich: rich, record: tileRecord)
                }
            }
        }
        tables[id] = result; return result
    }

    func tableHeaders(_ id: UInt64, count: Int) throws -> [(Int, Double)] {
        let bucket = try object(id, type: 6006), record = objects[id]!
        unknown(bucket, known: [1, 2], record: record)
        var result: [(Int, Double)] = [], seen = Set<Int>()
        for bytes in try bucket.allData(2) {
            let header = try Proto(bytes, budget: budget)
            unknown(header, known: [1, 2], record: record, path: ".field2")
            guard let index = try header.integer(1), index < UInt64(count), seen.insert(Int(index)).inserted,
                  let size = try header.float(2), size >= 0 else { throw DocumentError.corruptedPackage("invalid Pages table header") }
            result.append((Int(index), size))
        }
        return result
    }

    func tableDataList(_ store: Proto, field: Int, listType: UInt64, record: IWAObject) throws -> PagesCellDataList {
        guard let id = try reference(store, field, record: record, path: ".field4") else { return PagesCellDataList() }
        let list = try object(id, type: 6005), listRecord = objects[id]!
        guard try list.integer(1) == listType else { throw DocumentError.corruptedPackage("wrong Pages cell data-list type") }
        unknown(list, known: [1, 2, 3], record: listRecord)
        var result = PagesCellDataList()
        for bytes in try list.allData(4) {
            let ref = try Proto(bytes, budget: budget)
            unknown(ref, known: [1], record: listRecord, path: ".field4")
            guard let target = try ref.integer(1), objects[target] != nil else { throw DocumentError.corruptedPackage("missing Pages data-list segment") }
            result.hasSegments = true
        }
        for bytes in try list.allData(3) {
            let entry = try Proto(bytes, budget: budget)
            unknown(entry, known: [1, 2, listType == 1 ? 3 : 9], record: listRecord, path: ".field3")
            if listType == 8 { _ = try reference(entry, 9, record: listRecord, path: ".field3") }
            guard let key = try entry.integer(1), result.entries.updateValue(entry, forKey: key) == nil else { throw DocumentError.corruptedPackage("duplicate / missing Pages cell data key") }
        }
        return result
    }

    func opaqueCell(_ record: IWAObject, reason: String, text: String = "") -> Block {
        warnings.add(.unsupportedContent, part: record.part, element: "Pages." + reason, message: "Unsupported cell semantics retained in original IWA part.")
        return .unsupported(UnsupportedContent(name: "IWA." + reason, sourcePart: record.part, rawXML: "", text: text))
    }

    func tableCell(_ bytes: [UInt8], strings: PagesCellDataList, rich: PagesCellDataList, record: IWAObject) throws -> [Block] {
        guard bytes.count >= 12 else { throw DocumentError.corruptedPackage("truncated Pages cell") }
        guard bytes[0] == 5 else { return [opaqueCell(record, reason: "cellVersion")] }
        func integer(_ offset: Int, _ count: Int) throws -> UInt64 {
            guard offset <= bytes.count, count <= bytes.count - offset else { throw DocumentError.corruptedPackage("truncated Pages cell value") }
            return (0..<count).reduce(0) { $0 | UInt64(bytes[offset + $1]) << (8 * $1) }
        }
        let flags = try integer(8, 4)
        guard flags & ~UInt64(0x1FFFFF) == 0 else { return [opaqueCell(record, reason: "cellFlags")] }
        var position = 12, decimal: String?, number: Double?, date: Double?, ids: [Int: UInt64] = [:]
        if flags & 1 != 0 {
            guard bytes.count - position >= 16 else { throw DocumentError.corruptedPackage("truncated Pages decimal") }
            decimal = try pagesDecimal(Array(bytes[position..<(position + 16)])); position += 16
        }
        for bit in 1...20 where flags & (1 << bit) != 0 {
            if bit <= 2 {
                let value = Double(bitPattern: try integer(position, 8)); position += 8
                guard value.isFinite else { throw DocumentError.corruptedPackage("non-finite Pages cell number") }
                if bit == 1 { number = value } else { date = value }
            } else { ids[bit] = try integer(position, 4); position += 4 }
        }
        // Wide-offset records may have up to three zero padding bytes.
        if bytes.count - position > 3 || bytes[position...].contains(where: { $0 != 0 }) {
            warnings.add(.unsupportedContent, part: record.part, element: "Pages.cellExtension", message: "Unprojected cell bytes retained in original IWA part.")
        }
        if bytes[2..<8].contains(where: { $0 != 0 }) || ids.keys.contains(where: { $0 >= 5 }) {
            warnings.add(.uninterpretedFormatting, part: record.part, element: "Pages.cellProperties", message: "Cell styles, formulas and display formats retained; cached values are not recalculated or locale-formatted.")
        }
        var text: String?
        switch bytes[1] {
        case 0:
            if decimal == nil && number == nil && date == nil && ids[3] == nil && ids[4] == nil { return [] }
            return [opaqueCell(record, reason: "cellKind")]
        case 3:
            guard let key = ids[3] else { throw DocumentError.corruptedPackage("missing Pages cell string key") }
            if strings.entries[key] == nil && strings.hasSegments { return [opaqueCell(record, reason: "segmentedCellData")] }
            guard let entry = strings.entries[key], let string = try entry.string(3) else { throw DocumentError.corruptedPackage("missing Pages cell string") }
            text = string
        case 9:
            guard let key = ids[4] else { throw DocumentError.corruptedPackage("missing Pages rich cell key") }
            if rich.entries[key] == nil && rich.hasSegments { return [opaqueCell(record, reason: "segmentedCellData")] }
            guard let entry = rich.entries[key], let payloadID = try entry.reference(9, budget: budget) else { throw DocumentError.corruptedPackage("missing Pages rich cell payload") }
            let payload = try object(payloadID, type: 6218), payloadRecord = objects[payloadID]!
            unknown(payload, known: [1], record: payloadRecord)
            guard let storageID = try reference(payload, 1, record: payloadRecord) else { throw DocumentError.corruptedPackage("missing Pages cell storage") }
            let value = try object(storageID, type: 2001)
            guard try value.integer(1) == 5 else { throw DocumentError.corruptedPackage("Pages cell reference is not CELL storage") }
            if payload.fields[2] != nil { return [opaqueCell(payloadRecord, reason: "richTextRange")] }
            return try storage(storageID)
        case 2, 10: text = decimal ?? number.map { String($0) }
        case 6:
            guard let number, number == 0 || number == 1 else { throw DocumentError.corruptedPackage("invalid Pages boolean cell") }
            text = number == 1 ? "TRUE" : "FALSE"
        case 5:
            guard let date else { throw DocumentError.corruptedPackage("missing Pages date cell value") }
            // Retain the exact cached scalar; date display patterns require additional format semantics.
            return [opaqueCell(record, reason: "dateCell", text: String(date))]
        case 7:
            guard let number else { throw DocumentError.corruptedPackage("missing Pages duration value") }
            return [opaqueCell(record, reason: "durationCell", text: String(number))]
        default: return [opaqueCell(record, reason: "cellKind")]
        }
        guard let text else { throw DocumentError.corruptedPackage("missing Pages numeric cell value") }
        var paragraph = Paragraph(); paragraph.inlines = [.text(TextRun(text))]
        return [.paragraph(paragraph)]
    }
}

// Decode the iWork decimal coefficient without converting through binary floating point.
func pagesDecimal(_ bytes: [UInt8]) throws -> String {
    let exponentBits = Int(bytes[15] & 0x7F) << 7 | Int(bytes[14] >> 1)
    guard exponentBits < 0x3000 else { throw DocumentError.corruptedPackage("unsupported Pages decimal encoding") }
    var digits = [0]
    for byte in [bytes[14] & 1] + bytes[0..<14].reversed() {
        var carry = Int(byte)
        for index in digits.indices { let value = digits[index] * 256 + carry; digits[index] = value % 10; carry = value / 10 }
        while carry > 0 { digits.append(carry % 10); carry /= 10 }
    }
    while digits.count > 1 && digits.last == 0 { digits.removeLast() }
    let exponent = exponentBits - 0x1820
    var coefficient = digits.reversed().map(String.init).joined()
    if coefficient == "0" { return bytes[15] & 0x80 == 0 ? "0" : "-0" }
    var normalizedExponent = exponent
    while coefficient.last == "0" { coefficient.removeLast(); normalizedExponent += 1 }
    if normalizedExponent >= 0 && coefficient.count + normalizedExponent <= 40 { coefficient += String(repeating: "0", count: normalizedExponent) }
    else if normalizedExponent < 0 && normalizedExponent > -40 {
        let index = coefficient.count + normalizedExponent
        if index > 0 { coefficient.insert(".", at: coefficient.index(coefficient.startIndex, offsetBy: index)) }
        else { coefficient = "0." + String(repeating: "0", count: -index) + coefficient }
    } else { coefficient += "E" + String(normalizedExponent) }
    return (bytes[15] & 0x80 == 0 ? "" : "-") + coefficient
}
