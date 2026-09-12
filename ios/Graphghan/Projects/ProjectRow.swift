import SwiftUI
import GraphghanCore

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var sequence: WorkSequence?
    @State private var preview: UIImage?

    var body: some View {
        let summary = sequence.map { model.projects.summary(for: project, sequence: $0) }
        ProjectCardView(
            title: project.title,
            percent: summary?.percent,
            line: line(summary),
            estimate: sequence.flatMap { seq in
                project.isFinished ? nil : model.projects.estimatedFinish(for: project, sequence: seq).map { "Done around \($0.formatted(date: .abbreviated, time: .omitted))" }
            },
            lastWorked: project.lastWorked.map { "Last worked \($0.formatted(.relative(presentation: .named)))" },
            finished: project.isFinished,
            preview: preview)
        .task(id: project.chartID) { sequence = try? await model.projects.sequence(for: project) }
        .task { preview = await model.preview(for: project.patternID, sitePath: "patterns/\(project.patternID)/preview.png") }
    }

    private func line(_ summary: ProgressSummary?) -> String {
        guard let sequence, let summary else { return "" }
        return project.isFinished ? "Finished" : "Row \(project.cursor.row) of \(sequence.passes.count) · \(summary.percent.formatted())%"
    }
}
