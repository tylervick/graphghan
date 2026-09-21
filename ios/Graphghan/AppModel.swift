import Foundation
import Observation
import SwiftData
import UIKit
import GraphghanCore
import ProseReaderKit

/// App-wide state: the stores, the library as last loaded, navigation between tabs, and the
/// project currently open on the Work screen.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case patterns, projects }

    let patterns: PatternStore
    let charts: ChartLibrary
    /// Patterns opened from a file (#16), which the site knows nothing about.
    let localPatterns: LocalPatternStore
    let projects: ProjectService
    let liveActivity: LiveActivityController
    /// The written-row reader for PDFs (#112): the on-device model when this iPhone has one, else
    /// nil with `modelUnavailable` saying why.
    let rowReader: (any RowReading)?
    let modelUnavailable: String?

    var tab: Tab = .patterns
    var index: [IndexEntry] = []
    /// The local patterns as last loaded, newest import first in the Patterns tab's own section.
    var localIndex: [IndexEntry] = []
    /// The Patterns tab's navigation stack, so an import can land on what it just opened.
    var libraryPath: [LibraryItem] = []
    /// Why the last bundle was refused, for the alert. Nil when nothing has gone wrong.
    var importFailure: String?
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
         localPatterns: LocalPatternStore,
         activityBackend: ActivityBackend = ActivityKitBackend(),
         defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard,
         rowReader: (any RowReading)?? = nil, modelUnavailable: String?? = nil) {
        self.patterns = patterns
        self.charts = charts
        self.localPatterns = localPatterns
        // Double optionals: not given resolves the device's model; given nil means none (tests).
        if let rowReader {
            self.rowReader = rowReader
            self.modelUnavailable = modelUnavailable ?? nil
        } else if #available(iOS 26, *) {
            // One session across the whole read, not one a row: a phone counts how often an app
            // asks its model, and a session a row is what #176 turned into "Request has been
            // rate limited" from the first row. `ReaderSession` turns the session over before
            // the window fills.
            let reader = ProseReader(model: .onDevice, options: ReaderOptions(reuseSession: true, examples: true))
            let why = reader.unavailableReason()
            self.rowReader = why == nil ? reader : nil
            self.modelUnavailable = why
        } else {
            self.rowReader = nil
            self.modelUnavailable = "needs iOS 26"
        }
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
                             charts: ChartLibrary(directory: AppGroup.chartsURL),
                             localPatterns: LocalPatternStore(directory: AppGroup.localPatternsURL))
        model.registerIntentHandler()
        model.indexesProjects = true
        return model
    }

    // MARK: library

    /// Both halves of the Patterns tab, in one value: the local patterns first, then the site's.
    var libraryItems: [LibraryItem] {
        localIndex.map { LibraryItem(entry: $0, source: .local) }
            + index.map { LibraryItem(entry: $0, source: .site) }
    }

    func isLocal(_ slug: String) -> Bool { localIndex.contains { $0.slug == slug } }

    /// The local section. Cheap (a directory of small JSON files) and load-bearing well before the
    /// Patterns tab is opened -- a project's row needs to know its pattern is local to find its
    /// preview -- so the app calls it at launch as well as on every library refresh.
    func loadLocalPatterns() async {
        localIndex = await localPatterns.manifests().map(IndexEntry.init(manifest:))
    }

    func loadLibrary(force: Bool = false) async {
        await loadLocalPatterns()
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
    ///
    /// Local first, by pattern id: a pattern opened from a file has no site path to refresh
    /// against, and a project started from one must never be told the site has a newer chart.
    /// The cost is that a bundle whose id matches a published slug shadows it (#135).
    func manifest(for slug: String, path: String?) async throws -> PatternManifest {
        if let local = await localPatterns.manifest(for: slug) {
            manifests[slug] = local
            return local
        }
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

    /// A pattern's own preview. `sitePath` is what the site index gives; a local pattern ignores
    /// it and answers from its own directory, so every caller that has only a pattern id -- a
    /// project row, say -- gets the right picture without knowing where the pattern came from.
    func preview(for slug: String, sitePath: String) async -> UIImage? {
        if isLocal(slug) {
            let key = "local:\(slug)"
            if let image = images[key] { return image }
            guard let manifest = await localPatterns.manifest(for: slug),
                  let data = await localPatterns.preview(for: slug, path: manifest.preview),
                  let image = UIImage(data: data) else { return nil }
            images[key] = image
            return image
        }
        if let image = images[sitePath] { return image }
        guard let data = await patterns.preview(for: slug, sitePath: sitePath), let image = UIImage(data: data) else { return nil }
        images[sitePath] = image
        return image
    }

    /// A chart's preview by its manifest-relative path, which is the same string either way.
    func chartPreview(for slug: String, path: String) async -> UIImage? {
        let key = "\(slug)/\(path)"
        if let image = images[key] { return image }
        let data = if isLocal(slug) { await localPatterns.preview(for: slug, path: path) }
                   else { await patterns.chartPreview(for: slug, path: path) }
        guard let data, let image = UIImage(data: data) else { return nil }
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

    // MARK: opening a bundle (#16)

    /// A `.graphghan` file, however it arrived. Nothing is written unless the whole bundle
    /// validates, so a refusal leaves the library exactly as it was and only sets the sentence
    /// for the alert. On success the Patterns tab opens on the pattern that just arrived --
    /// landing on what you opened is the point of the gesture.
    @discardableResult
    func importBundle(data: Data) async -> PatternManifest? {
        let importer = BundleImporter(charts: charts, local: localPatterns)
        do {
            let manifest = try await importer.importBundle(data)
            manifests[manifest.id] = manifest
            // A second version of a pattern may have redrawn its previews, and they are cached by
            // pattern id rather than by content: drop this pattern's, keep everyone else's.
            for key in images.keys where key == "local:\(manifest.id)" || key.hasPrefix("\(manifest.id)/") {
                images[key] = nil
            }
            await loadLocalPatterns()
            // A project's Spotlight entry carries its pattern's title, which this import may have
            // just supplied or changed; nothing else on this path tells the index that.
            scheduleReindex()
            importFailure = nil
            tab = .patterns
            if let item = libraryItems.first(where: { $0.source == .local && $0.slug == manifest.id }) {
                libraryPath = [item]
            }
            return manifest
        } catch let error as BundleError {
            importFailure = error.message
        } catch {
            importFailure = "That pattern couldn't be opened."
        }
        return nil
    }

    /// The same path, from a file URL: Files, Mail and AirDrop hand over a copy in the app's
    /// Inbox, which is deleted afterwards whether or not the import worked -- nothing else prunes
    /// it, and opening one file three times should not leave three copies behind.
    func importBundle(at url: URL) async { await importFile(at: url) }

    /// A file, however it arrived, routed by what it is: a bundle imports at once, a PDF opens
    /// the import sheet (#112). The Inbox copy, the size cap and the scoped read are shared.
    func importFile(at url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        defer { removeInboxCopy(at: url) }
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let cap = isPDF ? PDFImporter.maximumBytes : Self.maximumBundleBytes
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= cap else {
            if isPDF {
                let state = PDFImportState(fileName: url.lastPathComponent)
                state.stage = .failed(PDFImportError.tooBig.message)
                pdfImport = state
            } else {
                importFailure = "That file is too big to be a pattern."
            }
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            importFailure = "That file couldn't be read."
            return
        }
        if isPDF { await importPDF(data: data, fileName: url.lastPathComponent) } else { await importBundle(data: data) }
    }

    // MARK: opening a PDF (#112)

    /// The import sheet while a PDF is being read or shown; nil otherwise.
    var pdfImport: PDFImportState? = nil

    private var pdfImporter: PDFImporter {
        PDFImporter(charts: charts, local: localPatterns, rowReader: rowReader, modelUnavailable: modelUnavailable)
    }

    /// The sheet's reading states, then the chart found or the sentence for why not. Cancel
    /// cancels the task; the read then throws `.cancelled` and the sheet is already gone.
    func importPDF(data: Data, fileName: String) async {
        let state = PDFImportState(fileName: fileName)
        pdfImport = state
        let importer = pdfImporter
        // The rows-only path reads for minutes; the screen must not sleep part way through it (#176).
        IdleTimer.hold()
        let task = Task { [weak self] in
            defer { IdleTimer.release() }
            do {
                let reading = try await importer.read(data, fileName: fileName) { p in
                    Task { @MainActor in
                        if case .rows(let done, let of, let seconds) = p, state.stage != .found {
                            state.stage = .readingRows(done: done, of: of, secondsElapsed: seconds)
                        }
                    }
                }
                state.reading = reading
                state.preview = UIImage(data: reading.preview)
                state.stage = .found
                if case .grid = reading.source { self?.startPDFCheck(state, importer: importer) }
            } catch PDFImportError.cancelled {
                if self?.pdfImport === state { self?.pdfImport = nil }
            } catch let error as PDFImportError {
                state.stage = .failed(error.message)
            } catch {
                state.stage = .failed(PDFImportError.cannotOpen.message)
            }
        }
        state.task = task
        await task.value
    }

    /// The written rows against the chart, after the chart is on screen (spec §4.2). The record
    /// lands in `state.check`; "Add to library" writes it into the chart.
    private func startPDFCheck(_ state: PDFImportState, importer: PDFImporter) {
        guard let reading = state.reading else { return }
        if case .grid(_, let total) = reading.source, total > 0, rowReader != nil { state.check = .running(done: 0, of: total) }
        // The sheet arrives through `onOpenURL` while the scene is still activating from the share
        // sheet, and whether the system counts the app as foreground at this moment is #176's
        // first hypothesis. The probe's report prints what the scene was doing here.
        state.appStateAtCheck = Self.describe(UIApplication.shared.applicationState)
        IdleTimer.hold()
        state.checkTask = Task {
            defer { IdleTimer.release() }
            let record = await importer.check(reading) { p in
                Task { @MainActor in
                    if case .checking(let done, let of) = p, case .running = state.check { state.check = .running(done: done, of: of) }
                }
            }
            state.check = .done(record)
        }
    }

    static func describe(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    /// "Why?" under a busy check: the three probes of #176, run against the reader the app holds,
    /// with what the app knows about the moment the check started. Answers land in `state.probe`.
    func runModelProbe() async {
        guard let state = pdfImport, !state.probing, state.probe == nil else { return }
        state.probing = true
        defer { state.probing = false }
        var context = ["the app was \(Self.describe(UIApplication.shared.applicationState)) now"]
        if !state.appStateAtCheck.isEmpty { context.append("the app was \(state.appStateAtCheck) when the check started") }
        guard #available(iOS 26, *), let reader = rowReader as? ProseReader else {
            state.probe = ModelProbe(
                steps: [.init(kind: .availability, name: "the model is there", ok: false, detail: modelUnavailable ?? "no on-device reader", seconds: 0)],
                context: context)
            return
        }
        state.probe = await reader.probe(context: context)
    }

    /// "Measure the limit": the three probes all answered, so the refusal is not in any single
    /// request and the question is how many of them this phone will take (#176). Minutes long,
    /// and the screen is held awake for it.
    func measureModelLimit() async {
        guard let state = pdfImport, !state.measuring, state.limits == nil else { return }
        guard #available(iOS 26, *), let reader = rowReader as? ProseReader else { return }
        state.measuring = true
        state.measuringStep = "starting"
        IdleTimer.hold()
        defer {
            IdleTimer.release()
            state.measuring = false
        }
        let context = ["the app was \(Self.describe(UIApplication.shared.applicationState)) while measuring"]
        state.limits = await reader.measureRequestLimit(context: context) { step in
            Task { @MainActor in state.measuringStep = step }
        }
    }

    /// "Skip the check": the reader stops between rows; what it read is compared and recorded.
    func skipPDFCheck() {
        pdfImport?.checkTask?.cancel()
    }

    /// "Add to library": the bundle importer's order, then the same landing as an opened bundle.
    func addImportedPDF() async {
        guard let state = pdfImport, let reading = state.reading, state.stage == .found || state.stage == .saving else { return }
        state.stage = .saving
        // Adding before the check ends stops it; its record (stopped at the row it reached) is saved.
        if let task = state.checkTask { task.cancel(); await task.value }
        var record: ImportRecord?
        if case .done(let r) = state.check { record = r }
        let importer = pdfImporter
        do {
            let manifest = try await importer.save(reading, record: record)
            manifests[manifest.id] = manifest
            for key in images.keys where key == "local:\(manifest.id)" || key.hasPrefix("\(manifest.id)/") { images[key] = nil }
            await loadLocalPatterns()
            scheduleReindex()
            pdfImport = nil
            tab = .patterns
            if let item = libraryItems.first(where: { $0.source == .local && $0.slug == manifest.id }) { libraryPath = [item] }
        } catch {
            state.stage = .failed("That pattern couldn't be saved.")
        }
    }

    /// Cancel and swipe-down: nothing written. Not while a save runs (the sheet hides the button
    /// and blocks the swipe then); the save finishes and lands as usual.
    func cancelPDFImport() {
        guard let state = pdfImport, state.stage != .saving else { return }
        state.task?.cancel()
        state.checkTask?.cancel()
        pdfImport = nil
    }

    /// Bigger than any pattern can plausibly be, checked before a byte is read.
    static let maximumBundleBytes = 64 << 20

    private func removeInboxCopy(at url: URL) {
        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .map { $0.appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL.path }
        guard inbox.contains(where: { url.standardizedFileURL.path.hasPrefix($0 + "/") }) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// `--import <path>` on the command line imports that file at launch: the simulator check is
    /// a command rather than a drag, and an app test drives the identical path.
    static func launchImportURL(_ arguments: [String]) -> URL? {
        guard let i = arguments.firstIndex(of: "--import"), i + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[i + 1])
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
        // Local first, like every other lookup by pattern id (#135).
        var patternTitle = await localPatterns.manifest(for: project.patternID)?.title
        if patternTitle == nil { patternTitle = await patterns.cachedManifest(for: project.patternID)?.title }
        return ProjectSnapshot(id: project.id, title: project.title, patternTitle: patternTitle ?? project.patternID, percent: percent,
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
