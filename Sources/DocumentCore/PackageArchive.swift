import Foundation
import CZlib

/// Immutable, memory-backed OPC ZIP. No files are extracted to disk.
package struct PackageArchive: Sendable {
    package struct Entry: Sendable {
        package let path: String
        package let compressedSize: Int
        package let expandedSize: Int
        let method: UInt16
        let crc: UInt32
        let payload: Range<Int>
    }
    private let data: Data
    package let entries: [String: Entry]
    package let paths: [String]

    package init(_ data: Data, limits: PackageLimits = .init()) throws {
        guard limits.maxEntries > 0, limits.maxExpandedBytes >= 0, limits.maxPartBytes >= 0 else {
            throw DocumentError.limitExceeded("limits must be nonnegative")
        }
        self.data = data.startIndex == 0 ? data : Data(data)
        let parsed = try data.withUnsafeBytes { raw -> ([String: Entry], [String]) in
            let b = raw.bindMemory(to: UInt8.self)
            func fail(_ s: String) -> DocumentError { .corruptedPackage(s) }
            func contains(_ offset: Int, _ length: Int) -> Bool { offset >= 0 && length >= 0 && offset <= b.count && length <= b.count - offset }
            func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
            func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
            func u64(_ i: Int) -> UInt64 { UInt64(u32(i)) | UInt64(u32(i + 4)) << 32 }
            func integer(_ n: UInt64) throws -> Int {
                guard n <= UInt64(Int.max) else { throw fail("ZIP64 integer overflow") }; return Int(n)
            }
            guard b.count >= 22 else { throw fail("missing ZIP end record") }
            var eocd: Int?
            for i in stride(from: b.count - 22, through: max(0, b.count - 65557), by: -1) {
                if u32(i) == 0x06054b50, i + 22 + Int(u16(i + 20)) == b.count { eocd = i; break }
            }
            guard let end = eocd else { throw fail("missing ZIP end record") }
            guard u16(end + 4) == 0, u16(end + 6) == 0, u16(end + 8) == u16(end + 10) else { throw fail("split ZIP is unsupported") }
            var count = Int(u16(end + 10)), size = Int(u32(end + 12)), offset = Int(u32(end + 16))
            var directoryEnd = end
            if end >= 20, u32(end - 20) == 0x07064b50 {
                guard u32(end - 16) == 0, u32(end - 4) == 1 else { throw fail("split ZIP64") }
                let z = try integer(u64(end - 12))
                guard contains(z, 56), u32(z) == 0x06064b50 else { throw fail("invalid ZIP64 end record") }
                let recordSize = try integer(u64(z + 4))
                guard recordSize >= 44, contains(z + 12, recordSize), z + 12 + recordSize == end - 20,
                      u32(z + 16) == 0, u32(z + 20) == 0, u64(z + 24) == u64(z + 32) else { throw fail("invalid ZIP64 layout") }
                count = try integer(u64(z + 32)); size = try integer(u64(z + 40)); offset = try integer(u64(z + 48)); directoryEnd = z
            } else if count == 65535 || size == Int(UInt32.max) || offset == Int(UInt32.max) { throw fail("ZIP64 markers without record") }
            guard count <= limits.maxEntries else { throw DocumentError.limitExceeded("ZIP entry count") }
            guard contains(offset, size), offset + size == directoryEnd else { throw fail("invalid ZIP directory bounds") }
            var p = offset, total = 0
            var entries: [String: Entry] = [:], paths: [String] = [], ranges: [Range<Int>] = []
            for _ in 0..<count {
                guard contains(p, 46), p + 46 <= directoryEnd, u32(p) == 0x02014b50 else { throw fail("invalid ZIP directory entry") }
                let flags = u16(p + 8), method = u16(p + 10), crc = u32(p + 16)
                guard flags & 0x0041 == 0 else { throw DocumentError.unsupportedContainer("encrypted ZIP") }
                guard method == 0 || method == 8 else { throw DocumentError.unsupportedContainer("ZIP method \(method)") }
                let nameSize = Int(u16(p + 28)), extraSize = Int(u16(p + 30)), commentSize = Int(u16(p + 32))
                let length = 46 + nameSize + extraSize + commentSize
                guard contains(p, length), p + length <= directoryEnd else { throw fail("ZIP directory entry overflow") }
                guard let name = String(bytes: b[(p + 46)..<(p + 46 + nameSize)], encoding: .utf8), !name.isEmpty,
                      !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"), !name.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
                      !name.split(separator: "/").contains("."), !name.contains("//"), !name.contains(":") else { throw fail("unsafe ZIP part name") }
                guard entries[name] == nil else { throw fail("duplicate ZIP part \(name)") }
                var expanded = Int(u32(p + 24)), compressed = Int(u32(p + 20)), local = Int(u32(p + 42)), disk = Int(u16(p + 34))
                let needs64 = expanded == Int(UInt32.max) || compressed == Int(UInt32.max) || local == Int(UInt32.max) || disk == 65535
                if needs64 {
                    var q = p + 46 + nameSize, found = false
                    let stop = q + extraSize
                    while q + 4 <= stop {
                        let tag = u16(q), n = Int(u16(q + 2)); q += 4
                        guard n <= stop - q else { throw fail("invalid ZIP extra field") }
                        if tag == 1 {
                            var r = q
                            func take() throws -> Int { guard r + 8 <= q + n else { throw fail("short ZIP64 extra field") }; defer { r += 8 }; return try integer(u64(r)) }
                            if expanded == Int(UInt32.max) { expanded = try take() }
                            if compressed == Int(UInt32.max) { compressed = try take() }
                            if local == Int(UInt32.max) { local = try take() }
                            if disk == 65535 { guard r + 4 <= q + n else { throw fail("short ZIP64 disk field") }; disk = Int(u32(r)) }
                            found = true; break
                        }
                        q += n
                    }
                    guard found else { throw fail("missing ZIP64 extra field") }
                }
                guard disk == 0 else { throw fail("split ZIP entry") }
                guard compressed <= Int(UInt32.max), expanded < Int(UInt32.max) else { throw DocumentError.unsupportedContainer("ZIP part exceeds the zlib buffer size") }
                guard expanded <= limits.maxPartBytes, expanded <= limits.maxExpandedBytes - total else { throw DocumentError.limitExceeded("ZIP expanded bytes") }
                total += expanded
                guard contains(local, 30), local + 30 <= offset, u32(local) == 0x04034b50,
                      u16(local + 6) == flags, u16(local + 8) == method else { throw fail("invalid local ZIP header") }
                let localNameSize = Int(u16(local + 26)), localExtraSize = Int(u16(local + 28))
                let headerSize = 30 + localNameSize + localExtraSize
                guard contains(local, headerSize), localNameSize == nameSize,
                      b[(local + 30)..<(local + 30 + localNameSize)].elementsEqual(b[(p + 46)..<(p + 46 + nameSize)]) else { throw fail("local ZIP name mismatch") }
                if flags & 8 == 0 {
                    guard u32(local + 14) == crc,
                          u32(local + 18) == UInt32.max || Int(u32(local + 18)) == compressed,
                          u32(local + 22) == UInt32.max || Int(u32(local + 22)) == expanded else { throw fail("local ZIP size or CRC mismatch") }
                }
                let start = local + headerSize
                guard contains(start, compressed), start + compressed <= offset else { throw fail("ZIP entry overlaps directory") }
                if method == 0, expanded != compressed { throw fail("stored ZIP size mismatch") }
                var occupiedEnd = start + compressed
                if flags & 8 != 0 {
                    var d = occupiedEnd
                    if contains(d, 4), u32(d) == 0x08074b50 { d += 4 }
                    let is64 = needs64 || u32(local + 18) == UInt32.max || u32(local + 22) == UInt32.max
                    let descriptorSize = is64 ? 20 : 12
                    guard contains(d, descriptorSize), d + descriptorSize <= offset, u32(d) == crc else { throw fail("invalid ZIP data descriptor") }
                    if is64 {
                        guard u64(d + 4) == UInt64(compressed), u64(d + 12) == UInt64(expanded) else { throw fail("ZIP64 descriptor mismatch") }
                    } else { guard Int(u32(d + 4)) == compressed, Int(u32(d + 8)) == expanded else { throw fail("ZIP descriptor mismatch") } }
                    occupiedEnd = d + descriptorSize
                }
                ranges.append(local..<occupiedEnd)
                entries[name] = Entry(path: name, compressedSize: compressed, expandedSize: expanded, method: method, crc: crc, payload: start..<(start + compressed))
                paths.append(name); p += length
            }
            guard p == offset + size else { throw fail("ZIP directory count mismatch") }
            let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
            for i in sorted.indices.dropFirst() where sorted[i].lowerBound < sorted[i - 1].upperBound { throw fail("overlapping ZIP entries") }
            return (entries, paths)
        }
        entries = parsed.0; paths = parsed.1
    }

    package func read(_ path: String) throws -> Data {
        guard let entry = entries[path] else { throw DocumentError.missingPart(path) }
        let output: Data
        if entry.method == 0 { output = data.subdata(in: entry.payload) }
        else {
            output = try data.withUnsafeBytes { raw in
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw DocumentError.corruptedPackage("inflate initialization") }
                defer { inflateEnd(&stream) }
                var expanded = Data(count: entry.expandedSize + 1)
                let status: Int32 = expanded.withUnsafeMutableBytes { dst in
                    stream.next_in = UnsafeMutablePointer(mutating: raw.baseAddress!.advanced(by: entry.payload.lowerBound).assumingMemoryBound(to: UInt8.self))
                    stream.avail_in = uInt(entry.compressedSize)
                    stream.next_out = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    stream.avail_out = uInt(dst.count)
                    return inflate(&stream, Z_FINISH)
                }
                guard status == Z_STREAM_END, stream.total_out == entry.expandedSize, stream.total_in == entry.compressedSize else { throw DocumentError.corruptedPackage("deflate length mismatch in \(path)") }
                expanded.removeLast(); return expanded
            }
        }
        let checksum = output.withUnsafeBytes { crc32(0, $0.baseAddress?.assumingMemoryBound(to: UInt8.self), uInt($0.count)) }
        guard UInt32(checksum) == entry.crc else { throw DocumentError.corruptedPackage("CRC mismatch in \(path)") }
        return output
    }
}
