import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct AppModelTests {
    static let index = #"[{"slug":"p","title":"P","version":"1","stitch":"sc","width":2,"height":1,"size_in":[1,1],"dedication":"","colors":1,"preview":"patterns/p/preview.png","manifest":"patterns/p/pattern.json","charts":1}]"#

    func makeModel() async throws -> (AppModel, StubClient) {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        return (AppModel(context: container.mainContext, patterns: patterns, charts: charts,
                         localPatterns: try makeLocalPatternStore()), client)
    }

    @Test func offlineWithoutCacheShowsAnError() async throws {
        let (model, _) = try await makeModel()
        await model.loadLibrary()
        #expect(model.index.isEmpty && model.libraryError != nil && model.libraryBanner == nil)
    }

    @Test func refreshFailureKeepsTheCacheAndShowsABanner() async throws {
        let (model, client) = try await makeModel()
        await client.respond("/patterns/index.json", body: Self.index, etag: "\"1\"")
        await model.loadLibrary()
        #expect(model.index.count == 1 && model.libraryBanner == nil && model.libraryError == nil)
        await client.fail("/patterns/index.json")
        await model.loadLibrary(force: true)
        #expect(model.index.count == 1 && model.libraryBanner != nil && model.libraryError == nil)
    }
}
