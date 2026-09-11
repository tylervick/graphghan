import Foundation

/// The shared conformance fixtures at <repo>/fixtures/chart-format, located relative to this file
/// so `swift test` and Xcode both find them without copying.
enum Fixtures {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }  // GraphghanCoreTests, Tests, GraphghanCore, Packages, ios, <repo>
        return url.appendingPathComponent("fixtures/chart-format", isDirectory: true)
    }()

    static var chartNames: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".chart.json") }
            .map { String($0.dropLast(".chart.json".count)) }
            .sorted()
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func json(_ name: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data(name))
        guard let dict = object as? [String: Any] else { throw FixtureError.notAnObject(name) }
        return dict
    }

    enum FixtureError: Error { case notAnObject(String) }
}
