import OSLog
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
            if let chart, let sequence, sequence.pass(at: cursor.row) != nil {
                content(chart: chart, sequence: sequence)
            } else if let error {
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundStyle(Color.ink)
                        .font(Font.Heather.body)
                    Button("Close") { dismiss() }
                        .buttonStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .background(Color.ground.weave().ignoresSafeArea())
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
        .onChange(of: project.cursorStitch) { _, _ in cursor = project.cursor }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private func content(chart: Chart, sequence: WorkSequence) -> some View {
        WorkScreen(chart: chart, sequence: sequence, cursor: cursor, step: project.step,
                   onDone: { perform(.advance, sequence: sequence) },
                   onBack: { perform(.back, sequence: sequence) },
                   onClose: { dismiss() },
                   onJump: { showJump = true },
                   onJumpWithinRow: { run, stitch in perform(.jump(row: cursor.row, run: run, stitch: stitch), sequence: sequence) },
                   onSetStep: { step in try? model.projects.setCountStep(step, for: project) })
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if let saveError = model.projects.lastError {
                    Banner(text: "Couldn't save your progress: \(saveError)", kind: .failure, action: .init(label: "Dismiss") { model.projects.lastError = nil })
                }
                if let hint = model.liveActivity.settingsHint {
                    Banner(text: hint, kind: .info, action: .init(label: "Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }, dismiss: { model.liveActivity.dismissHint() })
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

    private static let signposter = OSSignposter(subsystem: "com.tylervick.graphghan", category: "work")

    private func perform(_ action: WorkAction, sequence: WorkSequence) {
        // "tap" spans from the tap to the next free run-loop turn, "save" is the synchronous write:
        // the two intervals a performance audit reads first (#79).
        let tap = Self.signposter.beginInterval("tap")
        Haptics.prepare()  // warm the Taptic Engine again after a long pause
        let save = Self.signposter.beginInterval("save")
        let applied = model.projects.apply(action, to: project, in: sequence)
        Self.signposter.endInterval("save", save)
        guard let step = applied else { Self.signposter.endInterval("tap", tap); return }
        withAnimation(.spring(duration: 0.25)) { cursor = step.cursor }
        if let feedback = WorkFeedbackRule.feedback(for: step, in: sequence) { Haptics.play(feedback) }
        DispatchQueue.main.async { Self.signposter.endInterval("tap", tap) }
        // A failed save never blocks advancing (spec 6.6): model.projects.lastError is already set
        // for the banner above, and the cursor still moves.
    }
}
