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
