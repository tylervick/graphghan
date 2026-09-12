import SwiftUI
import GraphghanCore

/// Full-screen working mode: the current run, the rows around it, one big Done target.
struct WorkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var chart: Chart?
    @State private var sequence: WorkSequence?
    @State private var cursor: Cursor = .start
    @State private var showJump = false
    @State private var error: String?

    var body: some View {
        Group {
            if let chart, let sequence, let pass = sequence.pass(at: cursor.row) {
                content(chart: chart, sequence: sequence, pass: pass)
            } else if let error {
                VStack(spacing: 16) {
                    Text(error)
                    Button("Close") { dismiss() }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .task {
            cursor = project.cursor
            do {
                chart = try await model.projects.chart(for: project)
                sequence = try await model.projects.sequence(for: project)
                guard !Task.isCancelled else { return }
                Haptics.prepare()
                if let (info, state) = await model.activityState(for: project) {
                    guard !Task.isCancelled else { return }
                    await model.liveActivity.start(projectID: project.id, info: info, state: state)
                }
            } catch {
                self.error = "This project's chart could not be read. Open the project and download it again."
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Task {
                let final = sequence.flatMap { LiveActivityState.make(cursor: project.cursor, sequence: $0) }
                await model.liveActivity.end(projectID: project.id, finalState: final)
            }
        }
        .onChange(of: project.cursorRow) { _, _ in cursor = project.cursor }
        .onChange(of: project.cursorRun) { _, _ in cursor = project.cursor }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private func content(chart: Chart, sequence: WorkSequence, pass: Pass) -> some View {
        WorkScreen(chart: chart, sequence: sequence, cursor: cursor,
                   onDone: { perform(.advance, sequence: sequence) },
                   onBack: { perform(.back, sequence: sequence) },
                   onClose: { dismiss() },
                   onJump: { showJump = true },
                   onSelectRun: { run in perform(.jump(row: cursor.row, run: run), sequence: sequence) })
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if let saveError = model.projects.lastError {
                    Banner(text: "Couldn't save your progress: \(saveError)", kind: .failure, action: .init(label: "Dismiss") { model.projects.lastError = nil })
                }
                if let hint = model.liveActivity.settingsHint {
                    Banner(text: hint, kind: .info, action: .init(label: "Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        model.liveActivity.dismissHint()
                    })
                }
            }
            .padding(.top, 60)
        }
        .gesture(
            DragGesture(minimumDistance: 60).onEnded { value in
                if value.translation.width > 80, abs(value.translation.height) < 80 { perform(.back, sequence: sequence) }
            }
        )
        .sheet(isPresented: $showJump) {
            JumpToRowSheet(rowCount: sequence.passes.count, current: cursor.row) { row in perform(.jump(row: row), sequence: sequence) }
        }
    }

    private func perform(_ action: WorkAction, sequence: WorkSequence) {
        Haptics.prepare()  // warm the Taptic Engine again after a long pause
        guard let step = model.projects.apply(action, to: project, in: sequence) else { return }
        withAnimation(.spring(duration: 0.25)) { cursor = step.cursor }
        if let feedback = WorkFeedbackRule.feedback(for: step, in: sequence) { Haptics.play(feedback) }
        // A failed save never blocks advancing (spec 6.6): model.projects.lastError is already set
        // for the banner above, and the cursor still moves.
    }
}
