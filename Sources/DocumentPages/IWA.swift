import Foundation
import DocumentCore

// This wire layer has no schema dependency. Length-delimited bytes are parsed as messages only by their owning schema.
final class IWABudget {
    let limits: PackageLimits
    var fields = 0
    var decodedBytes = 0
    init(_ limits: PackageLimits) { self.limits = limits }
    func charge(_ count: Int = 1) throws {
        try Task.checkCancellation()
        guard count >= 0, count <= limits.maxXMLNodes - fields else { throw DocumentError.limitExceeded("IWA messages / fields") }
        fields += count
    }
}
struct Proto {
    enum Value { case integer(UInt64), fixed32(UInt32), fixed64(UInt64), bytes([UInt8]) }
    var fields: [Int: [Value]] = [:]
    init(_ bytes: [UInt8], budget: IWABudget) throws {
        var position = 0
        while position < bytes.count {
            try budget.charge()
            let tag = try IWorkProbe.varint(bytes, &position)
            guard tag >> 3 > 0, tag >> 3 <= 536_870_911 else { throw DocumentError.corruptedPackage("invalid protobuf field tag") }
            let key = Int(tag >> 3), value: Value
            switch tag & 7 {
            case 0: value = .integer(try IWorkProbe.varint(bytes, &position))
            case 1, 5:
                let count = tag & 7 == 1 ? 8 : 4
                guard bytes.count - position >= count else { throw DocumentError.corruptedPackage("truncated protobuf fixed value") }
                var number: UInt64 = 0
                for i in 0..<count { number |= UInt64(bytes[position + i]) << (8 * i) }
                position += count; value = count == 8 ? .fixed64(number) : .fixed32(UInt32(number))
            case 2:
                let count = try IWorkProbe.varint(bytes, &position)
                guard count <= UInt64(bytes.count - position) else { throw DocumentError.corruptedPackage("truncated protobuf bytes") }
                value = .bytes(Array(bytes[position..<(position + Int(count))])); position += Int(count)
            default: throw DocumentError.corruptedPackage("unsupported protobuf wire type")
            }
            fields[key, default: []].append(value)
        }
    }
    func integer(_ key: Int) throws -> UInt64? {
        guard let values = fields[key] else { return nil }
        guard values.count == 1, case .integer(let result) = values[0] else { throw DocumentError.corruptedPackage("invalid singular protobuf integer") }
        return result
    }
    func boolean(_ key: Int) throws -> Bool? {
        guard let value = try integer(key) else { return nil }
        guard value <= 1 else { throw DocumentError.corruptedPackage("invalid Pages boolean") }
        return value == 1
    }
    func data(_ key: Int) throws -> [UInt8]? {
        guard let values = fields[key] else { return nil }
        guard values.count == 1, case .bytes(let result) = values[0] else { throw DocumentError.corruptedPackage("invalid singular protobuf message") }
        return result
    }
    func allData(_ key: Int) throws -> [[UInt8]] {
        try (fields[key] ?? []).map { value in
            guard case .bytes(let bytes) = value else { throw DocumentError.corruptedPackage("invalid repeated protobuf message") }; return bytes
        }
    }
    func string(_ key: Int) throws -> String? {
        guard let bytes = try data(key) else { return nil }
        guard let string = String(bytes: bytes, encoding: .utf8) else { throw DocumentError.corruptedPackage("invalid IWA UTF-8") }; return string
    }
    func float(_ key: Int) throws -> Double? {
        guard let values = fields[key] else { return nil }
        guard values.count == 1, case .fixed32(let bits) = values[0], Float(bitPattern: bits).isFinite else { throw DocumentError.corruptedPackage("invalid IWA finite float") }
        return Double(Float(bitPattern: bits))
    }
    func double(_ key: Int) throws -> Double? {
        guard let values = fields[key] else { return nil }
        guard values.count == 1, case .fixed64(let bits) = values[0], Double(bitPattern: bits).isFinite else { throw DocumentError.corruptedPackage("invalid IWA finite double") }
        return Double(bitPattern: bits)
    }
    func message(_ key: Int, budget: IWABudget) throws -> Proto? { try data(key).map { try Proto($0, budget: budget) } }
    func reference(_ key: Int, budget: IWABudget) throws -> UInt64? {
        guard let value = try message(key, budget: budget) else { return nil }
        guard let id = try value.integer(1), id > 0 else { throw DocumentError.corruptedPackage("invalid IWA object reference") }; return id
    }
}
struct IWAObject {
    let id: UInt64
    let type: UInt64
    let bytes: [UInt8]
    let part: String
    let additionalMessages: Bool
}
func iwaObjects(_ data: Data, part: String, budget: IWABudget, firstOnly: Bool = false) throws -> [IWAObject] {
    let decoded = try IWorkProbe.decodeChunks(data, limits: budget.limits)
    guard decoded.count <= budget.limits.maxExpandedBytes - budget.decodedBytes else { throw DocumentError.limitExceeded("aggregate expanded IWA bytes") }
    budget.decodedBytes += decoded.count
    var position = 0, result: [IWAObject] = []
    while position < decoded.count {
        try budget.charge()
        let size = try IWorkProbe.varint(decoded, &position)
        guard size > 0, size <= UInt64(decoded.count - position) else { throw DocumentError.corruptedPackage("invalid IWA archive header length") }
        let header = try Proto(Array(decoded[position..<(position + Int(size))]), budget: budget); position += Int(size)
        guard let id = try header.integer(1), id > 0 else { throw DocumentError.corruptedPackage("invalid IWA object ID") }
        let infos = try header.allData(2)
        guard !infos.isEmpty else { throw DocumentError.corruptedPackage("missing IWA message info") }
        for (index, bytes) in infos.enumerated() {
            let info = try Proto(bytes, budget: budget)
            guard let type = try info.integer(1), let length = try info.integer(3), length <= UInt64(decoded.count - position) else { throw DocumentError.corruptedPackage("invalid IWA message length / type") }
            if index == 0 { result.append(IWAObject(id: id, type: type, bytes: Array(decoded[position..<(position + Int(length))]), part: part, additionalMessages: infos.count > 1)) }
            position += Int(length)
        }
        if firstOnly { break }
    }
    return result
}
