import Foundation
import Observation
import SwiftData
import UIKit
import GraphghanCore

/// App-wide state: the stores, the library as last loaded, navigation between tabs, and the
/// project currently open on the Work screen.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case patterns, projects }

    let patterns: PatternStore
    let charts: ChartLibrary
    let projects: ProjectService

    var tab: Tab = .patterns
    var index: [IndexEntry] = []
    /// A refresh failed but cached data is shown.
    var libraryBanner: String?
    /// Nothing to show at all (offline with no cache).
    var libraryError: String?
    var isLoadingLibrary = false
    var workingProject: Project?

    private var manifests: [String: PatternManifest] = [:]
    private var images: [String: UIImage] = [:]

    init(context: ModelContext, patterns: PatternStore, charts: ChartLibrary) {
        self.patterns = patterns
        self.charts = charts
        self.projects = ProjectService(context: context, charts: charts, patterns: patterns)
    }

    static func live(context: ModelContext) -> AppModel {
        AppModel(context: context,
                 patterns: PatternStore(cacheDirectory: AppGroup.patternsCacheURL, client: URLSessionHTTPClient()),
                 charts: ChartLibrary(directory: AppGroup.chartsURL))
    }

    // MARK: library

    func loadLibrary(force: Bool = false) async {
        if !force, !index.isEmpty { return }
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        let cached = await patterns.cachedIndex()
        if let cached, index.isEmpty { index = cached }
        do {
            index = try await patterns.refreshIndex()
            libraryBanner = nil
            libraryError = nil
        } catch {
            if index.isEmpty {
                libraryError = "Couldn't reach graphghan.milo.cat. Connect to the internet and try again."
            } else {
                libraryBanner = "Showing the last downloaded library; couldn't check for updates."
            }
        }
    }

    func cachedManifest(for slug: String) -> PatternManifest? {
        manifests[slug]
    }

    /// The cached manifest when there is one, refreshed in the background; otherwise fetched.
    func manifest(for slug: String, path: String?) async throws -> PatternManifest {
        if let m = manifests[slug] { return m }
        if let cached = await patterns.cachedManifest(for: slug) {
            manifests[slug] = cached
            Task { [weak self] in
                if let fresh = try? await self?.patterns.refreshManifest(for: slug, path: path) { self?.manifests[slug] = fresh }
            }
            return cached
        }
        let fresh = try await patterns.refreshManifest(for: slug, path: path)
        manifests[slug] = fresh
        return fresh
    }

    func preview(for slug: String, sitePath: String) async -> UIImage? {
        if let image = images[sitePath] { return image }
        guard let data = await patterns.preview(for: slug, sitePath: sitePath), let image = UIImage(data: data) else { return nil }
        images[sitePath] = image
        return image
    }

    func chartPreview(for slug: String, path: String) async -> UIImage? {
        let key = "\(slug)/\(path)"
        if let image = images[key] { return image }
        guard let data = await patterns.chartPreview(for: slug, path: path), let image = UIImage(data: data) else { return nil }
        images[key] = image
        return image
    }

    /// A chart for browsing: the library copy if a project already has it, else a download kept in memory.
    func browseChart(manifest: PatternManifest, chart: ManifestChart) async throws -> Chart {
        if await charts.hasChart(id: chart.id) { return try await charts.chart(id: chart.id) }
        return try Chart.load(await patterns.chartData(for: manifest.id, path: chart.path))
    }

    func startProject(manifest: PatternManifest, chart: ManifestChart, title: String) async throws {
        _ = try await projects.startProject(manifest: manifest, chart: chart, title: title)
        tab = .projects
    }
}
