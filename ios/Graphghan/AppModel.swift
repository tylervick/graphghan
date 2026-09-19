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
    var workingProject: Project? {
        didSet { projects.workingProjectID = workingProject?.id }
    }

    private var manifests: [String: PatternManifest] = [:]
    private var images: [String: UIImage] = [:]
    /// Charts seen this launch, so the synchronous `onApply` hook can build activity info without an await.
    private var chartCache: [String: Chart] = [:]
    /// The activity refresh the last `apply` kicked off, so an intent can wait for it (below).
    private var activityUpdate: Task<Void, Never>?
    /// The Spotlight work the last project change kicked off (spec §4.2), so tests can wait for it.
    /// Every scheduled task awaits the one before it, so refreshes and upserts land in the order
    /// they were asked for: an older full refresh can never re-add an entity a newer one deleted.
    private(set) var indexUpdate: Task<Void, Never>?
    /// Bumped by every full refresh; a queued refresh that is no longer the newest skips its work.
    private var indexGeneration = 0
    /// What the index does with the projection. Only the live app indexes (`live()` turns this on
    /// and points these at `ProjectIndexer`); merely constructing a model must not touch Spotlight,
    /// so tests record instead.
    var indexesProjects = false
    var reindex: @MainActor ([ProjectSnapshot]) async -> Void = { snapshots in
        if #available(iOS 18, *) { await ProjectIndexer.refresh(snapshots) }
    }
    var reindexOne: @MainActor (ProjectSnapshot) async -> Void = { snapshot in
        if #available(iOS 18, *) { await ProjectIndexer.upsert(snapshot) }
    }

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
            guard let state = LiveActivityState.make(cursor: step.cursor, sequence: sequence, perRepetition: project.tapPerRepetition) else { return }
            self.activityUpdate = Task { await self.liveActivity.update(projectID: project.id, info: info, state: state) }
        }
        // A step changes one project's percent and last-worked, which Spotlight shows under the
        // title: upsert that one entity, with the sequence the step already has, so the tap path
        // never pays for the full refresh's chart loads (#79).
        projects.onStep = { [weak self] project, sequence in self?.scheduleReindex(of: project, sequence: sequence) }
        projects.onProjectsChanged = { [weak self] in self?.scheduleReindex() }
    }

    /// Claims the process-wide handler the intents call. Only the app's one live model does this --
    /// merely constructing an `AppModel` must not steal the handler from another one.
    func registerIntentHandler() {
        WorkIntentHandler.shared.perform = { [weak self] action, id in await self?.performIntent(action, projectID: id) }
        WorkIntentHandler.shared.performWorking = { [weak self] action, chosen in await self?.performIntent(action, chosen: chosen) ?? .noProject }
        WorkIntentHandler.shared.projectSnapshots = { [weak self] in await self?.projectSnapshots() ?? [] }
    }

    static func live(context: ModelContext) -> AppModel {
        let model = AppModel(context: context,
                             patterns: PatternStore(cacheDirectory: AppGroup.patternsCacheURL, client: URLSessionHTTPClient()),
                             charts: ChartLibrary(directory: AppGroup.chartsURL))
        model.registerIntentHandler()
        model.indexesProjects = true
        return model
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
              let state = LiveActivityState.make(cursor: project.cursor, sequence: sequence, perRepetition: project.tapPerRepetition) else { return nil }
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
        // A tap can launch the app in the background, where the launch reconcile (a scene `.task`)
        // may never run: the controller then holds no current activity and would drop the refresh.
        // `start` adopts the activity that is already live for this project, so the refresh lands.
        if liveActivity.currentProjectID != projectID {
            await adoptActivity(for: project, chart: chart, sequence: sequence)
        }
        _ = await step(action, on: project, chart: chart, sequence: sequence)
    }

    /// A Done or Back said to Siri, or from the Action Button (spec §3): the same mutation path as
    /// the Work screen and the lock-screen button, on the project the maker chose or the one
    /// `resolveWorkingProject` picks. Voice never starts a Live Activity for a project that has none
    /// -- the Work screen owns that lifecycle -- but a Done said while one is up refreshes it, and one
    /// said while the Work screen is still open restarts an activity the system ended at its 8-hour
    /// limit, the same as a tap.
    func performIntent(_ action: WorkAction, chosen: UUID? = nil) async -> WorkIntentOutcome {
        let project: Project
        if let chosen {
            guard let named = try? projects.project(id: chosen) else { return .noProject }
            project = named
        } else {
            switch (try? resolveWorkingProject()) ?? .noProject {
            case .noProject: return .noProject
            case .ambiguous(let candidates):
                var snapshots: [ProjectSnapshot] = []
                for candidate in candidates { snapshots.append(await snapshot(for: candidate)) }
                return .ambiguous(snapshots)
            case .one(let working): project = working
            }
        }
        guard let chart = try? await projects.chart(for: project), let sequence = try? WorkSequence(chart: chart) else {
            return .chartUnavailable(title: project.title)
        }
        if liveActivity.currentProjectID != project.id, liveActivity.liveProjectID == project.id {
            await adoptActivity(for: project, chart: chart, sequence: sequence)
        }
        guard let step = await step(action, on: project, chart: chart, sequence: sequence) else { return .nowhereToGo(action) }
        return .moved(WorkIntentLanding(step: step, sequence: sequence, chart: chart, countStep: project.step, perRepetition: project.tapPerRepetition))
    }

    enum WorkingProject: Equatable {
        case noProject
        case one(Project)
        /// Rule 2 could not choose (spec §4.3): every unfinished project worked within an hour of
        /// the most recent one, most recent first.
        case ambiguous([Project])
    }

    /// Spec §3.2, in order: the project whose Live Activity is running, else the unfinished project
    /// worked most recently, else none. A project never worked counts from when it was started, so
    /// a maker who just started one and says "done" is not told they have no project going. Two
    /// unfinished projects worked within the same hour are a question, not a guess (spec §4.3).
    func resolveWorkingProject() throws -> WorkingProject {
        if let id = liveActivity.liveProjectID, let project = try projects.project(id: id), !project.isFinished { return .one(project) }
        func key(_ p: Project) -> Date { p.lastWorked ?? p.started }
        let unfinished = try projects.projects().filter { !$0.isFinished }.sorted { key($0) > key($1) }
        guard let first = unfinished.first else { return .noProject }
        let peers = unfinished.filter { key(first).timeIntervalSince(key($0)) < Self.ambiguityWindow }
        return peers.count > 1 ? .ambiguous(peers) : .one(first)
    }

    static let ambiguityWindow: TimeInterval = 3600

    // MARK: projects as data (spec §4.1)

    /// Every project as `ProjectEntity` and the Spotlight index see it. Percent comes from the
    /// cursor, as the lock screen computes it, not from `summary(for:)` -- that walks the event
    /// log, and may never run for the project being worked (#79).
    func projectSnapshots() async -> [ProjectSnapshot] {
        guard let all = try? projects.projects() else { return [] }
        var snapshots: [ProjectSnapshot] = []
        for project in all { snapshots.append(await snapshot(for: project)) }
        return snapshots
    }

    func snapshot(for project: Project) async -> ProjectSnapshot {
        await snapshot(for: project, sequence: try? await projects.sequence(for: project))
    }

    /// With a sequence the caller already holds, the only await is the manifest lookup.
    func snapshot(for project: Project, sequence: WorkSequence?) async -> ProjectSnapshot {
        var percent = 0.0
        if let sequence, let done = sequence.cellsBefore(project.cursor), sequence.totalCells > 0 {
            percent = (100 * Double(done) / Double(sequence.totalCells) * 10).rounded(.toNearestOrEven) / 10
        }
        let patternTitle = await patterns.cachedManifest(for: project.patternID)?.title ?? project.patternID
        return ProjectSnapshot(id: project.id, title: project.title, patternTitle: patternTitle, percent: percent,
                               lastWorked: project.lastWorked, isFinished: project.isFinished)
    }

    /// Spec §4.2: the index follows the store. Every mutation that changes what a project *is* or
    /// which projects exist lands here through `ProjectService.onProjectsChanged`, and the app calls
    /// it once at launch. Queued behind whatever index work is already running; skipped if a newer
    /// full refresh has been asked for since, because that one will see this one's state too.
    func scheduleReindex() {
        guard indexesProjects else { return }
        indexGeneration += 1
        let generation = indexGeneration
        let previous = indexUpdate
        indexUpdate = Task { [weak self] in
            await previous?.value
            guard let self, generation == self.indexGeneration else { return }
            await self.reindex(await self.projectSnapshots())
        }
    }

    /// One project moved: upsert its entity alone, in order with everything else queued.
    func scheduleReindex(of project: Project, sequence: WorkSequence) {
        guard indexesProjects else { return }
        let previous = indexUpdate
        indexUpdate = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.reindexOne(await self.snapshot(for: project, sequence: sequence))
        }
    }

    /// Tells the controller about the activity the system already shows for this project.
    private func adoptActivity(for project: Project, chart: Chart, sequence: WorkSequence) async {
        guard let state = LiveActivityState.make(cursor: project.cursor, sequence: sequence, perRepetition: project.tapPerRepetition) else { return }
        let info = LiveActivityState.info(projectID: project.id, chart: chart, sequence: sequence)
        await liveActivity.start(projectID: project.id, info: info, state: state)
    }

    /// The step every intent takes once it has its project: apply, then wait for the activity
    /// refresh `onApply` kicked off, so the lock screen the system snapshots when the intent
    /// returns already shows the new run.
    private func step(_ action: WorkAction, on project: Project, chart: Chart, sequence: WorkSequence) async -> WorkStep? {
        chartCache[project.chartID] = chart
        let step = projects.apply(action, to: project, in: sequence)
        await activityUpdate?.value
        return step
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
