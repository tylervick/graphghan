import SwiftUI
import GraphghanCore

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var sequence: WorkSequence?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PreviewImage(slug: project.patternID, sitePath: "patterns/\(project.patternID)/preview.png")
                .frame(width: 96, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title).font(.headline)
                if let sequence {
                    let summary = model.projects.summary(for: project, sequence: sequence)
                    ProgressView(value: summary.percent, total: 100)
                    Text(project.isFinished ? "Finished" : "Row \(project.cursor.row) of \(sequence.passes.count) · \(summary.percent.formatted())%")
                        .font(.caption).foregroundStyle(.secondary)
                    if let finish = model.projects.estimatedFinish(for: project, sequence: sequence), !project.isFinished {
                        Text("Done around \(finish.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let last = project.lastWorked {
                    Text("Last worked \(last.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: project.chartID) { sequence = try? await model.projects.sequence(for: project) }
    }
}
