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
                Section("Chart") {
                    Picker("Chart", selection: $chartID) {
                        ForEach(manifest.charts) { c in
                            Text("\(c.variant) · \(c.gaugeKey): \(c.size.width.formatted()) × \(c.size.height.formatted()) \(c.size.unit), \(c.height) rows").tag(c.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
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
                    Button(starting ? "Starting…" : "Start") { start() }.disabled(chart == nil || starting)
                }
            }
        }
    }

    private func start() {
        guard let chart else { return }
        starting = true
        Task {
            do {
                try await model.startProject(manifest: manifest, chart: chart, title: title)
                dismiss()
            } catch {
                self.error = "Couldn't download the chart. Check your connection and try again."
                starting = false
            }
        }
    }
}
