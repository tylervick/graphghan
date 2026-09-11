import SwiftUI
import GraphghanCore

struct PatternDetailView: View {
    @Environment(AppModel.self) private var model
    let entry: IndexEntry
    @State private var manifest: PatternManifest?
    @State private var loadError: String?
    @State private var showStart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PreviewImage(slug: entry.slug, sitePath: entry.preview)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if let manifest {
                    if !manifest.quote.isEmpty { Text("“\(manifest.quote)”").font(.title3.italic()) }
                    specs(manifest)
                    palette(manifest)
                    charts(manifest)
                    instructions
                } else if let loadError {
                    ContentUnavailableView("Couldn't load this pattern", systemImage: "wifi.slash", description: Text(loadError))
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let manifest {
                Button("Start project") { showStart = true }
                    .disabled(manifest.charts.isEmpty)
            }
        }
        .sheet(isPresented: $showStart) {
            if let manifest { StartProjectSheet(manifest: manifest) }
        }
        .task {
            do { manifest = try await model.manifest(for: entry.slug, path: entry.manifest) }
            catch { loadError = "Connect to the internet to open a pattern for the first time." }
        }
    }

    @ViewBuilder private func specs(_ m: PatternManifest) -> some View {
        let d = m.defaultChart
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow { Text("Chart").foregroundStyle(.secondary); Text(d.map { "\($0.width) × \($0.height) stitches × rows" } ?? "—") }
            GridRow { Text("Finished").foregroundStyle(.secondary); Text(d.map { "\($0.size.width.formatted()) × \($0.size.height.formatted()) \($0.size.unit)" } ?? "—") }
            GridRow { Text("Stitch").foregroundStyle(.secondary); Text(d?.stitch ?? entry.stitch) }
            GridRow { Text("Version").foregroundStyle(.secondary); Text(m.version) }
            if !m.dedication.isEmpty { GridRow { Text("For").foregroundStyle(.secondary); Text(m.dedication) } }
        }
        .font(.subheadline)
    }

    @ViewBuilder private func palette(_ m: PatternManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colors").font(.headline)
            ForEach(m.palette, id: \.code) { swatch in
                HStack {
                    RoundedRectangle(cornerRadius: 4).fill(ChartImage.color(swatch.hex)).frame(width: 28, height: 20)
                    Text(swatch.code).font(.system(.body, design: .monospaced)).bold()
                    Text(swatch.name)
                }
            }
        }
    }

    @ViewBuilder private func charts(_ m: PatternManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Published charts").font(.headline)
            ForEach(m.charts) { chart in
                NavigationLink {
                    ChartBrowserView(title: "\(m.title) · \(chart.key)", highlightRow: nil) {
                        try await model.browseChart(manifest: m, chart: chart)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(chart.variant) · \(chart.gaugeKey)").bold()
                            Text("\(chart.size.width.formatted()) × \(chart.size.height.formatted()) \(chart.size.unit) · \(chart.height) rows · \(chart.stitches.formatted()) stitches")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var instructions: some View {
        if let m = manifest, let chart = m.defaultChart {
            InstructionsView(slug: m.id, chart: chart)
        }
    }
}

/// Instruction sections live in the chart file, so they load on demand.
private struct InstructionsView: View {
    @Environment(AppModel.self) private var model
    let slug: String
    let chart: ManifestChart
    @State private var sections: [ChartDocument.Instruction] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sections, id: \.title) { section in
                Text(section.title).font(.headline)
                ForEach(section.text.split(separator: "\n").map(String.init), id: \.self) { line in
                    Text("• \(line)").font(.subheadline)
                }
            }
        }
        .task {
            if let manifest = model.cachedManifest(for: slug), let chart = try? await model.browseChart(manifest: manifest, chart: chart) {
                sections = chart.document.instructions
            }
        }
    }
}
