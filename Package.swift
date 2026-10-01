// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftDocuments",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DocumentCore", targets: ["DocumentCore"]),
        .library(name: "DocumentDOCX", targets: ["DocumentDOCX"]),
        .library(name: "SwiftDocuments", targets: ["SwiftDocuments"]),
        .executable(name: "swiftdoc", targets: ["swiftdoc"])
    ],
    targets: [
        .systemLibrary(name: "CZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"]), .brew(["zlib"])]),
        .target(name: "DocumentCore", dependencies: ["CZlib"]),
        .target(name: "DocumentDOCX", dependencies: ["DocumentCore"]),
        .target(name: "SwiftDocuments", dependencies: ["DocumentCore", "DocumentDOCX"]),
        .executableTarget(name: "swiftdoc", dependencies: ["SwiftDocuments"]),
        .testTarget(name: "SwiftDocumentsTests", dependencies: ["SwiftDocuments"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PartialLinkTests", dependencies: ["DocumentCore", "DocumentDOCX"])
    ]
)
