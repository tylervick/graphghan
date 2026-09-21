// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GraphghanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GraphghanCore", targets: ["GraphghanCore"])],
    targets: [
        .target(
            name: "GraphghanCore",
            // The grid reader (GridReader.swift) walks every pixel of an 8-megapixel page; at
            // -Onone that is forty seconds a page and half a second at -O. The package is pure
            // logic, so its debug builds are optimised too and the app's tests stay quick.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .testTarget(name: "GraphghanCoreTests", dependencies: ["GraphghanCore"]),
    ],
    swiftLanguageModes: [.v6]
)
