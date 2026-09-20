import Foundation
import GraphghanCore

/// Downloaded chart files, one per chart id, decoded once per launch. A chart is stored only if it
/// decodes and validates, so nothing under `charts/` is ever unreadable.
actor ChartLibrary {
    enum LibraryError: Error, Equatable {
        case missing(String)
        case badID(String)
    }

    private let directory: URL
    private var cache: [String: Chart] = [:]

    init(directory: URL) { self.directory = directory }

    private func fileURL(for id: String) throws -> URL {
        guard let hex = ChartID.hex(id) else { throw LibraryError.badID(id) }
        return directory.appendingPathComponent("\(hex).json")
    }

    func store(_ data: Data) throws -> Chart {
        let chart = try Chart.load(data)
        let url = try fileURL(for: chart.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        cache[chart.id] = chart
        return chart
    }

    /// The stored bytes, for a caller that needs the file rather than the decoded chart -- a
    /// project starting from a chart the library already holds, which must not re-download it.
    func data(id: String) throws -> Data {
        let url = try fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.missing(id) }
        return try Data(contentsOf: url)
    }

    func chart(id: String) throws -> Chart {
        if let chart = cache[id] { return chart }
        let url = try fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.missing(id) }
        let chart = try Chart.load(Data(contentsOf: url))
        cache[id] = chart
        return chart
    }

    func hasChart(id: String) -> Bool {
        if cache[id] != nil { return true }
        guard let url = try? fileURL(for: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func remove(id: String) throws {
        cache[id] = nil
        let url = try fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
