import Foundation

/// A format, package, XML, relationship or limit failure.
public enum DocumentError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownFormat
    case noCodec(DocumentFormat)
    case unsupportedContainer(String)
    case corruptedPackage(String)
    case invalidXML(part: String, detail: String)
    case missingPart(String)
    case invalidRelationship(part: String, detail: String)
    case limitExceeded(String)
    case invalidOptions(String)
    case invalidModel(String)
    case invalidText(String)
    case writingNotSupported(DocumentFormat)
    case writingLoss([WriteWarning])
    public var description: String {
        switch self {
        case .unknownFormat: "The document format could not be determined."
        case .noCodec(let f): "The \(f.rawValue) format requires \(f.productName)."
        case .unsupportedContainer(let s): "Unsupported container: \(s)"
        case .corruptedPackage(let s): "Corrupted package: \(s)"
        case .invalidXML(let p, let s): "XML parsing failed (\(p)): \(s)"
        case .missingPart(let p): "Missing part: \(p)"
        case .invalidRelationship(let p, let s): "Invalid relationship (\(p)): \(s)"
        case .limitExceeded(let s): "Document limit exceeded: \(s)"
        case .invalidOptions(let s): "Invalid document options: \(s)"
        case .invalidModel(let s): "Invalid document model: \(s)"
        case .invalidText(let s): "Invalid text document: \(s)"
        case .writingNotSupported(let f): "Writing \(f.rawValue) is not supported by this codec."
        case .writingLoss(let warnings): "Writing would lose unsupported content (\(warnings.count) warning categories)."
        }
    }
}
/// Bounds on package declarations and parser work, not a process-memory budget.
public struct PackageLimits: Sendable {
    /// Maximum number of ZIP entries; default 10,000.
    public var maxEntries: Int
    /// Maximum declared total expanded bytes; default 512 MiB.
    public var maxExpandedBytes: Int
    /// Maximum expanded bytes per part; default 128 MiB.
    public var maxPartBytes: Int
    /// Maximum XML element nesting depth; default 128.
    public var maxXMLDepth: Int
    /// Maximum XML node count per parsed part; default 2,000,000.
    public var maxXMLNodes: Int
    public init(maxEntries: Int = 10_000, maxExpandedBytes: Int = 512 << 20, maxPartBytes: Int = 128 << 20, maxXMLDepth: Int = 128, maxXMLNodes: Int = 2_000_000) {
        self.maxEntries = maxEntries; self.maxExpandedBytes = maxExpandedBytes; self.maxPartBytes = maxPartBytes
        self.maxXMLDepth = maxXMLDepth; self.maxXMLNodes = maxXMLNodes
    }
}
/// Parsing limits, revision view and related-story inclusion.
public struct ReadOptions: Sendable {
    public enum RevisionView: String, Sendable { case final, original, all }
    /// Package and XML parsing limits.
    public var limits: PackageLimits
    /// Revision view; defaults to final.
    public var revisions: RevisionView
    /// Whether to read headers, footers, notes and comments; defaults to true.
    public var includeRelatedStories: Bool
    public init(limits: PackageLimits = .init(), revisions: RevisionView = .final, includeRelatedStories: Bool = true) {
        self.limits = limits; self.revisions = revisions; self.includeRelatedStories = includeRelatedStories
    }
}
/// An aggregated recoverability warning keyed by code, part and element.
public struct ReadWarning: Sendable, Equatable, Codable {
    public enum Code: String, Sendable, Codable { case unsupportedContent, uninterpretedFormatting, unsupportedPart, invalidReference, incompleteField, storiesOmitted }
    /// Machine-readable warning category.
    public var code: Code
    /// Source package part associated with this warning.
    public var part: String
    /// Source element or property associated with this warning.
    public var element: String
    /// Human-readable diagnostic; branch on code rather than parsing this string.
    public var message: String
    /// Number of occurrences aggregated into this warning; defaults to one.
    public var count: Int
    public init(code: Code, part: String, element: String, message: String, count: Int = 1) {
        self.code = code; self.part = part; self.element = element; self.message = message; self.count = count
    }
}
package final class WarningCollector {
    private struct Key: Hashable { let code: String; let part: String; let element: String }
    private var warnings: [ReadWarning] = []
    private var indices: [Key: Int] = [:]
    package init() {}
    package func add(_ code: ReadWarning.Code, part: String, element: String, message: String, count: Int = 1) {
        let key = Key(code: code.rawValue, part: part, element: element)
        if let i = indices[key] { warnings[i].count += count }
        else { indices[key] = warnings.count; warnings.append(.init(code: code, part: part, element: element, message: message, count: count)) }
    }
    package var result: [ReadWarning] { warnings }
}
/// A complete document with its reading warnings.
public struct ReadResult: Sendable {
    /// Document value returned by the operation; scan results have no body blocks.
    public var document: Document
    /// Warnings retained in the returned document.
    public var warnings: [ReadWarning] { document.readWarnings }
    public init(document: Document) { self.document = document }
}
/// A document without body blocks, plus the number delivered to the callback and warnings.
public struct ScanResult: Sendable {
    /// Styles, requested related stories, sections, metadata and warnings, without main-body blocks.
    public var document: Document
    /// Number of top-level body blocks successfully delivered to the callback.
    public var blocksRead: Int
    /// Warnings retained in the returned document.
    public var warnings: [ReadWarning] { document.readWarnings }
    public init(document: Document, blocksRead: Int) { self.document = document; self.blocksRead = blocksRead }
}
/// Package format, metadata and part inventory without body parsing.
public struct DocumentSummary: Sendable, Codable {
    /// The content-detected or explicitly selected document format.
    public var format: DocumentFormat
    /// Metadata read from core, extended and custom package properties.
    public var metadata: DocumentMetadata
    /// Package inventory without inflating every part.
    public var parts: [PackagePart]
    /// Sum of declared expanded sizes; not process memory consumption.
    public var expandedBytes: Int { parts.reduce(0) { $0 + $1.expandedSize } }
    public init(format: DocumentFormat, metadata: DocumentMetadata, parts: [PackagePart]) { self.format = format; self.metadata = metadata; self.parts = parts }
}
/// The synchronous reading, inspection and per-block scanning contract for one format.
public protocol DocumentCodec: Sendable {
    var format: DocumentFormat { get }
    func read(_ data: Data, options: ReadOptions) throws -> ReadResult
    func inspect(_ data: Data, limits: PackageLimits) throws -> DocumentSummary
    func scan(_ data: Data, options: ReadOptions, onBlock: (Block) throws -> Void) throws -> ScanResult
    func write(_ document: Document, options: WriteOptions) throws -> WriteResult
}
/// A type-erased, Sendable format codec selected by value.
public struct Codec: Sendable {
    package let implementation: any DocumentCodec
    /// The format selected by this codec, independently of package detection.
    public var format: DocumentFormat { implementation.format }
    public init(_ codec: any DocumentCodec) { implementation = codec }
}
/// A selection of format codecs. Content detection selects the reader unless explicitly overridden.
public struct CodecSet: Sendable {
    private let codecs: [DocumentFormat: Codec]
    /// Formats in first registration order, without duplicates.
    public let formats: [DocumentFormat]
    public init(_ codecs: [Codec]) {
        var table: [DocumentFormat: Codec] = [:], formats: [DocumentFormat] = []
        for codec in codecs {
            if table.updateValue(codec, forKey: codec.format) == nil { formats.append(codec.format) }
        }
        self.codecs = table; self.formats = formats
    }
    /// Whether a codec for this format is registered.
    public func contains(_ format: DocumentFormat) -> Bool { codecs[format] != nil }
    /// The registered choice, suitable for re-registering in another set.
    /// Throws `noCodec` when absent. Operations are dispatched through the set.
    public func codec(for format: DocumentFormat) throws -> Codec {
        guard let codec = codecs[format] else { throw DocumentError.noCodec(format) }
        return codec
    }
    private func selection(_ data: Data, format: DocumentFormat?, limits: PackageLimits) throws -> (codec: any DocumentCodec, package: OPCPackage?) {
        if let format {
            let implementation = try codec(for: format).implementation
            return (implementation, implementation is any PreparedDocumentCodec ? try OPCPackage(data, limits: limits) : nil)
        }
        let detected = try DocumentFormat.detectedPackage(data, limits: limits)
        return (try codec(for: detected.format).implementation, detected.opc)
    }
    /// Read bytes with content detection, or an explicitly selected codec.
    public func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult {
        try readSync(data, format: format, options: options)
    }
    public func read(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult {
        try readURLSync(url, format: format, options: options)
    }
    public func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try inspectSync(data, format: format, limits: limits)
    }
    public func inspect(contentsOf url: URL, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try inspectURLSync(url, format: format, limits: limits)
    }
    public func scan(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try Task.checkCancellation()
        let selected = try selection(data, format: format, limits: options.limits)
        func consume(_ block: Block) throws {
            try Task.checkCancellation()
            try onBlock(block)
            try Task.checkCancellation()
        }
        let result: ScanResult
        if let prepared = selected.codec as? any PreparedDocumentCodec, let package = selected.package {
            result = try prepared.scan(package, options: options, onBlock: consume)
        } else { result = try selected.codec.scan(data, options: options, onBlock: consume) }
        try Task.checkCancellation()
        return result
    }
    public func scan(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try scan(data, format: urlFormat(url, data: data, explicit: format), options: options, onBlock: onBlock)
    }

