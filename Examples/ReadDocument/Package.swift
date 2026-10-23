// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ReadDocument",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "ReadDocument", dependencies: [
        .product(name: "SwiftDocuments", package: "SwiftDocuments")
    ])]
)
