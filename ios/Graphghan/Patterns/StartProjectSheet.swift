import SwiftUI
import GraphghanCore

struct StartProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let manifest: PatternManifest
    @State private var chartID: String
    @State private var title: String
    @State private var starting = false
    @State private var error: String?

    init(manifest: PatternManifest) {
        self.manifest = manifest
        _chartID = State(initialValue: manifest.defaultChart?.id ?? "")
        _title = State(initialValue: manifest.title)
    }

    private var chart: ManifestChart? { manifest.charts.first { $0.id == chartID } }

    var body: some View {
        NavigationStack {
            Form {
                if manifest.isPieced {
                    Section("Pieces") {
                        ForEach(manifest.pieces ?? []) { piece in
                            Text(piece.make > 1 ? "\(piece.title) × \(piece.make)" : piece.title)
                        }
                    }
                } else {
                    Section("Chart") {
                        Picker("Chart", selection: $chartID) {
                            ForEach(manifest.charts) { c in
                                Text("\(c.variant) · \(c.gaugeKey): \(c.sizeLabel.map { "\($0), " } ?? "")\(c.height) rows").tag(c.id)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                Section("Name") {
                    TextField("Project name", text: $title)
                }
                if let error { Section { Text(error).foregroundStyle(Color.brick) } }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ground.weave().ignoresSafeArea())
            .navigationTitle("Start project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(starting ? "Starting…" : "Start") { start() }.disabled((manifest.isPieced ? false : chart == nil) || starting)
                }
            }
        }
    }

    private func start() {
        starting = true
        Task {
            do {
                if manifest.isPieced {
                    try await model.startPiecedProject(manifest: manifest, title: title)
                } else {
                    guard let chart else { starting = false; return }
                    try await model.startProject(manifest: manifest, chart: chart, title: title)
                }
                dismiss()
            } catch {
                self.error = Self.startErrorText(pieced: manifest.isPieced)
                starting = false
            }
        }
    }

    /// A failed start's sentence: a pieced pattern reads its pieces rather than downloading a
    /// single chart, so a failure there is not "the chart" (#206 review). `nonisolated` -- it
    /// touches no actor-isolated state -- so a test can call it without hopping to the main actor.
    nonisolated static func startErrorText(pieced: Bool) -> String {
        pieced ? "Couldn't read this pattern's pieces." : "Couldn't download the chart. Check your connection and try again."
    }
}
