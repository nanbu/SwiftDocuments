import Foundation

/// Identification only. Pages, Numbers and Keynote share ZIP filenames; a filename is not a format marker.
/// Pages uses TSP.MessageInfo.type 10000 for TP.DocumentArchive (see docs/format-design.md).
package enum IWorkProbe {
    package static func isPages(_ data: Data) throws -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0 else { throw DocumentError.corruptedPackage("invalid IWA chunk") }
        let length = Int(bytes[1]) | Int(bytes[2]) << 8 | Int(bytes[3]) << 16
        guard length > 0, length <= bytes.count - 4 else { throw DocumentError.corruptedPackage("truncated IWA chunk") }
        let expanded = try snappy(Array(bytes[4..<(4 + length)]))
        var p = 0
        let headerSize = try varint(expanded, &p)
        guard headerSize <= UInt64(expanded.count - p) else { throw DocumentError.corruptedPackage("invalid IWA archive header") }
        let header = Array(expanded[p..<(p + Int(headerSize))])
        let fields = try protobuf(header)
        guard fields.integers[1] == 1, let info = fields.messages[2]?.first else { return false }
        return try protobuf(info).integers[1] == 10000
    }
    private static func varint(_ b: [UInt8], _ p: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard p < b.count else { throw DocumentError.corruptedPackage("truncated IWA varint") }
            let n = b[p]; p += 1
            guard shift < 63 || n <= 1 else { throw DocumentError.corruptedPackage("IWA varint overflow") }
            value |= UInt64(n & 127) << shift
            if n & 128 == 0 { return value }
        }
        throw DocumentError.corruptedPackage("IWA varint overflow")
    }
    private static func protobuf(_ b: [UInt8]) throws -> (integers: [Int: UInt64], messages: [Int: [[UInt8]]]) {
        var p = 0, integers: [Int: UInt64] = [:], messages: [Int: [[UInt8]]] = [:]
        while p < b.count {
            let tag = try varint(b, &p)
            guard tag >> 3 > 0, tag >> 3 <= UInt64(Int.max) else { throw DocumentError.corruptedPackage("invalid IWA protobuf tag") }
            let field = Int(tag >> 3)
            switch tag & 7 {
            case 0: integers[field] = try varint(b, &p)
            case 1: guard b.count - p >= 8 else { throw DocumentError.corruptedPackage("truncated IWA fixed64") }; p += 8
            case 2:
                let n = try varint(b, &p)
                guard n <= UInt64(b.count - p) else { throw DocumentError.corruptedPackage("truncated IWA message") }
                messages[field, default: []].append(Array(b[p..<(p + Int(n))])); p += Int(n)
            case 5: guard b.count - p >= 4 else { throw DocumentError.corruptedPackage("truncated IWA fixed32") }; p += 4
            default: throw DocumentError.corruptedPackage("unsupported IWA wire type")
            }
        }
        return (integers, messages)
    }
    private static func snappy(_ b: [UInt8]) throws -> [UInt8] {
        var p = 0
        let declared = try varint(b, &p)
        // An iWork chunk normally expands to 64 KiB. Identification never needs a giant allocation.
        guard declared <= 1 << 20 else { throw DocumentError.limitExceeded("IWA probe chunk size") }
        let size = Int(declared)
        var out: [UInt8] = []; out.reserveCapacity(size)
        while p < b.count {
            let tag = b[p]; p += 1
            var n: Int, offset: Int
            switch tag & 3 {
            case 0:
                n = Int(tag >> 2) + 1
                if n > 60 {
                    let extra = n - 60
                    guard extra <= b.count - p else { throw DocumentError.corruptedPackage("short Snappy literal length") }
                    n = 0
                    for i in 0..<extra { n |= Int(b[p + i]) << (8 * i) }; p += extra; n += 1
                }
                guard n <= b.count - p, n <= size - out.count else { throw DocumentError.corruptedPackage("Snappy literal overflow") }
                out.append(contentsOf: b[p..<(p + n)]); p += n; continue
            case 1:
                guard p < b.count else { throw DocumentError.corruptedPackage("short Snappy copy") }
                n = Int((tag >> 2) & 7) + 4; offset = Int(tag & 224) << 3 | Int(b[p]); p += 1
            case 2:
                guard b.count - p >= 2 else { throw DocumentError.corruptedPackage("short Snappy copy") }
                n = Int(tag >> 2) + 1; offset = Int(b[p]) | Int(b[p + 1]) << 8; p += 2
            default:
                guard b.count - p >= 4 else { throw DocumentError.corruptedPackage("short Snappy copy") }
                n = Int(tag >> 2) + 1; offset = Int(b[p]) | Int(b[p + 1]) << 8 | Int(b[p + 2]) << 16 | Int(b[p + 3]) << 24; p += 4
            }
            guard offset > 0, offset <= out.count, n <= size - out.count else { throw DocumentError.corruptedPackage("Snappy copy overflow") }
            for _ in 0..<n { out.append(out[out.count - offset]) }
        }
        guard out.count == size else { throw DocumentError.corruptedPackage("Snappy size mismatch") }; return out
    }
}
