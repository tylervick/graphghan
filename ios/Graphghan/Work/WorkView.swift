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
                Haptics.prepare()
            } catch {
                self.error = "This project's chart could not be read. Open the project and download it again."
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private func content(chart: Chart, sequence: WorkSequence, pass: Pass) -> some View {
        let finished = WorkEngine.isFinished(cursor, in: sequence)
        let current: Run? = cursor.run < pass.runs.count ? pass.runs[cursor.run] : nil
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                Button("Close") { dismiss() }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(pass.label) of \(sequence.passes.count)").font(.title2.bold())
                        .onLongPressGesture { showJump = true }
                        .accessibilityHint("Long press to jump to a row")
                        .accessibilityAction(named: "Jump to row") { showJump = true }
                    Text(sideText(pass)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Back") { perform(.back, sequence: sequence) }
                    .disabled(cursor == .start)
            }
            .padding(.horizontal)

            if let saveError = model.projects.lastError {
                HStack {
                    Text("Couldn't save your progress: \(saveError)")
                        .font(.footnote)
                    Spacer()
                    Button("Dismiss") { model.projects.lastError = nil }
                        .font(.footnote)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.yellow.opacity(0.25))
            }

            RowStripView(chart: chart, sequence: sequence, cursor: cursor).padding(.horizontal)

            RunChipsView(chart: chart, pass: pass, cursor: cursor) { run in
                perform(.jump(row: cursor.row, run: run), sequence: sequence)
            }

            if finished {
                VStack(spacing: 8) {
                    Text("Finished").font(.largeTitle.bold())
                    Text("Every row is done. Block it, weave in the ends, and take a picture.").multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if let current {
                currentRun(current, chart: chart, sequence: sequence, pass: pass)
                Spacer(minLength: 0)
                Button {
                    perform(.advance, sequence: sequence)
                } label: {
                    Text("Done").font(.largeTitle.bold()).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityLabel("Done with \(current.count) \(colorName(current.code, chart))")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
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
    private func currentRun(_ run: Run, chart: Chart, sequence: WorkSequence, pass: Pass) -> some View {
        let hex = chart.palette[chart.colorIndex(of: run.code) ?? 0].hex
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(run.count)").font(.system(size: 72, weight: .heavy, design: .rounded))
                Text(run.code).font(.system(size: 40, weight: .bold, design: .monospaced))
            }
            Text(colorName(run.code, chart)).font(.title3)
        }
        .foregroundStyle(ChartImage.isLight(hex) ? .black : .white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(ChartImage.color(hex), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        Text(nextText(chart: chart, sequence: sequence, pass: pass)).font(.headline).foregroundStyle(.secondary)
    }

    private func nextText(chart: Chart, sequence: WorkSequence, pass: Pass) -> String {
        if cursor.run + 1 < pass.runs.count {
            let next = pass.runs[cursor.run + 1]
            return "then \(next.count) \(colorName(next.code, chart))"
        }
        if let nextPass = sequence.pass(at: cursor.row + 1), let first = nextPass.runs.first {
            return "last run in this row · next row starts in \(colorName(first.code, chart))"
        }
        return "last run of the last row"
    }

    private func sideText(_ pass: Pass) -> String {
        let dir = pass.direction.map { $0 == .ltr ? "read left → right" : "read right → left" } ?? "read direction not specified"
        guard let side = pass.side else { return dir }
        return "\(side == .ws ? "Wrong side" : "Right side") · \(dir)"
    }

    private func colorName(_ code: String, _ chart: Chart) -> String {
        chart.palette[chart.colorIndex(of: code) ?? 0].name
    }

    private func perform(_ action: WorkAction, sequence: WorkSequence) {
        Haptics.prepare()  // warm the Taptic Engine again after a long pause
        guard let step = model.projects.apply(action, to: project, in: sequence) else { return }
        cursor = step.cursor
        if let feedback = WorkFeedbackRule.feedback(for: step, in: sequence) { Haptics.play(feedback) }
        // A failed save never blocks advancing (spec 6.6): model.projects.lastError is already set
        // for the banner above, and the cursor still moves.
    }
}
