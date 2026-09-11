import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct PatternStoreTests {
    static let index = #"[{"slug":"p","title":"P","version":"1","stitch":"sc","width":2,"height":1,"size_in":[1,1],"dedication":"","colors":1,"preview":"patterns/p/preview.png","manifest":"patterns/p/pattern.json","charts":1}]"#
    static let manifest = #"{"schema":1,"id":"p","title":"P","version":"1","dedication":"","quote":"","author":"","license":"","preview":"preview.png","palette":[],"charts":[],"updated":"2026-09-11T00:00:00Z"}"#

    func makeStore() async throws -> (PatternStore, StubClient) {
        let client = StubClient()
        let store = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        return (store, client)
    }

    @Test func freshFetchThenNotModified() async throws {
        let (store, client) = try await makeStore()
        #expect(await store.cachedIndex() == nil)
        await client.respond("/patterns/index.json", body: Self.index, etag: "\"v1\"")
        let first = try await store.refreshIndex()
        #expect(first.map(\.slug) == ["p"])
        #expect(await store.cachedIndex()?.count == 1)
        await client.respond("/patterns/index.json", status: 304)
        let second = try await store.refreshIndex()
        #expect(second == first)
        let log = await client.requests()
        #expect(log.map(\.ifNoneMatch) == [nil, "\"v1\""])
    }

    @Test func offlineWithCacheKeepsServingTheCache() async throws {
        let (store, client) = try await makeStore()
        await client.respond("/patterns/index.json", body: Self.index, etag: "\"v1\"")
        _ = try await store.refreshIndex()
        await client.fail("/patterns/index.json")
        await #expect(throws: URLError.self) { try await store.refreshIndex() }
        #expect(await store.cachedIndex()?.first?.slug == "p")
    }

    @Test func offlineWithoutCacheHasNothing() async throws {
        let (store, _) = try await makeStore()
        await #expect(throws: URLError.self) { try await store.refreshIndex() }
        #expect(await store.cachedIndex() == nil)
    }

    @Test func serverErrorsAreReported() async throws {
        let (store, client) = try await makeStore()
        await client.respond("/patterns/index.json", status: 500, body: "boom")
        await #expect(throws: PatternStore.StoreError.http(500)) { try await store.refreshIndex() }
        await client.respond("/patterns/index.json", status: 304)  // 304 with nothing cached
        await #expect(throws: PatternStore.StoreError.noCache) { try await store.refreshIndex() }
    }

    @Test func manifestsPreviewsAndCharts() async throws {
        let (store, client) = try await makeStore()
        await client.respond("/patterns/p/pattern.json", body: Self.manifest, etag: "\"m1\"")
        let m = try await store.refreshManifest(for: "p", path: "patterns/p/pattern.json")
        let cached = await store.cachedManifest(for: "p")
        #expect(m.id == "p" && cached?.id == "p")
        await client.respond("/patterns/p/preview.png", body: "PNG")
        #expect(await store.preview(for: "p", sitePath: "patterns/p/preview.png") == Data("PNG".utf8))
        await client.fail("/patterns/p/preview.png")
        #expect(await store.preview(for: "p", sitePath: "patterns/p/preview.png") == Data("PNG".utf8))  // cached
        await client.respond("/patterns/p/charts/final-sc/preview.png", body: "PNG2")
        #expect(await store.chartPreview(for: "p", path: "charts/final-sc/preview.png") == Data("PNG2".utf8))
        await client.respond("/patterns/p/charts/final-sc/chart.json", body: "{}")
        #expect(try await store.chartData(for: "p", path: "charts/final-sc/chart.json") == Data("{}".utf8))
        await client.fail("/patterns/p/charts/final-sc/chart.json")
        await #expect(throws: URLError.self) { try await store.chartData(for: "p", path: "charts/final-sc/chart.json") }
    }
}
