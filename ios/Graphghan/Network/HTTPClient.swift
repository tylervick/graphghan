import Foundation

struct HTTPResponse: Sendable {
    let status: Int
    let data: Data
    let etag: String?
}

/// The one network seam. Tests substitute a stub; the app uses URLSession.
protocol HTTPClient: Sendable {
    func get(_ url: URL, ifNoneMatch: String?) async throws -> HTTPResponse
}

struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func get(_ url: URL, ifNoneMatch: String?) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData  // PatternStore manages its own cache with ETags
        if let ifNoneMatch { request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        return HTTPResponse(status: http?.statusCode ?? 0, data: data, etag: http?.value(forHTTPHeaderField: "ETag"))
    }
}