    /// Read on the generic executor, without occupying the caller's actor.
    /// Cancellation is cooperative; the codec protocol and file I/O remain synchronous.
    @concurrent public func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult {
        try readSync(data, format: format, options: options)
    }
    /// Read a content-detected local package on the generic executor.
    @concurrent public func read(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult {
        try readURLSync(url, format: format, options: options)
    }
    /// Inspect on the generic executor without parsing body content.
    @concurrent public func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) async throws -> DocumentSummary {
        try inspectSync(data, format: format, limits: limits)
    }
    /// Inspect a content-detected local package on the generic executor.
    @concurrent public func inspect(contentsOf url: URL, format: DocumentFormat? = nil, limits: PackageLimits = .init()) async throws -> DocumentSummary {
        try inspectURLSync(url, format: format, limits: limits)
    }
    /// Read independent documents with bounded concurrency and results in input order.
    /// Failure cancels and awaits remaining children. The limit bounds active reads, not total memory.
    @concurrent public func readAll(contentsOf urls: [URL], options: ReadOptions = .init(), maxConcurrentReads: Int = 4) async throws -> [ReadResult] {
        try await boundedRead(urls, maxConcurrent: maxConcurrentReads) { url in
            try await self.read(contentsOf: url, options: options)
        }
    }

