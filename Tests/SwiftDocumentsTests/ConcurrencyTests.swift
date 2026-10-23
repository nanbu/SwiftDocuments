import Foundation
import Testing
import SwiftDocuments
@testable import DocumentCore

private enum BatchError: Error { case failed, consumer }
private enum ReadContext {
    @TaskLocal static var marker = "absent"
}
private struct ExecutorProbeCodec: DocumentCodec {
    var format: DocumentFormat { .docx }
    func read(_ data: Data, options: ReadOptions) throws -> ReadResult {
        var document = Document()
        document.metadata.title = ReadContext.marker
        document.metadata.subject = String(Thread.isMainThread)
        document.metadata.description = options.revisions.rawValue
        return .init(document: document)
    }
    func inspect(_ data: Data, limits: PackageLimits) throws -> DocumentSummary {
        var metadata = DocumentMetadata()
        metadata.title = ReadContext.marker; metadata.subject = String(Thread.isMainThread)
        metadata.description = String(limits.maxPartBytes)
        return .init(format: .docx, metadata: metadata, parts: [])
    }
    func scan(_ data: Data, options: ReadOptions, onBlock: (Block) throws -> Void) throws -> ScanResult {
        .init(document: try read(data, options: options).document, blocksRead: 0)
    }
}

/// Controlled completions exercise actual in-flight work and cancellation without timing assumptions.
private actor BatchGate {
    private var waiters: [Int: CheckedContinuation<Result<Int, BatchError>, Never>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    private var started: [Int] = []
    private var cancelled: Set<Int> = []
    private var active = 0
    private var peak = 0
    func run(_ index: Int) async throws -> Int {
        try Task.checkCancellation()
        active += 1; peak = max(peak, active)
        defer { active -= 1 }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[index] = continuation; started.append(index)
                for (count, observer) in observers where started.count >= count { observer.resume() }
                observers.removeAll { started.count >= $0.0 }
                if Task.isCancelled { cancel(index) }
            }
        } onCancel: {
            Task { await self.cancel(index) }
        }
        try Task.checkCancellation()
        return try result.get()
    }
    func waitForStarts(_ count: Int) async {
        if started.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func finish(_ index: Int, fail: Bool = false) {
        waiters.removeValue(forKey: index)?.resume(returning: fail ? .failure(.failed) : .success(index))
    }
    private func cancel(_ index: Int) {
        cancelled.insert(index)
        waiters.removeValue(forKey: index)?.resume(returning: .success(index))
    }
    func snapshot() -> (started: Set<Int>, cancelled: Set<Int>, active: Int, peak: Int) {
        (Set(started), cancelled, active, peak)
    }
}

