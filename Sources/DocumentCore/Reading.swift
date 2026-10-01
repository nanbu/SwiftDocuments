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
    public var description: String {
        switch self {
        case .unknownFormat: "文書の形式を判定できません。"
        case .noCodec(let f): "\(f.rawValue) を読むには \(f.productName) が必要です。"
        case .unsupportedContainer(let s): "未対応のコンテナ: \(s)"
        case .corruptedPackage(let s): "破損したパッケージ: \(s)"
        case .invalidXML(let p, let s): "XML の解析失敗 (\(p)): \(s)"
        case .missingPart(let p): "パーツがありません: \(p)"
        case .invalidRelationship(let p, let s): "不正な参照 (\(p)): \(s)"
        case .limitExceeded(let s): "読み取り制限を超えました: \(s)"
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
    /// The format identifier or source numbering format, according to this type.
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
}
/// A type-erased, Sendable format codec selected by value.
public struct Codec: Sendable {
    package var implementation: any DocumentCodec
    public init(_ codec: any DocumentCodec) { implementation = codec }
}
/// A selection of format codecs. Content detection selects the reader unless explicitly overridden.
public struct CodecSet: Sendable {
    private var codecs: [DocumentFormat: any DocumentCodec]
    public init(_ codecs: [Codec]) {
        self.codecs = [:]
        for codec in codecs { self.codecs[codec.implementation.format] = codec.implementation }
    }
    private func codec(_ data: Data, format: DocumentFormat?, limits: PackageLimits) throws -> any DocumentCodec {
        let f = try format ?? DocumentFormat.detect(data, limits: limits)
        guard let codec = codecs[f] else { throw DocumentError.noCodec(f) }
        return codec
    }
    public func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult {
        try codec(data, format: format, limits: options.limits).read(data, options: options)
    }
    public func read(contentsOf url: URL, options: ReadOptions = .init()) throws -> ReadResult {
        try read(Data(contentsOf: url, options: .mappedIfSafe), options: options)
    }
    public func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try codec(data, format: format, limits: limits).inspect(data, limits: limits)
    }
    public func inspect(contentsOf url: URL, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try inspect(Data(contentsOf: url, options: .mappedIfSafe), limits: limits)
    }
    public func scan(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try codec(data, format: format, limits: options.limits).scan(data, options: options, onBlock: onBlock)
    }
    public func scan(contentsOf url: URL, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try scan(Data(contentsOf: url, options: .mappedIfSafe), options: options, onBlock: onBlock)
    }
}
