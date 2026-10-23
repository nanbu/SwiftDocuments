import Foundation
@_exported import DocumentCore
@_exported import DocumentDOCX
@_exported import DocumentODT
@_exported import DocumentPages
@_exported import DocumentMarkdown

extension CodecSet {
    /// All currently implemented reading codecs.
    public static let all = CodecSet([.docx, .docm, .odt, .pages, .markdown])
}
extension Document {
    /// Read a local package, detecting its contents unless a format is selected.
    /// Warnings are retained in `readWarnings`; related bodies are in `stories`.
    public init(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws {
        self = try CodecSet.all.read(contentsOf: url, format: format, options: options).document
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
    public static func read(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) throws -> ReadResult {
        try CodecSet.all.read(contentsOf: url, format: format, options: options)
    }
    /// Inspect format, metadata and inventory without parsing body blocks.
    /// Body and image CRCs are not verified by inspection.
    public static func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try CodecSet.all.inspect(data, format: format, limits: limits)
    }
    /// Inspect a local package without parsing its body or inflating images.
    public static func inspect(contentsOf url: URL, format: DocumentFormat? = nil, limits: PackageLimits = .init()) throws -> DocumentSummary {
        try CodecSet.all.inspect(contentsOf: url, format: format, limits: limits)
    }
    /// Deliver each top-level body block to a synchronous throwing callback.
    /// The result omits body blocks. ZIP bytes and expanded XML remain in memory.
    /// Callback errors propagate unchanged; later parse failures may follow earlier callbacks.
    public static func scan(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try CodecSet.all.scan(data, format: format, options: options, onBlock: onBlock)
    }
    /// Scan a local package in body order without retaining its body blocks.
    /// A table is one block. This is not constant-memory streaming.
    public static func scan(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init(), onBlock: (Block) throws -> Void) throws -> ScanResult {
        try CodecSet.all.scan(contentsOf: url, format: format, options: options, onBlock: onBlock)
    }
    /// Read bytes on the generic executor, preserving task cancellation and task-local values.
    @concurrent public static func read(_ data: Data, format: DocumentFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult {
        try await CodecSet.all.read(data, format: format, options: options)
    }
    /// Read a local document without occupying the caller's actor.
    @concurrent public static func read(contentsOf url: URL, format: DocumentFormat? = nil, options: ReadOptions = .init()) async throws -> ReadResult {
        try await CodecSet.all.read(contentsOf: url, format: format, options: options)
    }
    /// Inspect bytes on the generic executor without parsing body blocks.
    @concurrent public static func inspect(_ data: Data, format: DocumentFormat? = nil, limits: PackageLimits = .init()) async throws -> DocumentSummary {
        try await CodecSet.all.inspect(data, format: format, limits: limits)
    }
    /// Inspect a local package without occupying the caller's actor.
    @concurrent public static func inspect(contentsOf url: URL, format: DocumentFormat? = nil, limits: PackageLimits = .init()) async throws -> DocumentSummary {
        try await CodecSet.all.inspect(contentsOf: url, format: format, limits: limits)
    }
    /// Read a batch in input order, with at most the specified number of active reads.
    /// A failure cancels and awaits remaining children; no partial batch is returned.
    @concurrent public static func readAll(contentsOf urls: [URL], options: ReadOptions = .init(), maxConcurrentReads: Int = 4) async throws -> [ReadResult] {
        try await CodecSet.all.readAll(contentsOf: urls, options: options, maxConcurrentReads: maxConcurrentReads)
    }
}

extension Document {
    /// Generate bytes in the selected format, retaining diagnosed writing losses.
    public func write(as format: DocumentFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult {
        try CodecSet.all.write(self, as: format, options: options)
    }
    /// Serialize completely, then atomically replace a local destination.
    public func write(to url: URL, as format: DocumentFormat? = nil, options: WriteOptions = .init()) throws -> WriteResult {
        try CodecSet.all.write(self, to: url, as: format, options: options)
    }
    /// Generate bytes on the generic executor.
    @concurrent public func write(as format: DocumentFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult {
        try await CodecSet.all.write(self, as: format, options: options)
    }
    /// Serialize and atomically save on the generic executor.
    @concurrent public func write(to url: URL, as format: DocumentFormat? = nil, options: WriteOptions = .init()) async throws -> WriteResult {
        try await CodecSet.all.write(self, to: url, as: format, options: options)
    }
}
