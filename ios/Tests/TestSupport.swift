import Foundation
import SwiftData
import GraphghanCore
@testable import Graphghan

enum TestFixtures {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }  // Tests, ios, <repo>
        return url
    }()
    static let directory = root.appendingPathComponent("fixtures/chart-format", isDirectory: true)
    static func data(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
    /// `fixtures/import/<name>.pdf`, written by `graphghan export --format pdf`.
    static func importPDF(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("fixtures/import/\(name).pdf"))
    }
    /// `fixtures/bundle/<slug>.graphghan`, written by `graphghan export --format graphghan`.
    static func bundle(_ slug: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("fixtures/bundle/\(slug).graphghan"))
    }
}

@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    try Persistence.makeContainer(inMemory: true)
}

func makeLocalPatternStore() throws -> LocalPatternStore {
    LocalPatternStore(directory: try temporaryDirectory())
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

actor StubClient: HTTPClient {
    struct Recorded: Equatable { let path: String; let ifNoneMatch: String? }
    private var responses: [String: Result<HTTPResponse, Error>] = [:]
    private var log: [Recorded] = []

    func respond(_ path: String, status: Int = 200, body: String = "", etag: String? = nil) {
        responses[path] = .success(HTTPResponse(status: status, data: Data(body.utf8), etag: etag))
    }
    func respond(_ path: String, data: Data, etag: String? = nil) {
        responses[path] = .success(HTTPResponse(status: 200, data: data, etag: etag))
    }
    func fail(_ path: String) { responses[path] = .failure(URLError(.notConnectedToInternet)) }
    func requests() -> [Recorded] { log }

    func get(_ url: URL, ifNoneMatch: String?) async throws -> HTTPResponse {
        log.append(Recorded(path: url.path, ifNoneMatch: ifNoneMatch))
        guard let r = responses[url.path] else { throw URLError(.notConnectedToInternet) }
        return try r.get()
    }
}

enum TestManifest {
    static func make(chartID: String, variant: String = "final", gaugeKey: String = "sc", version: String = "1.0.0", path: String = "charts/final-sc/chart.json") -> PatternManifest {
        let json = """
        {"schema":1,"id":"two-letter-codes","title":"Two-letter codes","version":"\(version)","dedication":"","quote":"","author":"","license":"",
         "preview":"preview.png","palette":[],"charts":[{"id":"\(chartID)","variant":"\(variant)","gauge_key":"\(gaugeKey)","default":true,
         "path":"\(path)","preview":"charts/final-sc/preview.png","width":12,"height":2,"size":{"width":3.4,"height":0.5,"unit":"in"},
         "stitch":"sc","colors":4,"stitches":24,"changes_per_row":{"mean":2,"max":2},"yards_est":10}],"updated":"2026-09-11T00:00:00Z"}
        """
        return try! JSONDecoder().decode(PatternManifest.self, from: Data(json.utf8))
    }
}
