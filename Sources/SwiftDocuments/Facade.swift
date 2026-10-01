import Foundation
@_exported import DocumentCore
@_exported import DocumentDOCX

extension CodecSet {
    /// All currently implemented codecs: DOCX and DOCM.
    public static let all = CodecSet([.docx, .docm])
}
extension Document {
    /// Read a content-detected local package with all implemented codecs.
    /// Warnings are retained in `readWarnings`; related bodies are in `stories`.
    public init(contentsOf url: URL, options: ReadOptions = .init()) throws {
        self = try CodecSet.all.read(contentsOf: url, options: options).document
    }
    /// Read package bytes, optionally selecting a format instead of detecting it.
    public init(data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws {
        self = try CodecSet.all.read(data, format: format, options: options).document
    }
    /// Read a complete document model and expose its aggregated warnings.
    public static func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult {
        try CodecSet.all.read(data, format: format, options: options)
    }
    /// Read a local document and expose its aggregated warnings.
    public static func read(contentsOf url: URL, options: ReadOptions = .init()) throws -> ReadResult {
        try CodecSet.all.read(contentsOf: url, options: options)
    }
    /// Inspect format, metadata and inventory without parsing body blocks.
    /// Body and image CRCs are not verified by inspection.
    public static func inspect(_ data: Data, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try CodecSet.all.inspect(data, limits: limits)
    }
    /// Inspect a local package without parsing its body or inflating images.
    public static func inspect(contentsOf url: URL, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try CodecSet.all.inspect(contentsOf: url, limits: limits)
    }
    /// Deliver each top-level body block to a synchronous throwing callback.
    /// The result omits body blocks. ZIP bytes and expanded XML remain in memory.
    /// Callback errors propagate unchanged; later parse failures may follow earlier callbacks.
    public static func scan(_ data: Data, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try CodecSet.all.scan(data, options: options, onBlock: onBlock)
    }
    /// Scan a local package in body order without retaining its body blocks.
    /// A table is one block. This is not constant-memory streaming.
    public static func scan(contentsOf url: URL, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try CodecSet.all.scan(contentsOf: url, options: options, onBlock: onBlock)
    }
}
