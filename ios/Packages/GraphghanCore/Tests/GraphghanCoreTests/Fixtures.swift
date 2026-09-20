import Foundation

/// The shared fixtures under <repo>/fixtures -- the conformance charts and the bundles -- located
/// relative to this file so `swift test` and Xcode both find them without copying.
enum Fixtures {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }  // GraphghanCoreTests, Tests, GraphghanCore, Packages, ios, <repo>
        return url
    }()

    static let directory = root.appendingPathComponent("fixtures/chart-format", isDirectory: true)

    /// `fixtures/import/<name>.pdf`, written by `graphghan export --format pdf` (the round-trip
    /// fixtures of the import spec §7.1).
    static func importPDF(_ name: String) -> URL {
        root.appendingPathComponent("fixtures/import/\(name).pdf")
    }
    /// `fixtures/bundle/<slug>.graphghan`, written by `graphghan export --format graphghan`.
    static func bundle(_ slug: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("fixtures/bundle/\(slug).graphghan"))
    }

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
