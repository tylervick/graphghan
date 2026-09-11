import Foundation
import GraphghanCore

/// The published library: `patterns/index.json`, each pattern's `pattern.json`, previews, and
/// chart downloads. Index and manifests are cached on disk with their ETags so a refresh that
/// returns 304 costs nothing and an offline launch still has a library.
actor PatternStore {
    enum StoreError: Error, Equatable {
        case http(Int)
        case noCache
    }

    static let defaultBaseURL = URL(string: "https://graphghan.milo.cat/")!

    let baseURL: URL
    private let cacheDirectory: URL
    private let client: HTTPClient

    init(baseURL: URL = PatternStore.defaultBaseURL, cacheDirectory: URL, client: HTTPClient) {
        self.baseURL = baseURL
        self.cacheDirectory = cacheDirectory
        self.client = client
    }

    // MARK: index

    private var indexFile: URL { cacheDirectory.appendingPathComponent("index.json") }

    func cachedIndex() -> [IndexEntry]? {
        guard let data = try? Data(contentsOf: indexFile) else { return nil }
        return try? JSONDecoder().decode([IndexEntry].self, from: data)
    }

    func refreshIndex() async throws -> [IndexEntry] {
        let data = try await conditionalGet(sitePath: "patterns/index.json", cacheFile: indexFile)
        return try JSONDecoder().decode([IndexEntry].self, from: data)
    }

    // MARK: manifests

    private func patternDirectory(_ slug: String) -> URL { cacheDirectory.appendingPathComponent(slug, isDirectory: true) }
    private func manifestFile(_ slug: String) -> URL { patternDirectory(slug).appendingPathComponent("pattern.json") }

    func cachedManifest(for slug: String) -> PatternManifest? {
        guard let data = try? Data(contentsOf: manifestFile(slug)) else { return nil }
        return try? JSONDecoder().decode(PatternManifest.self, from: data)
    }

    /// `path` is the index entry's `manifest` (site-relative); nil falls back to the conventional location.
    func refreshManifest(for slug: String, path: String?) async throws -> PatternManifest {
        let data = try await conditionalGet(sitePath: path ?? "patterns/\(slug)/pattern.json", cacheFile: manifestFile(slug))
        return try JSONDecoder().decode(PatternManifest.self, from: data)
    }

    // MARK: images and charts

    /// The pattern's site-relative preview (from the index). Cached forever; nil when unavailable.
    func preview(for slug: String, sitePath: String) async -> Data? {
        await cachedBytes(sitePath: sitePath, cacheFile: patternDirectory(slug).appendingPathComponent("preview.png"))
    }

    /// A chart preview by manifest-relative path (e.g. `charts/final-sc/preview.png`).
    func chartPreview(for slug: String, path: String) async -> Data? {
        let name = path.replacingOccurrences(of: "/", with: "_")
        return await cachedBytes(sitePath: "patterns/\(slug)/\(path)", cacheFile: patternDirectory(slug).appendingPathComponent(name))
    }

    /// A chart file by manifest-relative path. Not cached here: the ChartLibrary keeps what a project needs.
    func chartData(for slug: String, path: String) async throws -> Data {
        let response = try await client.get(url(for: "patterns/\(slug)/\(path)"), ifNoneMatch: nil)
        guard response.status == 200 else { throw StoreError.http(response.status) }
        return response.data
    }

    // MARK: plumbing

    private func url(for sitePath: String) -> URL { baseURL.appendingPathComponent(sitePath) }

    private func conditionalGet(sitePath: String, cacheFile: URL) async throws -> Data {
        let etagFile = cacheFile.appendingPathExtension("etag")
        let cached = try? Data(contentsOf: cacheFile)
        let etag = cached == nil ? nil : try? String(contentsOf: etagFile, encoding: .utf8)
        let response = try await client.get(url(for: sitePath), ifNoneMatch: etag)
        switch response.status {
        case 200:
            try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try response.data.write(to: cacheFile, options: .atomic)
            if let tag = response.etag { try tag.write(to: etagFile, atomically: true, encoding: .utf8) }
            else { try? FileManager.default.removeItem(at: etagFile) }
            return response.data
        case 304:
            guard let cached else { throw StoreError.noCache }
            return cached
        default:
            throw StoreError.http(response.status)
        }
    }

    private func cachedBytes(sitePath: String, cacheFile: URL) async -> Data? {
        if let data = try? Data(contentsOf: cacheFile) { return data }
        guard let response = try? await client.get(url(for: sitePath), ifNoneMatch: nil), response.status == 200 else { return nil }
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? response.data.write(to: cacheFile, options: .atomic)
        return response.data
    }
}
