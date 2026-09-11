// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GraphghanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GraphghanCore", targets: ["GraphghanCore"])],
    targets: [
        .target(name: "GraphghanCore"),
        .testTarget(name: "GraphghanCoreTests", dependencies: ["GraphghanCore"]),
    ],
    swiftLanguageModes: [.v6]
)
