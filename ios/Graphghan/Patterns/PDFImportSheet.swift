import GraphghanCore
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
                            Text(record.sentence ?? "Written rows agree with the chart.")
                                .font(Font.Heather.caption).foregroundStyle(Color.ink2).multilineTextAlignment(.center)
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

    /// The estimate the sheet prints: rows at the measured pace, rounded up, never under a minute.
    static func minutes(for rows: Int) -> Int {
        max(1, Int((Double(rows) * PDFImporter.secondsPerRow / 60).rounded(.up)))
    }
}
