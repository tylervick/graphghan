import SwiftUI
import GraphghanCore

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var sequence: WorkSequence?
    @State private var preview: UIImage?
    @State private var summary: ProgressSummary?
    @State private var historyUnavailable = false
    /// A pieced project's own line and percent (spec 2026-09-25 §6.5), from its current piece --
    /// never the event log's summary, which is per chart and a written piece has none of.
    @State private var pieceLine: String?
    @State private var piecePercent: Double?
    /// The manifest, the current piece or its line could not be read.
    @State private var pieceUnavailable = false

    var body: some View {
        ProjectCardView(
            title: project.title,
            percent: project.isPieced ? piecePercent : summary?.percent,
            line: project.isPieced ? Self.cardLine(pieceLine, unavailable: pieceUnavailable) : line(summary),
            estimate: project.isPieced ? nil : summary.flatMap { s in
                project.isFinished ? nil : model.projects.estimatedFinish(from: s).map { "Done around \($0.formatted(date: .abbreviated, time: .omitted))" }
            },
            lastWorked: project.lastWorked.map { "Last worked \($0.formatted(.relative(presentation: .named)))" },
            finished: project.isFinished,
            preview: preview)
        .task(id: project.chartID) {
            guard !project.isPieced else { return }
            sequence = try? await model.projects.sequence(for: project)
        }
        // The summary walks every event; recompute it when the project changes outside the Work
        // screen, never on each tap behind the cover (see ProjectSummaryKey).
        .task(id: SummaryRefresh(key: ProjectSummaryKey.make(for: project, working: model.workingProject), chartID: sequence == nil ? nil : project.chartID)) {
            guard !project.isPieced, let sequence, ProjectSummaryKey.make(for: project, working: model.workingProject) != nil || summary == nil else { return }
            do {
                summary = try model.projects.summary(for: project, sequence: sequence)
                historyUnavailable = false
            } catch {
                summary = nil
                historyUnavailable = true
            }
        }
        // A pieced project's line and percent come from its current piece, not the event log --
        // no estimate either (Pace is per chart).
        .task(id: PieceRefresh(key: ProjectSummaryKey.make(for: project, working: model.workingProject), piece: project.currentPiece, copy: project.currentCopy)) {
            guard project.isPieced, ProjectSummaryKey.make(for: project, working: model.workingProject) != nil || pieceLine == nil else { return }
            guard let manifest = try? await model.manifest(for: project.patternID, path: nil),
                  let work = try? await model.projects.work(for: project) else {
                pieceLine = nil
                piecePercent = nil
                pieceUnavailable = true
                return
            }
            pieceLine = try? model.projects.progressLine(for: project, manifest: manifest, work: work)
            piecePercent = model.projects.currentPercent(for: project, work: work)
            pieceUnavailable = pieceLine == nil
        }
        .task { preview = await model.preview(for: project.patternID, sitePath: "patterns/\(project.patternID)/preview.png") }
    }

    private struct SummaryRefresh: Hashable { let key: ProjectSummaryKey?; let chartID: String? }
    private struct PieceRefresh: Hashable { let key: ProjectSummaryKey?; let piece: String?; let copy: Int }

    /// A pieced project's card line: its progress line, "History couldn't be read" when that
    /// failed (the single-chart row's sentence), or empty while it loads.
    static func cardLine(_ line: String?, unavailable: Bool) -> String {
        unavailable ? "History couldn't be read" : line ?? ""
    }

    private func line(_ summary: ProgressSummary?) -> String {
        if historyUnavailable { return "History couldn't be read" }
        guard let sequence, let summary else { return "" }
        return project.isFinished ? "Finished" : "Row \(project.cursor.row) of \(sequence.passes.count) · \(summary.percent.formatted())%"
    }
}
