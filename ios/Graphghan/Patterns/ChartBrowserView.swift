import SwiftUI
import GraphghanCore

/// The whole chart at 1 pixel per cell, scaled without smoothing, with pinch zoom and row numbers.
struct ChartBrowserView: View {
    let title: String
    let highlightRow: Int?
    let load: @MainActor () async throws -> Chart
    @State private var chart: Chart?
    @State private var image: CGImage?
    /// Built once beside the image: deriving it per body evaluation walks every row of the chart.
    @State private var sequence: WorkSequence?
    @State private var scale: CGFloat = 4
    @State private var pinchBase: CGFloat = 4
    @State private var error: String?

    var body: some View {
        Group {
            if let chart, let image {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: CGFloat(chart.width) * scale, height: CGFloat(chart.height) * scale * chart.cellAspect)
                        rowNumbers(chart)
                        if let highlightRow, let y = gridRow(for: highlightRow) {
                            Rectangle().stroke(Color.accentColor, lineWidth: 2)
                                .frame(width: CGFloat(chart.width) * scale, height: scale * chart.cellAspect)
                                .offset(y: CGFloat(y) * scale * chart.cellAspect)
                        }
                    }
                    .padding(24)
                }
                .gesture(MagnifyGesture().onChanged { scale = min(40, max(1, pinchBase * $0.magnification)) }.onEnded { _ in pinchBase = scale })
            } else if let error {
                ContentUnavailableView("Couldn't load the chart", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let c = try await load()
                chart = c
                image = ChartImage.make(c)
                // A chart with no derivable working order still browses; it just has no row numbers.
                sequence = try? WorkSequence(chart: c)
            } catch { self.error = "Couldn't load this chart. Check your connection and try again." }
        }
    }

    private func gridRow(for row: Int) -> Int? {
        sequence?.pass(at: row)?.gridRow
    }

    @ViewBuilder private func rowNumbers(_ chart: Chart) -> some View {
        ForEach(Array(stride(from: 10, through: chart.height, by: 10)), id: \.self) { row in
            if let y = gridRow(for: row) {
                Text("\(row)")
                    .font(.system(size: 9, design: .monospaced))
                    .offset(x: -20, y: CGFloat(y) * scale * chart.cellAspect)
                Text("\(row)")
                    .font(.system(size: 9, design: .monospaced))
                    .offset(x: CGFloat(chart.width) * scale + 6, y: CGFloat(y) * scale * chart.cellAspect)
            }
        }
    }
}
