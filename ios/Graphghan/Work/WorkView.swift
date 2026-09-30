import OSLog
import SwiftUI
import GraphghanCore

/// Full-screen working mode: the current run, the rows around it, one big Done target. A pieced
/// project's current piece may be a chart (the path unchanged from before pieces, spec §6.1) or
/// written rows (spec §6.4, no chart band, no strip).
struct WorkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var chart: Chart?
    @State private var sequence: WorkSequence?
    @State private var work: PieceWork?
    @State private var manifest: PatternManifest?
    @State private var pieceFinished = false
    @State private var nextTitle: String?
    @State private var cursor: Cursor = .start
    @State private var showJump = false
    @State private var error: String?

    var body: some View {
        Group {
            if case .written(let seq)? = work {
                writtenContent(seq)
            } else if let chart, let sequence, sequence.pass(at: cursor.row) != nil {
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
                if project.isPieced {
                    manifest = try await model.manifest(for: project.patternID, path: nil)
                }
                let loaded = try await model.projects.work(for: project)
                work = loaded
                guard !Task.isCancelled else { return }
                switch loaded {
                case .chart(let c, let s):
                    chart = c
                    sequence = s
                    Haptics.prepare()
                    if let (info, state) = await model.activityState(for: project) {
                        guard !Task.isCancelled else { return }
                        await model.liveActivity.start(projectID: project.id, info: info, state: state)
                    }
                case .written:
                    // A written piece's state is run-based, not row-based (#223): no Live Activity yet.
                    Haptics.prepare()
                }
                if project.isPieced { refreshFinished() }
            } catch {
                self.error = "This project's chart could not be read. Open the project and download it again."
            }
        }
        .onAppear { IdleTimer.hold() }
        .onDisappear {
            IdleTimer.release()
            Task {
                let final = sequence.flatMap { LiveActivityState.make(cursor: project.cursor, sequence: $0, perRepetition: project.tapPerRepetition) }
                await model.liveActivity.end(projectID: project.id, finalState: final)
            }
        }
        .onChange(of: project.cursorRow) { _, _ in cursor = project.cursor }
        .onChange(of: project.cursorRun) { _, _ in cursor = project.cursor }
        .onChange(of: project.cursorStitch) { _, _ in cursor = project.cursor }
        .statusBarHidden(true)
    }

    /// The current piece's title, as the project screen shows it: the manifest piece's title, or
    /// the project's own title for a single-chart project (spec §6.1).
    private var currentTitle: String {
        manifest?.pieces?.first { $0.id == project.currentPiece }?.title ?? project.title
    }

    @ViewBuilder
    private func content(chart: Chart, sequence: WorkSequence) -> some View {
        WorkScreen(chart: chart, sequence: sequence, cursor: cursor, step: project.step, perRepetition: project.tapPerRepetition,
                   onDone: { perform(.advance, sequence: sequence) },
                   onBack: { perform(.back, sequence: sequence) },
                   onClose: { dismiss() },
                   onJump: { showJump = true },
                   onJumpWithinRow: { run, stitch in perform(.jump(row: cursor.row, run: run, stitch: stitch), sequence: sequence) },
                   onSetStep: { step in try? model.projects.setCountStep(step, for: project) },
                   onSetPerRepetition: { on in try? model.projects.setTapPerRepetition(on, for: project) },
                   bandStyle: project.chartStyle,
                   onSetBandStyle: { style in try? model.projects.setBandStyle(style, for: project) })
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
        .overlay(alignment: .bottom) {
            // A pieced project's chart piece offers the next piece too, once every row is worked
            // (spec §6.5); a single-chart project has no next piece, so `nextTitle` stays nil.
            if project.isPieced, WorkEngine.isFinished(cursor, in: sequence), let nextTitle {
                Button("Next: \(nextTitle)") { Task { await goToNext() } }
                    .buttonStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 130)
            }
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

    @ViewBuilder
    private func writtenContent(_ seq: WrittenSequence) -> some View {
        WrittenWorkScreen(title: currentTitle, sequence: seq, cursor: cursor, finished: pieceFinished, next: nextTitle,
                          onDone: { performWritten(.advance) },
                          onBack: { performWritten(.back) },
                          onClose: { dismiss() },
                          onJump: { showJump = true },
                          onFinishPiece: { try? model.projects.finishPiece(project); refreshFinished() },
                          onNext: { Task { await goToNext() } })
            .gesture(
                DragGesture(minimumDistance: 60).onEnded { value in
                    if value.translation.width > 80, abs(value.translation.height) < 80 { performWritten(.back) }
                }
            )
            .sheet(isPresented: $showJump) {
                // An open piece has no last row to bound the sheet at, so it allows jumping ahead.
                JumpToRowSheet(rowCount: seq.totalRows ?? max(cursor.row + 50, 100), current: cursor.row) { row in performWritten(.jump(row: row)) }
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
        if project.isPieced { refreshFinished() }
        DispatchQueue.main.async { Self.signposter.endInterval("tap", tap) }
        // A failed save never blocks advancing (spec 6.6): model.projects.lastError is already set
        // for the banner above, and the cursor still moves.
    }

    /// A written piece's step: no runs, no haptics feedback rule to consult (spec §6.4).
    private func performWritten(_ action: WorkAction) {
        guard case .written(let seq)? = work else { return }
        Haptics.prepare()
        guard let step = model.projects.apply(action, to: project, work: .written(seq)) else { return }
        withAnimation(.spring(duration: 0.25)) { cursor = step.cursor }
        refreshFinished()
    }

    /// Whether the current piece is finished, and the next unfinished piece's title (spec §6.5);
    /// nil/false for a single-chart project, which has no pieces to look up.
    private func refreshFinished() {
        guard project.isPieced, let manifest else {
            pieceFinished = false
            nextTitle = nil
            return
        }
        pieceFinished = (try? model.projects.currentProgress(of: project))?.finished != nil
        if let key = try? model.projects.nextUnfinished(after: project, manifest: manifest),
           let piece = manifest.pieces?.first(where: { $0.id == key.piece }) {
            nextTitle = piece.make > 1 ? "\(piece.title) \(key.copy) of \(piece.make)" : piece.title
        } else {
            nextTitle = nil
        }
    }

    /// "Next: …" on a finished piece (chart or written): select it, reload its work, and land on
    /// its own cursor (review focus 2). Clears `chart`/`sequence` on a written next piece -- left
    /// stale, `onDisappear` would build the final Live Activity state from the piece just left.
    /// A Live Activity belongs to a chart piece (#223): moving onto a written piece ends it (no
    /// final state, since nothing about it is wrong); moving onto a chart piece starts or updates
    /// one exactly as the `.task` above does on first appearing.
    private func goToNext() async {
        guard let manifest, let key = try? model.projects.nextUnfinished(after: project, manifest: manifest) else { return }
        do {
            try await model.projects.selectPiece(key, of: project, manifest: manifest)
            let loaded = try await model.projects.work(for: project)
            work = loaded
            switch loaded {
            case .chart(let c, let s):
                chart = c
                sequence = s
                if let (info, state) = await model.activityState(for: project) {
                    await model.liveActivity.start(projectID: project.id, info: info, state: state)
                }
            case .written:
                chart = nil
                sequence = nil
                await model.liveActivity.end(projectID: project.id, finalState: nil)
            }
            cursor = project.cursor
            pieceFinished = false
            refreshFinished()
        } catch {
            self.error = "This project's chart could not be read. Open the project and download it again."
        }
    }
}
