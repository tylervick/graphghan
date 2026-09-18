import SwiftUI
import GraphghanCore

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var sequence: WorkSequence?
    @State private var preview: UIImage?
    @State private var summary: ProgressSummary?
    @State private var historyUnavailable = false

    var body: some View {
        ProjectCardView(
            title: project.title,
            percent: summary?.percent,
            line: line(summary),
            estimate: summary.flatMap { s in
                project.isFinished ? nil : model.projects.estimatedFinish(from: s).map { "Done around \($0.formatted(date: .abbreviated, time: .omitted))" }
            },
            lastWorked: project.lastWorked.map { "Last worked \($0.formatted(.relative(presentation: .named)))" },
            finished: project.isFinished,
            preview: preview)
        .task(id: project.chartID) { sequence = try? await model.projects.sequence(for: project) }
        // The summary walks every event; recompute it when the project changes outside the Work
        // screen, never on each tap behind the cover (see ProjectSummaryKey).
        .task(id: SummaryRefresh(key: ProjectSummaryKey.make(for: project, working: model.workingProject), chartID: sequence == nil ? nil : project.chartID)) {
            guard let sequence, ProjectSummaryKey.make(for: project, working: model.workingProject) != nil || summary == nil else { return }
            do {
                summary = try model.projects.summary(for: project, sequence: sequence)
                historyUnavailable = false
            } catch {
                summary = nil
                historyUnavailable = true
            }
        }
        .task { preview = await model.preview(for: project.patternID, sitePath: "patterns/\(project.patternID)/preview.png") }
    }

    private struct SummaryRefresh: Hashable { let key: ProjectSummaryKey?; let chartID: String? }

    private func line(_ summary: ProgressSummary?) -> String {
        if historyUnavailable { return "History couldn't be read" }
        guard let sequence, let summary else { return "" }
        return project.isFinished ? "Finished" : "Row \(project.cursor.row) of \(sequence.passes.count) · \(summary.percent.formatted())%"
    }
}