    private func readSync(_ data: Data, format: DocumentFormat?, options: ReadOptions) throws -> ReadResult {
        try Task.checkCancellation()
        let selected = try selection(data, format: format, limits: options.limits)
        let result: ReadResult
        if let prepared = selected.codec as? any PreparedDocumentCodec, let package = selected.package {
            result = try prepared.read(package, options: options)
        } else { result = try selected.codec.read(data, options: options) }
        try Task.checkCancellation()
        return result
    }
    private func readURLSync(_ url: URL, format: DocumentFormat?, options: ReadOptions) throws -> ReadResult {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try readSync(data, format: urlFormat(url, data: data, explicit: format), options: options)
    }
    private func inspectSync(_ data: Data, format: DocumentFormat?, limits: PackageLimits) throws -> DocumentSummary {
        try Task.checkCancellation()
        let selected = try selection(data, format: format, limits: limits)
        let result: DocumentSummary
        if let prepared = selected.codec as? any PreparedDocumentCodec, let package = selected.package {
            result = try prepared.inspect(package)
        } else { result = try selected.codec.inspect(data, limits: limits) }
        try Task.checkCancellation()
        return result
    }
    private func inspectURLSync(_ url: URL, format: DocumentFormat?, limits: PackageLimits) throws -> DocumentSummary {
        try Task.checkCancellation()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try inspectSync(data, format: urlFormat(url, data: data, explicit: format), limits: limits)
    }
    private func urlFormat(_ url: URL, data: Data, explicit: DocumentFormat?) -> DocumentFormat? {
        if let explicit { return explicit }
        if data.starts(with: [0x50, 0x4B]) || data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) { return nil }
        return DocumentFormat(fileExtension: url.pathExtension) == .markdown ? .markdown : nil
    }
}
