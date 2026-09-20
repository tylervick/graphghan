import Foundation
import Observation
import SwiftData
import GraphghanCore

/// Every mutation of a project goes through here: the Work screen, and later the Live Activity
/// intents, call `apply`, so cursor and event are always written together.
@MainActor
@Observable
final class ProjectService {
    enum ServiceError: Error, Equatable {
        case chartMismatch(expected: String, got: String)
        case cursorNotAtStart
        case chartUnavailable(String)
    }

    enum VersionNotice: Equatable {
        case chartChanged(newChart: ManifestChart, newVersion: String, canSwitch: Bool)
    }

    private let context: ModelContext
    /// `ModelContext` does not retain its `ModelContainer`; a context built from a container that's
    /// only a local in some setup function would otherwise dangle the moment that function returns.
    private let container: ModelContainer
    let charts: ChartLibrary
    let patterns: PatternStore
    /// Injected clock so tests control timestamps.
    var now: @Sendable () -> Date = { Date() }
    /// The last storage error, for a one-time banner. Never blocks advancing.
    var lastError: String?
    /// Called after every successful step (whether or not the save succeeded): the Live Activity updates from here.
    var onApply: ((Project, WorkSequence, WorkStep) -> Void)?
    /// Called when the set of projects, or what one is, changes: started, finished or unfinished
    /// (by hand or by the last Done), switched to a new chart, deleted. Not on a plain step. The
    /// Spotlight index of projects hangs off this (App Intents spec §4.2).
    var onProjectsChanged: (() -> Void)?
    /// Called after every successful step with the sequence it was applied in: the one project's
    /// Spotlight entry follows its cursor from here (App Intents spec §4.2).
    var onStep: ((Project, WorkSequence) -> Void)?
    /// The project on the Work screen right now. `summary(for:)` walks every event of a project,
    /// so nothing may compute it for this one while taps are landing (#79); the debug assertion in
    /// `summary` is the guard, the summary-refresh key in the views is what keeps it satisfied.
    var workingProjectID: UUID?

    init(context: ModelContext, charts: ChartLibrary, patterns: PatternStore) {
        self.context = context
        self.container = context.container
        self.charts = charts
        self.patterns = patterns
    }

    func projects() throws -> [Project] {
        var descriptor = FetchDescriptor<Project>()
        descriptor.sortBy = [SortDescriptor(\.lastWorked, order: .reverse), SortDescriptor(\.started, order: .reverse)]
        return try context.fetch(descriptor)
    }

    /// Validates the chart first; a project exists only once its chart is on disk. The library's
    /// copy wins over a download when it already holds this chart id -- which is the only way a
    /// pattern opened from a file can start at all (there is nothing to fetch), and which also
    /// lets a second project start from a site pattern offline.
    func startProject(manifest: PatternManifest, chart: ManifestChart, title: String) async throws -> Project {
        let stored = await charts.hasChart(id: chart.id)
        let data = stored ? try await charts.data(id: chart.id)
                          : try await patterns.chartData(for: manifest.id, path: chart.path)
        let decoded = try Chart.load(data)  // in memory; no file yet
        guard decoded.id == chart.id else { throw ServiceError.chartMismatch(expected: chart.id, got: decoded.id) }
        _ = try await charts.store(data)  // now safe to persist
        let project = Project(patternID: manifest.id, chartID: chart.id, chartVariant: chart.variant, chartGaugeKey: chart.gaugeKey,
                              patternVersion: manifest.version, title: title.isEmpty ? manifest.title : title, started: now())
        context.insert(project)
        try save()
        onProjectsChanged?()
        return project
    }

