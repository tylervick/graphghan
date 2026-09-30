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
        /// A piece key the manifest does not have (spec 2026-09-25 §5.3).
        case pieceUnknown(PieceKey)
    }

    enum VersionNotice: Equatable {
        case chartChanged(newChart: ManifestChart, newVersion: String, canSwitch: Bool)
    }

    private let context: ModelContext
    /// `ModelContext` does not retain its `ModelContainer`; a context built from a container that's
    /// only a local in some setup function would otherwise dangle the moment that function returns.
    private let container: ModelContainer
    let charts: ChartLibrary
    /// Written-rows documents, for a pieced project's written pieces (spec 2026-09-25 §6.1).
    let rows: RowsLibrary
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

    init(context: ModelContext, charts: ChartLibrary, rows: RowsLibrary, patterns: PatternStore) {
        self.context = context
        self.container = context.container
        self.charts = charts
        self.rows = rows
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
        let finishedChanged = record(step, on: project, leftTheEnd: !WorkEngine.isFinished(step.cursor, in: sequence))
        onApply?(project, sequence, step)
        onStep?(project, sequence)
        if finishedChanged { onProjectsChanged?() }
        return step
    }

    /// The current piece's step, chart or written: the chart path is `apply(_:to:in:)` with its
    /// hooks; a written piece fires only `onProjectsChanged`, since `onApply`/`onStep` carry a
    /// `WorkSequence` a written piece does not have.
    @discardableResult
    func apply(_ action: WorkAction, to project: Project, work: PieceWork) -> WorkStep? {
        switch work {
        case .chart(_, let sequence):
            return apply(action, to: project, in: sequence)
        case .written(let seq):
            let finished = (try? currentProgress(of: project))?.finished != nil
            guard let step = WrittenEngine.apply(action, to: project.cursor, in: seq, finished: finished) else { return nil }
            // A written piece has no "past the end" cursor: finishing is a flag on its last row,
            // so any back or jump leaves it.
            if record(step, on: project, leftTheEnd: true) { onProjectsChanged?() }
            return step
        }
    }

    /// What every step writes, in one save: the cursor, the finish state and the event. For a
    /// pieced project the finish belongs to the current piece and the project finishes only
    /// with its last piece and assembly step. Returns whether the project's -- or, for a pieced
    /// project, the piece's -- finished state changed.
    private func record(_ step: WorkStep, on project: Project, leftTheEnd: Bool) -> Bool {
        let t = now()
        let wasFinished = project.isFinished
        project.cursor = step.cursor
        project.lastWorked = t
        // Working backwards or jumping away from the end un-finishes the project (or piece), so
        // Work is offered again instead of the detail screen becoming a dead end.
        let unfinishes = (step.kind == .back || step.kind == .jump) && leftTheEnd
        var pieceChanged = false
        if project.isPieced {
            if let progress = try? currentProgress(of: project) {
                let pieceWasFinished = progress.finished != nil
                progress.cursor = step.cursor
                if step.finished { progress.finished = t } else if unfinishes { progress.finished = nil }
                pieceChanged = pieceWasFinished != (progress.finished != nil)
            }
            updateProjectFinished(project)
        } else if step.finished {
            project.finished = t
        } else if unfinishes {
            project.finished = nil
        }
        let event = ProgressEvent(t: t, row: step.cursor.row, run: step.cursor.run, stitch: step.cursor.stitch, kind: step.kind,
                                  piece: project.currentPiece, copy: project.currentCopy)
        event.project = project
        context.insert(event)
        do {
            try save()
        } catch {
            // lastError is already set by save(); in-memory state and the pending event stay
            // queued for the next save.
        }
        return pieceChanged || wasFinished != project.isFinished
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
        try context.delete(model: PieceProgress.self, where: #Predicate { $0.project?.id == id })
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

// MARK: pieced projects (spec 2026-09-25 §5.4, §6.1, §6.2, §6.5)

extension ProjectService {
    /// Starts at the first piece. Every chart a piece names must already be in the library: a
    /// pieced pattern only ever arrives as a bundle, and the bundle import stored them.
    func startPiecedProject(manifest: PatternManifest, title: String) async throws -> Project {
        guard let first = manifest.pieces?.first else { throw ServiceError.pieceUnknown(PieceKey(piece: "", copy: 1)) }
        for id in Set(manifest.pieces?.compactMap(\.chart) ?? []) where !(await charts.hasChart(id: id)) {
            throw ServiceError.chartUnavailable(id)
        }
        let project = Project(patternID: manifest.id, chartID: "", chartVariant: "", chartGaugeKey: "",
                              patternVersion: manifest.version, title: title.isEmpty ? manifest.title : title, started: now())
        project.piecesTotal = manifest.piecesTotal
        project.assemblyTotal = manifest.assembly.count
        context.insert(project)
        do {
            try await selectPiece(PieceKey(piece: first.id, copy: 1), of: project, manifest: manifest)
        } catch {
            context.delete(project)
            try? save()
            throw error
        }
        onProjectsChanged?()
        return project
    }

    /// Every started piece copy of the project, by piece id then copy.
    func pieceProgress(for project: Project) throws -> [PieceProgress] {
        let id = project.id
        var descriptor = FetchDescriptor<PieceProgress>(predicate: #Predicate { $0.project?.id == id })
        descriptor.sortBy = [SortDescriptor(\.pieceID), SortDescriptor(\.copy)]
        return try context.fetch(descriptor)
    }

    /// The current piece copy's record; nil for a single-chart project.
    func currentProgress(of project: Project) throws -> PieceProgress? {
        guard let key = project.currentKey else { return nil }
        return try progress(key, of: project)
    }

    private func progress(_ key: PieceKey, of project: Project) throws -> PieceProgress? {
        let id = project.id, piece = key.piece, copy = key.copy
        var descriptor = FetchDescriptor<PieceProgress>(predicate: #Predicate { $0.project?.id == id && $0.pieceID == piece && $0.copy == copy })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Makes `key` the current piece: its own cursor comes back (review focus 2), and `chartID`
    /// follows it -- the chart's id for a chart piece, "" for a written one.
    func selectPiece(_ key: PieceKey, of project: Project, manifest: PatternManifest) async throws {
        guard let piece = manifest.pieces?.first(where: { $0.id == key.piece }), key.copy >= 1, key.copy <= piece.make else {
            throw ServiceError.pieceUnknown(key)
        }
        var chart: ManifestChart?
        if let id = piece.chart {
            guard let entry = manifest.charts.first(where: { $0.id == id }) else { throw ServiceError.chartUnavailable(id) }
            chart = entry
        }
        guard let docID = piece.chart ?? piece.rowsID else { throw ServiceError.pieceUnknown(key) }
        let record: PieceProgress
        if let existing = try progress(key, of: project) {
            record = existing
        } else {
            record = PieceProgress(pieceID: key.piece, copy: key.copy, docID: docID)
            context.insert(record)
            record.project = project
        }
        project.currentPiece = key.piece
        project.currentCopy = key.copy
        project.cursor = record.cursor
        if let chart {
            project.currentRowsID = nil
            project.chartID = chart.id
            project.chartVariant = chart.variant
            project.chartGaugeKey = chart.gaugeKey
        } else {
            project.currentRowsID = piece.rowsID
            project.chartID = ""
        }
        try save()
    }

    /// The current piece, loaded and ready to work.
    func work(for project: Project) async throws -> PieceWork {
        if let rowsID = project.currentRowsID {
            do { return .written(WrittenSequence(try await rows.document(id: rowsID))) }
            catch { throw ServiceError.chartUnavailable(rowsID) }
        }
        let chart = try await chart(for: project)
        return .chart(chart, try WorkSequence(chart: chart))
    }

    /// Done by hand, for an open-ended written piece, which never finishes on its last row.
    func finishPiece(_ project: Project) throws {
        guard let progress = try currentProgress(of: project) else { return }
        progress.finished = now()
        updateProjectFinished(project)
        try save()
        onProjectsChanged?()
    }

    func setAssemblyStep(_ index: Int, done: Bool, for project: Project) throws {
        var steps = Set(project.assemblyDone)
        if done { steps.insert(index) } else { steps.remove(index) }
        project.assemblyDone = steps.sorted()
        updateProjectFinished(project)
        try save()
        onProjectsChanged?()
    }

    /// A pieced project is finished when every piece copy is and every assembly step is ticked.
    /// Keeps the first finish time while it stays finished.
    func updateProjectFinished(_ project: Project) {
        let finishedPieces = ((try? pieceProgress(for: project)) ?? []).filter { $0.finished != nil }.count
        if finishedPieces >= project.piecesTotal && project.assemblyDone.count >= project.assemblyTotal {
            if project.finished == nil { project.finished = now() }
        } else {
            project.finished = nil
        }
    }

    /// The first piece copy, in manifest order, that is not finished and not the current one.
    func nextUnfinished(after project: Project, manifest: PatternManifest) throws -> PieceKey? {
        let byKey = Dictionary(try pieceProgress(for: project).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for piece in manifest.pieces ?? [] {
            for copy in 1...max(1, piece.make) {
                let key = PieceKey(piece: piece.id, copy: copy)
                if key != project.currentKey && byKey[key]?.finished == nil { return key }
            }
        }
        return nil
    }

    /// Every piece copy in manifest order, with its row line: "Row r of N" (or "Row r" when
    /// open-ended) once started; "N rows" or "Open-ended" before; "Done" when finished.
    func statuses(for project: Project, manifest: PatternManifest) async -> [PieceStatus] {
        let byKey = Dictionary(((try? pieceProgress(for: project)) ?? []).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var passes: [String: Int?] = [:]   // chart id → row count, nil when it cannot be read
        var written: [String: WrittenSequence?] = [:]
        var out: [PieceStatus] = []
        for piece in manifest.pieces ?? [] {
            for copy in 1...max(1, piece.make) {
                let key = PieceKey(piece: piece.id, copy: copy)
                let progress = byKey[key]
                let line: String
                if progress?.finished != nil {
                    line = "Done"
                } else if let id = piece.chart {
                    if passes[id] == nil {
                        passes[id] = .some(try? WorkSequence(chart: try await charts.chart(id: id)).passes.count)
                    }
                    if let n = passes[id] ?? nil {
                        line = progress.map { "Row \($0.cursorRow) of \(n)" } ?? Self.rowCount(n)
                    } else {
                        line = "Chart missing"
                    }
                } else if let id = piece.rowsID {
                    if written[id] == nil { written[id] = .some((try? await rows.document(id: id)).map(WrittenSequence.init)) }
                    if let seq = written[id] ?? nil {
                        if let progress {
                            let r = progress.cursorRow
                            line = seq.totalRows.map { "Row \(r) of \($0)" } ?? "Row \(r)"
                        } else {
                            line = seq.totalRows.map(Self.rowCount) ?? "Open-ended"
                        }
                    } else {
                        line = "Rows missing"
                    }
                } else {
                    line = "Chart missing"
                }
                out.append(PieceStatus(piece: piece, copy: copy, isWritten: piece.isWritten, line: line,
                                       finished: progress?.finished != nil, isCurrent: key == project.currentKey))
            }
        }
        return out
    }

    private static func rowCount(_ n: Int) -> String { n == 1 ? "1 row" : "\(n) rows" }

    /// "Front panel · Row 42 of 77 · 3 of 8 pieces"; no total for an open-ended piece
    /// (review focus 3); "Finished" once the whole project is.
    func progressLine(for project: Project, manifest: PatternManifest, work: PieceWork) throws -> String {
        if project.isFinished { return "Finished" }
        let title = manifest.pieces?.first(where: { $0.id == project.currentPiece })?.title ?? project.currentPiece ?? project.title
        let r = project.cursor.row
        let total: Int? = switch work {
        case .chart(_, let seq): seq.passes.count
        case .written(let seq): seq.totalRows
        }
        let rowPart = total.map { "Row \(r) of \($0)" } ?? "Row \(r)"
        let done = try pieceProgress(for: project).filter { $0.finished != nil }.count
        return "\(title) · \(rowPart) · \(done) of \(project.piecesTotal) pieces"
    }

    /// The current piece's percent (spec §6.5: never a project percent); nil when it is
    /// open-ended.
    func currentPercent(for project: Project, work: PieceWork) -> Double? {
        let finished = (try? currentProgress(of: project))?.finished != nil
        return ProjectPace.pieceSummary(key: project.currentKey ?? PieceKey(piece: "", copy: 1), cursor: project.cursor,
                                        finished: finished, model: work.model).percent
    }

    /// Progress schema 2. Throws when the event log cannot be read, like `exportDocument(for:)`.
    func exportPiecedDocument(for project: Project) throws -> ProjectProgressDocument {
        let id = project.id
        var descriptor = FetchDescriptor<ProgressEvent>(predicate: #Predicate { $0.project?.id == id })
        descriptor.sortBy = [SortDescriptor(\.t)]
        let events = try context.fetch(descriptor).compactMap { e in
            e.piece.map { PiecedEventRecord(t: e.t, piece: $0, copy: e.copy, row: e.row, run: e.run, stitch: e.stitch, kind: e.kind) }
        }
        let pieces = try pieceProgress(for: project).map {
            PieceProgressRecord(piece: $0.pieceID, copy: $0.copy, docID: $0.docID, cursor: $0.cursor, finished: $0.finished)
        }
        return ProjectProgressDocument(patternID: project.patternID, patternVersion: project.patternVersion, pieces: pieces,
                                       current: project.currentKey, assemblyDone: project.assemblyDone,
                                       started: project.started, finished: project.finished, events: events)
    }
}
