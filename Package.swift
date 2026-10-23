// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftDocuments",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
        .library(name: "DocumentDOCX", targets: ["DocumentDOCX"]),
        .library(name: "DocumentODT", targets: ["DocumentODT"]),
        .library(name: "DocumentPages", targets: ["DocumentPages"]),
        .library(name: "DocumentMarkdown", targets: ["DocumentMarkdown"]),
        .library(name: "SwiftDocuments", targets: ["SwiftDocuments"]),
        .executable(name: "swiftdoc", targets: ["swiftdoc"])
    ],
    targets: [
        .systemLibrary(name: "CDocumentZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"]), .brew(["zlib"])]),
        .target(name: "DocumentCore", dependencies: ["CDocumentZlib"]),
        .target(name: "DocumentDOCX", dependencies: ["DocumentCore"], resources: [.copy("Resources")]),
        .target(name: "DocumentODT", dependencies: ["DocumentCore"]),
        .target(name: "DocumentPages", dependencies: ["DocumentCore"], resources: [.copy("Resources")]),
        .target(name: "DocumentMarkdown", dependencies: ["DocumentCore"]),
        .target(name: "SwiftDocuments", dependencies: ["DocumentCore", "DocumentDOCX", "DocumentODT", "DocumentPages", "DocumentMarkdown"]),
        .executableTarget(name: "swiftdoc", dependencies: ["SwiftDocuments"]),
        .testTarget(name: "SwiftDocumentsTests", dependencies: ["SwiftDocuments"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PartialLinkTests", dependencies: ["DocumentCore", "DocumentDOCX"])
    ]
)
