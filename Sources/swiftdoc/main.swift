import Foundation
import SwiftDocuments

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 2, ["text", "inspect", "scan", "read"].contains(args[0]) else {
        print("使い方: swiftdoc text|inspect|scan|read 文書.docx")
        exit(2)
    }
    let url = URL(fileURLWithPath: args[1])
    let start = ContinuousClock.now
    switch args[0] {
    case "inspect":
        let summary = try Document.inspect(contentsOf: url)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(summary), as: UTF8.self))
    case "text":
        let result = try Document.read(contentsOf: url)
        print(result.document.plainText)
        for warning in result.warnings { FileHandle.standardError.write(Data("警告: \(warning.part) / \(warning.element) (\(warning.count)): \(warning.message)\n".utf8)) }
    case "scan":
        var characters = 0
        let result = try Document.scan(contentsOf: url, options: ReadOptions(includeRelatedStories: false)) { characters += $0.plainText.count }
        print("blocks=\(result.blocksRead) characters=\(characters) warnings=\(result.warnings.count) time=\(start.duration(to: .now))")
    default:
        let result = try Document.read(contentsOf: url, options: ReadOptions(includeRelatedStories: false))
        print("blocks=\(result.document.blocks.count) characters=\(result.document.blocks.reduce(0) { $0 + $1.plainText.count }) warnings=\(result.warnings.count) time=\(start.duration(to: .now))")
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1)
}
