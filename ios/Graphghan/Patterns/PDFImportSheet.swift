import GraphghanCore
import SwiftUI

/// What the import sheet shows (phone import spec §5.2). Driven by `AppModel`, read by the sheet
/// and by tests.
@MainActor @Observable
final class PDFImportState {
    enum Stage: Equatable {
        case reading
        case found
        case failed(String)
    }
    var stage: Stage = .reading
    let fileName: String
    var reading: PDFImportReading? = nil
    var preview: UIImage? = nil
    init(fileName: String) { self.fileName = fileName }
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
                        Button("Add to library") { Task { await model.addImportedPDF() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
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
                    Button(state.stage == .found ? "Cancel" : "Done") { model.cancelPDFImport() }
                }
            }
        }
        .interactiveDismissDisabled(state.stage == .reading)
    }
}
