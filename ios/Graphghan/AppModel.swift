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
    let liveActivity: LiveActivityController

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
    /// Charts seen this launch, so the synchronous `onApply` hook can build activity info without an await.
    private var chartCache: [String: Chart] = [:]
    /// The activity refresh the last `apply` kicked off, so an intent can wait for it (below).
    private var activityUpdate: Task<Void, Never>?

    init(context: ModelContext, patterns: PatternStore, charts: ChartLibrary,
         activityBackend: ActivityBackend = ActivityKitBackend(),
         defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard) {
        self.patterns = patterns
        self.charts = charts
        self.projects = ProjectService(context: context, charts: charts, patterns: patterns)
        self.liveActivity = LiveActivityController(backend: activityBackend, defaults: defaults)
        // One mutation path, one activity refresh: every step -- Work screen or lock-screen button --
        // pushes the state it just wrote. The hook is synchronous, so it needs a cached chart; a
        // project with an activity always has one, because starting or reconciling that activity
        // read the chart. Without it the hook does nothing, which is what an activity-less project
        // wants anyway.
        projects.onApply = { [weak self] project, sequence, step in
            guard let self, let chart = self.chartCache[project.chartID] else { return }
            let info = LiveActivityState.info(projectID: project.id, chart: chart, sequence: sequence)
            guard let state = LiveActivityState.make(cursor: step.cursor, sequence: sequence) else { return }
            self.activityUpdate = Task { await self.liveActivity.update(projectID: project.id, info: info, state: state) }
        }
        WorkIntentHandler.shared.perform = { [weak self] action, id in await self?.performIntent(action, projectID: id) }
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

    // MARK: live activity

    /// The attributes and current state for a project, or nil when its chart cannot be read.
    func activityState(for project: Project) async -> (WorkActivityInfo, WorkActivityState)? {
        guard let chart = try? await projects.chart(for: project), let sequence = try? WorkSequence(chart: chart),
              let state = LiveActivityState.make(cursor: project.cursor, sequence: sequence) else { return nil }
        chartCache[project.chartID] = chart
        return (LiveActivityState.info(projectID: project.id, chart: chart, sequence: sequence), state)
    }

    /// A lock-screen button: same mutation path as the Work screen, then the activity updates via
    /// `onApply`. The intent waits for that refresh so the lock screen the system snapshots when
    /// the intent returns already shows the new run.
    func performIntent(_ action: WorkAction, projectID: UUID) async {
        guard let project = try? projects.project(id: projectID) else {
            await endActivityUnavailable(projectID: projectID)
            return
        }
        guard let chart = try? await projects.chart(for: project), let sequence = try? WorkSequence(chart: chart) else {
            await endActivityUnavailable(projectID: projectID)
            return
        }
        chartCache[project.chartID] = chart
        _ = projects.apply(action, to: project, in: sequence)
        await activityUpdate?.value
    }

    private func endActivityUnavailable(projectID: UUID) async {
        // The closure only reads the store and builds state -- never a public LiveActivityController
        // method, which would deadlock on the mutex `reconcile` already holds.
        await liveActivity.reconcile { [weak self] info in
            guard info.projectID == projectID else {
                // another project's activity is refreshed from its own stored cursor, never ended
                guard let self, let p = try? self.projects.project(id: info.projectID) else { return nil }
                return await self.activityState(for: p)?.1
            }
            return nil
        }
    }

    /// Launch-time reconciliation (spec §7): the stored cursor wins; stale activities end.
    func reconcileActivities() async {
        // As above: the closure must not call a public LiveActivityController method.
        await liveActivity.reconcile { [weak self] info in
            guard let self, let project = try? self.projects.project(id: info.projectID) else { return nil }
            return await self.activityState(for: project)?.1
        }
    }
}
