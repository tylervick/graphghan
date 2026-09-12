import SwiftUI
import GraphghanCore

struct PatternDetailView: View {
    @Environment(AppModel.self) private var model
    let entry: IndexEntry
    @State private var manifest: PatternManifest?
    @State private var chart: Chart?
    @State private var preview: UIImage?
    @State private var loadError: String?
    @State private var showStart = false
    @State private var browsing: ManifestChart?

    var body: some View {
        ScrollView {
            if let manifest {
                PatternDetailContent(manifest: manifest, chart: chart, preview: preview,
                                     onStart: { showStart = true }, onBrowse: { browsing = $0 })
            } else if let loadError {
                ContentUnavailableView("Couldn't load this pattern", systemImage: "wifi.slash", description: Text(loadError))
                    .padding(.top, 80)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Color.ground.weave().ignoresSafeArea())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $browsing) { chart in
            if let manifest {
                ChartBrowserView(title: "\(manifest.title) · \(chart.key)", highlightRow: nil) {
                    try await model.browseChart(manifest: manifest, chart: chart)
                }
            }
        }
        .sheet(isPresented: $showStart) {
            if let manifest { StartProjectSheet(manifest: manifest) }
        }
        .task {
            preview = await model.preview(for: entry.slug, sitePath: entry.preview)
            do {
                let m = try await model.manifest(for: entry.slug, path: entry.manifest)
                manifest = m
                if let c = m.defaultChart { chart = try? await model.browseChart(manifest: m, chart: c) }
            } catch { loadError = "Connect to the internet to open a pattern for the first time." }
        }
    }
}
