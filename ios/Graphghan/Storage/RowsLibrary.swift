import Foundation
import GraphghanCore

/// Downloaded written-rows documents, one per id, decoded once per launch. A document is stored
/// only if it decodes and validates, so nothing under `rows/` is ever unreadable.
actor RowsLibrary {
    enum LibraryError: Error, Equatable {
        case missing(String)
        case badID(String)
    }

    private let directory: URL
    private var cache: [String: RowsDocument] = [:]

    init(directory: URL) { self.directory = directory }

    private func fileURL(for id: String) throws -> URL {
        guard let hex = ChartID.hex(id) else { throw LibraryError.badID(id) }
        return directory.appendingPathComponent("\(hex).json")
    }

    func store(_ data: Data) throws -> RowsDocument {
        let document = try RowsDocument.load(data)
        let url = try fileURL(for: document.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        cache[document.id] = document
        return document
    }

    /// The stored bytes, for a caller that needs the file rather than the decoded document -- a
    /// project starting from a piece the library already holds, which must not re-download it.
    func data(id: String) throws -> Data {
        let url = try fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.missing(id) }
        return try Data(contentsOf: url)
    }

    func document(id: String) throws -> RowsDocument {
        if let document = cache[id] { return document }
        let url = try fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.missing(id) }
        let document = try RowsDocument.load(Data(contentsOf: url))
        cache[id] = document
        return document
    }

    func has(id: String) -> Bool {
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
