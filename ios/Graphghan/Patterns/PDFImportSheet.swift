import GraphghanCore
import ProseReaderKit
import SwiftUI

/// What the import sheet shows (phone import spec §5.2). Driven by `AppModel`, read by the sheet
/// and by tests.
@MainActor @Observable
final class PDFImportState {
    enum Stage: Equatable {
        case reading
        case readingRows(done: Int, of: Int, secondsElapsed: Int)
        case found
        case saving
        case failed(String)
    }
    var stage: Stage = .reading
    let fileName: String
    var reading: PDFImportReading? = nil
    var preview: UIImage? = nil
    /// The read in flight, so Cancel can stop the model mid-row.
    var task: Task<Void, Never>? = nil
    enum CheckStage: Equatable {
        case none
        case running(done: Int, of: Int)
        case done(ImportRecord)
    }
    /// The row check under "Chart found" (spec §5.2), and its task so Skip and Cancel can stop it.
    var check: CheckStage = .none
    var checkTask: Task<Void, Never>? = nil
    /// What the app's scene was doing when the check started, for the probe's report (#176).
    var appStateAtCheck: String = ""
    /// And what the iPhone's power situation was, which nobody thought to note on the first
    /// four runs and which may be the whole of it.
    var powerAtCheck: String = ""
    var onBatteryAtCheck = false
    /// The three probes' answers, once "Why?" has asked them, and whether they are being asked.
    var probe: ModelProbe? = nil
    var probing = false
    /// The measurement of what the phone will take (#176 round two), which takes minutes, so it
    /// is asked for by a second tap and reports what it is doing while it runs.
    var limits: LimitReport? = nil
    var measuring = false
    var measuringStep = ""
    /// The measurement in flight, so Cancel and "Add to library" stop it: it asks the model for
    /// minutes and holds the screen awake, neither of which may outlive the sheet.
    var measureTask: Task<Void, Never>? = nil
    init(fileName: String) { self.fileName = fileName }

    /// Cancel while the model reads or before the chart is added; Done once it failed.
    var isCancellable: Bool {
        switch stage {
        case .found, .readingRows: return true
        case .reading, .saving, .failed: return false
        }
    }
}

struct PDFImportSheet: View {
    @Environment(AppModel.self) private var model
    let state: PDFImportState

