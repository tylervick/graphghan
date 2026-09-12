import SwiftUI
import GraphghanCore

/// The pattern detail body (spec §6.7), stateless: `PatternDetailView` loads and hands over.
struct PatternDetailContent: View {
    let manifest: PatternManifest
    /// The default chart once loaded; until then the manifest's plain palette shows.
    let chart: Chart?
    let preview: UIImage?
    let onStart: () -> Void
    let onBrowse: (ManifestChart) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewImage
            VStack(alignment: .leading, spacing: 4) {
                Text(manifest.title).font(Font.Heather.title).foregroundStyle(Color.ink)
                if !manifest.dedication.isEmpty { Text(manifest.dedication).font(Font.Heather.body).foregroundStyle(Color.ink2) }
                if !manifest.quote.isEmpty { Text("“\(manifest.quote)”").font(Font.Heather.quote).foregroundStyle(Color.ink).padding(.top, 4) }
            }
            specs
            colors
            if let chart, !chart.document.instructions.isEmpty { instructions(chart) }
            charts
            Button("Start project", action: onStart).buttonStyle(.primary).disabled(manifest.charts.isEmpty)
        }
        .padding(16)
    }

    private var previewImage: some View {
        Group {
            if let preview { Image(uiImage: preview).resizable().interpolation(.none).scaledToFill() }
            else { Color.panel.overlay(Image(systemName: "photo").foregroundStyle(Color.ink2)) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
    }

    private var specs: some View {
        let d = manifest.defaultChart
        return Card(padding: 14) {
            VStack(spacing: 8) {
                specRow("Chart", d.map { "\($0.width) × \($0.height) stitches × rows" } ?? "—")
                specRow("Finished", d.map { "\($0.size.width.formatted()) × \($0.size.height.formatted()) \($0.size.unit)" } ?? "—")
                specRow("Stitch", d?.stitch ?? "—")
                specRow("Version", manifest.version)
            }
        }
    }

    private func specRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(Font.Heather.body).foregroundStyle(Color.ink2)
            Spacer()
            Text(value).font(Font.Heather.body).foregroundStyle(Color.ink).monospacedDigit()
        }
    }

    private var colors: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Colors").font(Font.Heather.heading).foregroundStyle(Color.ink)
                if let chart {
                    ForEach(chart.document.palette, id: \.code) { entry in
                        paletteRow(code: entry.code, name: entry.name, hex: entry.hex, note: YarnLabel.text(for: entry))
                    }
                } else {
                    ForEach(manifest.palette, id: \.code) { swatch in
                        paletteRow(code: swatch.code, name: swatch.name, hex: swatch.hex, note: nil)
                    }
                }
            }
        }
    }

    private func paletteRow(code: String, name: String, hex: String, note: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Chip(text: code, hex: hex)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Font.Heather.label).foregroundStyle(Color.ink)
                if let note { Text(note).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
            }
        }
    }

    private func instructions(_ chart: Chart) -> some View {
        ForEach(chart.document.instructions, id: \.title) { section in
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title).font(Font.Heather.heading).foregroundStyle(Color.ink)
                    ForEach(section.text.split(separator: "\n").map(String.init), id: \.self) { line in
                        Text("• \(line)").font(Font.Heather.body).foregroundStyle(Color.ink)
                    }
                }
            }
        }
    }

    private var charts: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Published charts").font(Font.Heather.heading).foregroundStyle(Color.ink)
                ForEach(manifest.charts) { chart in
                    Button { onBrowse(chart) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(chart.variant) · \(chart.gaugeKey)").font(Font.Heather.label).foregroundStyle(Color.ink)
                                Text("\(chart.size.width.formatted()) × \(chart.size.height.formatted()) \(chart.size.unit) · \(chart.height) rows · \(chart.stitches.formatted()) stitches")
                                    .font(Font.Heather.caption).foregroundStyle(Color.ink2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.ink2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
