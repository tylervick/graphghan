import Foundation
import GraphghanCore

/// Patterns opened from a `.graphghan` file: the manifest and the previews, one directory per
/// pattern id. Shaped like `PatternStore` so `AppModel` talks to the two the same way.
///
/// Chart files are not here -- they go to `ChartLibrary` under their chart id like every other
/// chart, which is also how an imported chart dedupes against a downloaded copy of the same one.
///
/// This lives in Application Support rather than beside the pattern cache in Caches, because iOS
/// purges Caches under disk pressure. For a site pattern that is free; for the only copy of a
/// pattern someone sent, it is data loss (design spec §6.3).
actor LocalPatternStore {
    private let directory: URL

    init(directory: URL) { self.directory = directory }

    private func patternDirectory(_ id: String) -> URL {
        directory.appendingPathComponent(id, isDirectory: true)
    }

    /// Every local pattern, by title. A directory whose manifest will not decode is skipped
    /// rather than fatal: the store answers with what it can read.
    func manifests() -> [PatternManifest] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { manifest(for: $0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func manifest(for id: String) -> PatternManifest? {
        let file = patternDirectory(id).appendingPathComponent(PatternBundle.manifestName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(PatternManifest.self, from: data)
    }

    func has(id: String) -> Bool { manifest(for: id) != nil }

    /// A preview by its manifest-relative path, e.g. `preview.png` or `charts/final-sc/preview.png`.
    func preview(for id: String, path: String) -> Data? {
        guard let url = safeURL(id: id, path: path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Writes the pattern's directory whole: built in a sibling temporary directory and swapped
    /// in, so a pattern folder is never half-written and re-importing replaces rather than merges.
    /// A chart the new version no longer lists stays in `ChartLibrary`; a project pinned its id
    /// and has to keep opening.
    func save(_ bundle: PatternBundle) throws {
        let id = bundle.manifest.id
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        // The manifest goes back as the bytes that arrived, not a re-encode (PatternBundle).
        try bundle.manifestData.write(to: staging.appendingPathComponent(PatternBundle.manifestName), options: .atomic)
        for (path, bytes) in bundle.previews {
            guard let destination = url(under: staging, path: path) else { continue }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try bytes.write(to: destination, options: .atomic)
        }

        let final = patternDirectory(id)
        if FileManager.default.fileExists(atPath: final.path) {
            try FileManager.default.removeItem(at: final)
        }
        try FileManager.default.moveItem(at: staging, to: final)
    }

    // MARK: paths

    /// A manifest-relative path resolved under a base, refusing anything that could leave it.
    /// `PatternBundle` already refuses these, and so does the zip reader; this is the third check
    /// because it is the one standing between a string and the filesystem.
    private func url(under base: URL, path: String) -> URL? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, !components.contains(where: { $0.isEmpty || $0 == ".." || $0 == "." }) else {
            return nil
        }
        return components.reduce(base) { $0.appendingPathComponent($1) }
    }

    private func safeURL(id: String, path: String) -> URL? {
        guard !id.isEmpty, !id.contains("/"), id != "..", !id.hasPrefix(".") else { return nil }
        return url(under: patternDirectory(id), path: path)
    }
}