    var body: some View {
        NavigationStack {
            Group {
                switch state.stage {
                case .reading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the pages…").font(Font.Heather.body).foregroundStyle(Color.ink2)
                    }
                case .readingRows(let done, let of, let seconds):
                    VStack(spacing: 12) {
                        Text("This pattern has no chart the app can read, so it is reading the \(of) written rows. About \(PDFImportSheet.minutes(for: of)) minutes.")
                            .font(Font.Heather.body).foregroundStyle(Color.ink2).multilineTextAlignment(.center)
                        ProgressView(value: Double(done), total: Double(max(of, 1))).tint(Color.ink)
                        Text("Row \(done) of \(of), \(seconds) s").font(Font.Heather.caption).foregroundStyle(Color.ink2).monospacedDigit()
                    }
                    .padding()
                case .found:
                    VStack(spacing: 16) {
                        if let preview = state.preview {
                            Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if let r = state.reading {
                            Text(r.bundle.manifest.title).font(Font.Heather.heading).foregroundStyle(Color.ink)
                            Text("\(r.width) × \(r.height) stitches, \(r.colours) colours").font(Font.Heather.body).foregroundStyle(Color.ink2)
                            if let leftOut = r.contents?.sentence {
                                Text(leftOut).font(Font.Heather.caption).foregroundStyle(Color.ink2).multilineTextAlignment(.center)
                            }
                        }
                        switch state.check {
                        case .none:
                            EmptyView()
                        case .running(let done, let of):
                            VStack(spacing: 6) {
                                Text("Checking written row \(done) of \(of)…").font(Font.Heather.caption).foregroundStyle(Color.ink2).monospacedDigit()
                                ProgressView(value: Double(done), total: Double(max(of, 1))).tint(Color.ink)
                                Button("Skip the check") { model.skipPDFCheck() }.font(Font.Heather.caption)
                            }
                        case .done(let record):
                            VStack(spacing: 8) {
                                // Nothing to say for a chart with no written rows; agreement only for a finished check.
                                if let sentence = record.sentence ?? (record.check == .finished ? "Written rows agree with the chart." : nil) {
                                    if record.problem == nil {
                                        Text(sentence).font(Font.Heather.caption).foregroundStyle(Color.ink2).multilineTextAlignment(.center)
                                    } else {
                                        // Anything that went wrong has to leave the phone: this
                                        // is the sentence a maker sends on, and it was the one
                                        // thing on the sheet that could not be copied (#176).
                                        report(sentence)
                                    }
                                }
                                if record.problem == ImportRecord.modelBusy {
                                    if state.onBatteryAtCheck {
                                        Text("This iPhone was on battery, which may be why; plugging in may help.")
                                            .font(Font.Heather.caption).foregroundStyle(Color.ink2)
                                            .multilineTextAlignment(.center)
                                    }
                                    whyTheModelIsBusy
                                }
                            }
                        }
                        Button("Add to library") {
                            state.stage = .saving  // set before the save runs: no second tap, no cancel underneath it
                            Task { await model.addImportedPDF() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                case .saving:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Adding to library…").font(Font.Heather.body).foregroundStyle(Color.ink2)
                    }
                case .failed(let sentence):
                    VStack(spacing: 12) {
                        Image(systemName: "doc.questionmark").font(Font.Heather.rowNumber).foregroundStyle(Color.ink2)
                        Text(sentence).font(Font.Heather.body).foregroundStyle(Color.ink).multilineTextAlignment(.center)
                        if sentence == ImportRecord.modelBusySentence { whyTheModelIsBusy }
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ground.weave().ignoresSafeArea())
            .navigationTitle(state.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if state.stage != .saving {
                        Button(state.isCancellable ? "Cancel" : "Done") { model.cancelPDFImport() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(state.stage == .reading || state.stage == .saving)
    }

    /// "Why?" beside a busy model (#176). The simulator has no model, so the three probes -- a
    /// one-line prompt with no instructions, the same prompt under the row instructions, a
    /// structured answer -- can only be asked on the phone that refused the check, and this is
    /// where they are asked. The report says which of the three is the first to be refused.
    @ViewBuilder private var whyTheModelIsBusy: some View {
        if let probe = state.probe {
            report(probe.text)
            measureTheLimit
        } else if state.probing {
            ProgressView()
        } else {
            Button("Why?") { Task { await model.runModelProbe() } }.font(Font.Heather.caption)
        }
    }

    /// When the three probes all answer, the refusal is not in any one request and the next
    /// question is how many of them the phone will take (#176). That measurement asks the model
    /// thirty times and waits out a refusal, so it runs on a second tap, not with the first.
    @ViewBuilder private var measureTheLimit: some View {
        if let limits = state.limits {
            report(limits.text)
        } else if state.measuring {
            VStack(spacing: 6) {
                ProgressView()
                Text(state.measuringStep).font(Font.Heather.caption).foregroundStyle(Color.ink2)
            }
        } else if state.probe?.steps.allSatisfy(\.ok) == true {
            Button("Measure the limit (a few minutes)") { model.startModelLimitMeasurement() }
                .font(Font.Heather.caption)
        }
    }

    /// A report the maker has to get off the phone and into an issue. It scrolls, because these
    /// run to a dozen lines and the sheet would otherwise cut the last ones off -- which is
    /// exactly what happened to the run that mattered (#176) -- and it copies and shares, because
    /// reading a token count off a screen and typing it out again loses the digits that matter.
    @ViewBuilder private func report(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(text)
                    .font(Font.Heather.caption).foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.leading).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            HStack(spacing: 16) {
                Button("Copy") { UIPasteboard.general.string = text }
                ShareLink(item: text) { Text("Share") }
            }
            .font(Font.Heather.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The estimate the sheet prints: rows at the measured pace, rounded up, never under a minute.
    static func minutes(for rows: Int) -> Int {
        max(1, Int((Double(rows) * PDFImporter.secondsPerRow / 60).rounded(.up)))
    }
}
