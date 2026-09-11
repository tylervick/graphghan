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

    /// Downloads and validates the chart first; a project exists only once its chart is on disk.
    func startProject(manifest: PatternManifest, chart: ManifestChart, title: String) async throws -> Project {
        let data = try await patterns.chartData(for: manifest.id, path: chart.path)
        let decoded = try Chart.load(data)  // in memory; no file yet
        guard decoded.id == chart.id else { throw ServiceError.chartMismatch(expected: chart.id, got: decoded.id) }
        _ = try await charts.store(data)  // now safe to persist
        let project = Project(patternID: manifest.id, chartID: chart.id, chartVariant: chart.variant, chartGaugeKey: chart.gaugeKey,
                              patternVersion: manifest.version, title: title.isEmpty ? manifest.title : title, started: now())
        context.insert(project)
        try save()
        return project
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
        guard let step = WorkEngine.apply(action, to: project.cursor, in: sequence) else { return nil }
        let t = now()
        project.cursor = step.cursor
        project.lastWorked = t
        if step.finished {
            project.finished = t
        } else if step.kind == .back || step.kind == .jump, !WorkEngine.isFinished(step.cursor, in: sequence) {
            // Working backwards or jumping away from the end un-finishes the project, so Work is
            // offered again instead of the detail screen becoming a dead end.
            project.finished = nil
        }
        let event = ProgressEvent(t: t, row: step.cursor.row, run: step.cursor.run, kind: step.kind)
        event.project = project
        context.insert(event)
        do {
            try save()
        } catch {
            // lastError is already set by save(); in-memory state and the pending event stay
            // queued for the next save.
        }
        return step
    }

    func summary(for project: Project, sequence: WorkSequence) -> ProgressSummary {
        Pace.summarize(events: project.eventRecords, cursor: project.cursor, sequence: sequence)
    }

    func estimatedFinish(for project: Project, sequence: WorkSequence) -> Date? {
        let s = summary(for: project, sequence: sequence)
        return Pace.estimatedFinish(remainingStitches: s.totalStitches - s.stitchesDone, stitchesPerHour: s.stitchesPerHour, sessions: s.sessions, now: now())
    }

    func setNotes(_ text: String, for project: Project) throws {
        project.notes = text
        try save()
    }

    func markFinished(_ project: Project) throws {
        project.finished = now()
        try save()
    }

    func markUnfinished(_ project: Project) throws {
        project.finished = nil
        try save()
    }

    func delete(_ project: Project) throws {
        context.delete(project)
        try save()
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
    }

    func exportDocument(for project: Project) -> ProgressDocument {
        ProgressDocument(patternID: project.patternID, chartID: project.chartID, patternVersion: project.patternVersion,
                         cursor: project.cursor, started: project.started, finished: project.finished, events: project.eventRecords)
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
