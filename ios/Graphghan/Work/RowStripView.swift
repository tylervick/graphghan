import SwiftUI
import GraphghanCore

/// The grid rows around the current pass, current row outlined in Heather, a marker on the edge
/// you start from, rows already worked dimmed. Two shapes: the compact strip in a Panel box, and
/// the full-bleed backdrop behind the Done field, where every row but the current one is softened
/// toward Ground so the glass controls have stitches to refract without the chart shouting.
struct RowStripView: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    var rowsAround = 2
    var backdrop = false

    var body: some View {
        if backdrop {
            canvas.accessibilityHidden(true)
        } else {
            canvas
                .frame(height: 56)
                .padding(8)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            guard let pass = sequence.pass(at: cursor.row), let y = pass.gridRow else { return }
            let workedGridRows = Set((1..<cursor.row).compactMap { sequence.pass(at: $0)?.gridRow })
            // The strip clamps its window to the chart so it stays full; the backdrop keeps the
            // current row pinned mid-field and leaves Ground where the chart runs out, so the
            // controls at the bottom never sit on the row being worked.
            let y0 = backdrop ? y - rowsAround : max(0, y - rowsAround)
            let y1 = backdrop ? y + rowsAround : min(chart.height - 1, y + rowsAround)
            guard y0 <= y1 else { return }  // belt and braces: never build an empty or reversed range
            let rows = y1 - y0 + 1
            let cw = size.width / CGFloat(chart.width)
            let ch = size.height / CGFloat(rows)
            for gy in y0...y1 where gy >= 0 && gy < chart.height {
                let rowRect = CGRect(x: 0, y: CGFloat(gy - y0) * ch, width: size.width, height: ch)
                for run in chart.runsByRow[gy] {
                    let rect = CGRect(x: CGFloat(run.x0) * cw, y: rowRect.minY, width: CGFloat(run.count) * cw, height: ch)
                    context.fill(Path(rect), with: .color(ChartImage.color(chart.palette[run.colorIndex].hex)))
                }
                if backdrop, gy != y {
                    context.fill(Path(rowRect), with: .color(.ground.opacity(0.6)))
                }
                if workedGridRows.contains(gy) {
                    context.fill(Path(rowRect), with: .color(Color.ink.opacity(backdrop ? 0.25 : 0.45)))
                }
            }
            let outline: CGFloat = backdrop ? 3 : 2
            let current = CGRect(x: outline / 2, y: CGFloat(y - y0) * ch + outline / 2, width: size.width - outline, height: ch - outline)
            context.stroke(Path(current), with: .color(.heather), lineWidth: outline)
            if let direction = pass.direction {
                let marker = direction == .ltr
                    ? CGRect(x: 0, y: CGFloat(y - y0) * ch, width: 8, height: ch)
                    : CGRect(x: size.width - 8, y: CGFloat(y - y0) * ch, width: 8, height: ch)
                context.fill(Path(marker), with: .color(.heather))
            }
        }
    }
}
