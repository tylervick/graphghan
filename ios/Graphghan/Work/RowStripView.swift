import SwiftUI
import GraphghanCore

/// The grid rows around the current pass, current row outlined, a marker on the edge you start from.
struct RowStripView: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    var rowsAround = 2

    var body: some View {
        Canvas { context, size in
            guard let pass = sequence.pass(at: cursor.row), let y = pass.gridRow else { return }
            let y0 = max(0, y - rowsAround)
            let y1 = min(chart.height - 1, y + rowsAround)
            guard y0 <= y1 else { return }  // belt and braces: never build an empty or reversed range
            let rows = y1 - y0 + 1
            let cw = size.width / CGFloat(chart.width)
            let ch = size.height / CGFloat(rows)
            for gy in y0...y1 {
                for run in chart.runsByRow[gy] {
                    let rect = CGRect(x: CGFloat(run.x0) * cw, y: CGFloat(gy - y0) * ch, width: CGFloat(run.count) * cw, height: ch)
                    context.fill(Path(rect), with: .color(ChartImage.color(chart.palette[run.colorIndex].hex)))
                }
                if gy != y {
                    context.fill(Path(CGRect(x: 0, y: CGFloat(gy - y0) * ch, width: size.width, height: ch)), with: .color(.black.opacity(0.45)))
                }
            }
            let current = CGRect(x: 1, y: CGFloat(y - y0) * ch + 1, width: size.width - 2, height: ch - 2)
            context.stroke(Path(current), with: .color(.heather), lineWidth: 2)
            if let direction = pass.direction {
                let marker = direction == .ltr
                    ? CGRect(x: 0, y: CGFloat(y - y0) * ch, width: 8, height: ch)
                    : CGRect(x: size.width - 8, y: CGFloat(y - y0) * ch, width: 8, height: ch)
                context.fill(Path(marker), with: .color(.heather))
            }
        }
        .frame(height: 56)
        .padding(8)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}