    /// Looks a project up by its stable `id`, for callers that only have the identifier -- the
    /// Live Activity intents, which cross a process boundary and so cannot hold the object.
    func project(id: UUID) throws -> Project? {
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func chart(for project: Project) async throws -> Chart {
        do { return try await charts.chart(id: project.chartID) }
        catch { throw ServiceError.chartUnavailable(project.chartID) }
    }

    func sequence(for project: Project) async throws -> WorkSequence {
        try WorkSequence(chart: try await chart(for: project))
    }

    /// Never blocks advancing on a storage failure (spec 6.6): the cursor and event are always
    /// mutated in memory and returned, whether or not the save behind them succeeds. A failed save
    /// sets `lastError` for the banner and leaves the mutated project and the inserted event queued
    /// -- the next successful `save()` (from any mutator) persists them.
    @discardableResult
    func apply(_ action: WorkAction, to project: Project, in sequence: WorkSequence) -> WorkStep? {
        guard let step = WorkEngine.apply(action, to: project.cursor, in: sequence, step: project.step, perRepetition: project.tapPerRepetition) else { return nil }
        let t = now()
        let wasFinished = project.isFinished
        project.cursor = step.cursor
        project.lastWorked = t
        if step.finished {
            project.finished = t
        } else if step.kind == .back || step.kind == .jump, !WorkEngine.isFinished(step.cursor, in: sequence) {
            // Working backwards or jumping away from the end un-finishes the project, so Work is
            // offered again instead of the detail screen becoming a dead end.
            project.finished = nil
        }
        let finishedChanged = wasFinished != project.isFinished
        let event = ProgressEvent(t: t, row: step.cursor.row, run: step.cursor.run, stitch: step.cursor.stitch, kind: step.kind)
        event.project = project
        context.insert(event)
        do {
            try save()
        } catch {
            // lastError is already set by save(); in-memory state and the pending event stay
            // queued for the next save.
        }
        onApply?(project, sequence, step)
        onStep?(project, sequence)
        if finishedChanged { onProjectsChanged?() }
        return step
    }

    /// The project's event log as the core package's value type, oldest first: a fetch by
    /// predicate, so a tap never pays for the history it has already written (#79).
    func events(for project: Project) throws -> [ProgressEventRecord] {
        let id = project.id
        var descriptor = FetchDescriptor<ProgressEvent>(predicate: #Predicate { $0.project?.id == id })
        descriptor.sortBy = [SortDescriptor(\.t)]
        return try context.fetch(descriptor).map { ProgressEventRecord(t: $0.t, row: $0.row, run: $0.run, stitch: $0.stitch, kind: $0.kind) }
    }

    /// Throws when the event log cannot be read: an empty history would look like a project with no
    /// sessions and no pace, which is a wrong answer, not a degraded one.
    func summary(for project: Project, sequence: WorkSequence) throws -> ProgressSummary {
        assert(project.id != workingProjectID, "the summary walks every event; never compute it for the project being worked")
        return Pace.summarize(events: try events(for: project), cursor: project.cursor, sequence: sequence)
    }

    func estimatedFinish(for project: Project, sequence: WorkSequence) throws -> Date? {
        estimatedFinish(from: try summary(for: project, sequence: sequence))
    }

    /// The estimate from a summary the caller already holds: `summary(for:)` walks every event of
    /// the project, so a view that shows both must not compute it twice.
    func estimatedFinish(from s: ProgressSummary) -> Date? {
        Pace.estimatedFinish(remainingCells: s.totalCells - s.cellsDone, stitchesPerHour: s.stitchesPerHour, sessions: s.sessions, now: now())
    }

    func setNotes(_ text: String, for project: Project) throws {
        project.notes = text
        try save()
    }

    func setCountStep(_ step: CountStep, for project: Project) throws {
        project.step = step
        try save()
    }

    func setTapPerRepetition(_ on: Bool, for project: Project) throws {
        project.tapPerRepetition = on
        try save()
    }

    func setBandStyle(_ style: BandStyle, for project: Project) throws {
        project.chartStyle = style
        try save()
    }

    func markFinished(_ project: Project) throws {
        project.finished = now()
        try save()
        onProjectsChanged?()
    }

    func markUnfinished(_ project: Project) throws {
        project.finished = nil
        try save()
        onProjectsChanged?()
    }

    /// Deletes the project and its events: with no to-many array there is no cascade to lean on.
    func delete(_ project: Project) throws {
        let id = project.id
        try context.delete(model: ProgressEvent.self, where: #Predicate { $0.project?.id == id })
        context.delete(project)
        try save()
        onProjectsChanged?()
    }

    /// Spec 4.5: same chart id means nothing changed, whatever the version says.
    func versionNotice(for project: Project, manifest: PatternManifest) -> VersionNotice? {
        guard let published = manifest.charts.first(where: { $0.variant == project.chartVariant && $0.gaugeKey == project.chartGaugeKey }) else { return nil }
        guard published.id != project.chartID else { return nil }
        return .chartChanged(newChart: published, newVersion: manifest.version, canSwitch: project.cursor == .start)
    }

    func switchChart(_ project: Project, to chart: ManifestChart, manifest: PatternManifest) async throws {
        guard project.cursor == .start else { throw ServiceError.cursorNotAtStart }
        let data = try await patterns.chartData(for: manifest.id, path: chart.path)
        let decoded = try Chart.load(data)  // in memory; no file yet
        guard decoded.id == chart.id else { throw ServiceError.chartMismatch(expected: chart.id, got: decoded.id) }
        _ = try await charts.store(data)  // now safe to persist
        project.chartID = chart.id
        project.chartVariant = chart.variant
        project.chartGaugeKey = chart.gaugeKey
        project.patternVersion = manifest.version
        try save()
        onProjectsChanged?()
    }

    /// Throws when the event log cannot be read: a document without its history is not an export.
    func exportDocument(for project: Project) throws -> ProgressDocument {
        ProgressDocument(patternID: project.patternID, chartID: project.chartID, patternVersion: project.patternVersion,
                         cursor: project.cursor, started: project.started, finished: project.finished,
                         events: try events(for: project))
    }

    private func save() throws {
        do {
            try context.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
}