@Suite(.timeLimit(.minutes(1))) struct ConcurrencyTests {
    @MainActor @Test func asyncDispatchLeavesMainActorAndPreservesTaskLocal() async throws {
        let set = CodecSet([Codec(ExecutorProbeCodec())])
        try await ReadContext.$marker.withValue("inherited") {
            let result = try await set.read(Data(), format: .docx, options: .init(revisions: .original))
            #expect(result.document.metadata.title == "inherited")
            #expect(result.document.metadata.description == "original")
            let summary = try await set.inspect(Data(), format: .docx, limits: .init(maxPartBytes: 73))
            #expect(summary.metadata.title == "inherited" && summary.metadata.description == "73")
            #if os(macOS)
            #expect(result.document.metadata.subject == "false")
            #expect(summary.metadata.subject == "false")
            #endif
        }
    }

    @MainActor @Test func asyncFacadeMatchesSynchronousReadInspectAndAssets() async throws {
        let data = try fixture("features.docx")
        let full = try await Document.read(data, format: .docx)
        let synchronous = try { try Document.read(data, format: .docx) }()
        #expect(full.document.plainText == synchronous.document.plainText)
        #expect(full.warnings == synchronous.warnings)
        let summary = try await Document.inspect(data, format: .docx)
        #expect(summary.format == .docx && summary.parts.count == full.document.packageParts.count)
        let fromURL = try await Document.read(contentsOf: fixtureURL("features.docx"))
        let urlSummary = try await Document.inspect(contentsOf: fixtureURL("features.docx"))
        #expect(fromURL.document.plainText == full.document.plainText)
        #expect(urlSummary.parts.map(\.path) == summary.parts.map(\.path))
        let originalAsset = try { try synchronous.document.asset(at: "word/document.xml") }()
        #expect(try await full.document.asset(at: "word/document.xml") == originalAsset)
        await #expect(throws: DocumentError.noCodec(.odt)) { try await CodecSet([.docx]).inspect(Data(), format: .odt) }
        await #expect(throws: DocumentError.corruptedPackage("codec / MIME mismatch")) {
            try await Document.read(fixture("macro.docm"), format: .docx)
        }
    }

    @Test func boundedReadsKeepInputOrderDespiteReversedCompletion() async throws {
        let gate = BatchGate()
        let task = Task { try await boundedRead([0, 1, 2, 3], maxConcurrent: 2) { try await gate.run($0) } }
        await gate.waitForStarts(2)
        #expect(await gate.snapshot().started == [0, 1])
        await gate.finish(1); await gate.waitForStarts(3)
        #expect(await gate.snapshot().active == 2)
        await gate.finish(2); await gate.waitForStarts(4)
        await gate.finish(3); await gate.finish(0)
        #expect(try await task.value == [0, 1, 2, 3])
        let snapshot = await gate.snapshot()
        #expect(snapshot.peak == 2 && snapshot.active == 0)
    }

    @MainActor @Test func asyncURLFormatOverrideMatchesSynchronousDispatch() async throws {
        let url = fixtureURL("macro.docm")
        let set = CodecSet([Codec(ExecutorProbeCodec())])
        // The probe accepts arbitrary bytes only when explicit selection bypasses detection.
        let result = try await set.read(contentsOf: url, format: .docx, options: .init(revisions: .original))
        let summary = try await set.inspect(contentsOf: url, format: .docx, limits: .init(maxPartBytes: 73))
        #expect(result.document.metadata.description == "original")
        #expect(summary.metadata.description == "73")
        #if os(macOS)
        #expect(result.document.metadata.subject == "false" && summary.metadata.subject == "false")
        #endif
        let full = try await Document.read(contentsOf: url, format: .docm)
        #expect(full.document.sourceFormat == .docm)
        #expect(try await Document.inspect(contentsOf: url, format: .docm).format == .docm)
        await #expect(throws: DocumentError.corruptedPackage("codec / MIME mismatch")) {
            try await Document.read(contentsOf: url, format: .docx)
        }
        await #expect(throws: DocumentError.corruptedPackage("codec / MIME mismatch")) {
            try await Document.inspect(contentsOf: url, format: .docx)
        }
    }

    @Test func failedBatchCancelsAndJoinsRemainingChildren() async throws {
        let gate = BatchGate()
        let task = Task { try await boundedRead([0, 1, 2], maxConcurrent: 2) { try await gate.run($0) } }
        await gate.waitForStarts(2); await gate.finish(0, fail: true)
        await #expect(throws: BatchError.failed) { try await task.value }
        let snapshot = await gate.snapshot()
        #expect(snapshot.started == [0, 1] && snapshot.cancelled.contains(1) && snapshot.active == 0)
    }

    @Test func parentCancellationJoinsRemainingChildren() async throws {
        let gate = BatchGate()
        let task = Task { try await boundedRead([0, 1, 2], maxConcurrent: 2) { try await gate.run($0) } }
        await gate.waitForStarts(2); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let snapshot = await gate.snapshot()
        #expect(snapshot.started == [0, 1] && snapshot.active == 0 && snapshot.cancelled == [0, 1])
    }

    @Test func batchURLReadsPreserveDuplicatesOptionsAndWarnings() async throws {
        let urls = [fixtureURL("macro.docm"), fixtureURL("features.docx"), fixtureURL("macro.docm")]
        let options = ReadOptions(revisions: .original, includeRelatedStories: false)
        let results = try await Document.readAll(contentsOf: urls, options: options, maxConcurrentReads: 2)
        #expect(results.map { $0.document.sourceFormat } == [.docm, .docx, .docm])
        for (url, result) in zip(urls, results) {
            let full = try await CodecSet.all.read(contentsOf: url, options: options)
            #expect(result.document.plainText == full.document.plainText && result.warnings == full.warnings)
        }
        #expect(try await Document.readAll(contentsOf: [], maxConcurrentReads: Int.max).isEmpty)
        await #expect(throws: DocumentError.invalidOptions("maxConcurrentReads must be a positive integer")) {
            try await CodecSet.all.readAll(contentsOf: [], maxConcurrentReads: 0)
        }
        await #expect(throws: DocumentError.invalidOptions("maxConcurrentReads must be a positive integer")) {
            try await Document.readAll(contentsOf: urls, maxConcurrentReads: -1)
        }
        await #expect(throws: DocumentError.noCodec(.docm)) {
            try await CodecSet([.docx]).readAll(contentsOf: urls, maxConcurrentReads: 1)
        }
        await #expect(throws: DocumentError.self) {
            try await Document.readAll(contentsOf: [fixtureURL("minimal.docx")], options: .init(limits: .init(maxEntries: 1)))
        }
    }

    @Test func cancelledEntryPointsDoNotDispatchOrReturnEmptySuccess() async throws {
        let set = CodecSet([Codec(ExecutorProbeCodec())])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await set.read(Data(), format: .docx) }
            await #expect(throws: CancellationError.self) { try await set.inspect(Data(), format: .docx) }
            await #expect(throws: CancellationError.self) { try await Document.readAll(contentsOf: []) }
            #expect(throws: CancellationError.self) { try DocumentFormat.detect(Data()) }
            #expect(throws: CancellationError.self) { try Document().asset(at: "missing") }
        }
        await task.value
    }

    @Test func scanCancellationStopsLaterCallbacksAndPreservesConsumerError() async throws {
        let data = makeDocument(paragraph("A") + paragraph("B"))
        for throwsFromConsumer in [false, true] {
            let task = Task {
                var calls = 0
                do {
                    _ = try Document.scan(data) { _ in
                        calls += 1; withUnsafeCurrentTask { $0?.cancel() }
                        if throwsFromConsumer { throw BatchError.consumer }
                    }
                    Issue.record("Cancelled scan succeeded")
                } catch is CancellationError { #expect(!throwsFromConsumer) }
                catch BatchError.consumer { #expect(throwsFromConsumer) }
                catch { Issue.record("Unexpected error: \(error)") }
                #expect(calls == 1)
            }
            await task.value
        }
    }
}
