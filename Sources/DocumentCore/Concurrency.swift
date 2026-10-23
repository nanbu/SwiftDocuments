/// Bounded structured reads. Each input is submitted once and results keep input order.
@concurrent package func boundedRead<Input: Sendable, Output: Sendable>(
    _ inputs: [Input], maxConcurrent: Int,
    operation: @escaping @Sendable (Input) async throws -> Output
) async throws -> [Output] {
    guard maxConcurrent > 0 else { throw DocumentError.invalidOptions("maxConcurrentReads must be a positive integer") }
    try Task.checkCancellation()
    return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
        defer { group.cancelAll() }
        var results = [Output?](repeating: nil, count: inputs.count)
        var next = 0
        func submit(_ index: Int) throws {
            let input = inputs[index]
            guard group.addTaskUnlessCancelled(operation: {
                try Task.checkCancellation()
                return (index, try await operation(input))
            }) else { throw CancellationError() }
        }
        while next < min(maxConcurrent, inputs.count) { try submit(next); next += 1 }
        while let (index, result) = try await group.next() {
            try Task.checkCancellation()
            results[index] = result
            if next < inputs.count { try submit(next); next += 1 }
        }
        try Task.checkCancellation()
        // Only reached after every submitted child succeeded; no partial result is returned.
        return results.map { $0! }
    }
}
