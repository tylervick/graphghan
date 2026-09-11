import Foundation
import SwiftData
@testable import Graphghan

enum TestFixtures {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }  // Tests, ios, <repo>
        return url.appendingPathComponent("fixtures/chart-format", isDirectory: true)
    }()
    static func data(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
}

@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    try Persistence.makeContainer(inMemory: true)
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
