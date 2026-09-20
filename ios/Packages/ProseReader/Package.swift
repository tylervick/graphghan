// swift-tools-version: 6.0
// The Foundation Models reading experiment (docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md §9):
// a macOS command-line tool that reads a pattern PDF's text through Apple's on-device model or the
// Private Cloud Compute model into the same `graphghan-import/1` document the Python importer consumes.
// The library target is the part a phone would carry (#112): the @Generable shape and the reading loop.
import PackageDescription

let package = Package(
    name: "ProseReader",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ProseReaderKit", targets: ["ProseReaderKit"]),
        .executable(name: "prosereader", targets: ["prosereader"]),
    ],
    targets: [
        .target(name: "ProseReaderKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "prosereader", dependencies: ["ProseReaderKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ProseReaderKitTests", dependencies: ["ProseReaderKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
