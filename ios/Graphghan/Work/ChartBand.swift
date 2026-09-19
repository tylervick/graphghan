import SwiftUI
import GraphghanCore

/// The chart at stitch scale (spec §5.3): the current row tall and ringed, two rows above faint,
/// the rows below at full strength as the ruler; or the whole chart at true aspect. Drawn with
/// `Canvas` and redrawn only when the cursor or size changes. The band is hidden from VoiceOver;
/// the panel is the spoken path.
struct ChartBand: View {
    enum Mode: Equatable { case band, whole }

    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    let segmentLabel: String?
    let mode: Mode
    let onAdvance: () -> Void
    let onJump: (_ run: Int, _ stitch: Int) -> Void
    let onToggleMode: () -> Void

    @State private var drag: CGFloat = 0
    @State private var dragBase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let pass = sequence.pass(at: cursor.row)
            let layout = pass.flatMap { p in
                cursor.run <= p.runs.count
                    ? BandLayout(width: geo.size.width, height: geo.size.height, chart: chart, pass: p, cursor: cursor, segmentLabel: segmentLabel)
                    : nil
            }
            Canvas(rendersAsynchronously: false) { context, size in
                if mode == .whole || layout == nil {
                    drawWhole(context: &context, size: size)
                } else if let layout, let pass {
                    drawBand(context: &context, layout: layout, pass: pass, size: size)
                }
            }
            .contentShape(Rectangle())
            // In the whole-chart view a tap returns to the band (spec §5.3); only the band itself advances.
            .onTapGesture { mode == .whole ? onToggleMode() : onAdvance() }
            .simultaneousGesture(longPressJump(layout: layout, pass: pass))
            // High priority, not simultaneous: on the band, a rightward scrub is the band's own
            // scroll, not the screen-wide back swipe `WorkView` attaches around this view (spec
            // §5.4). A tap still reaches `onTapGesture` above -- this drag needs 12pt of travel
            // to begin -- and the long-press-to-jump gesture above is unaffected.
            .highPriorityGesture(DragGesture(minimumDistance: 12).onChanged { value in
                let raw = dragBase + value.translation.width
                drag = layout.map { Self.clampedDrag(raw, offsetX: $0.offsetX, maxOffset: maxOffset($0)) } ?? raw
            }.onEnded { _ in
                dragBase = layout.map { Self.clampedDrag(drag, offsetX: $0.offsetX, maxOffset: maxOffset($0)) } ?? drag
            })
            .simultaneousGesture(MagnifyGesture().onEnded { value in
                if (mode == .band && value.magnification < 0.8) || (mode == .whole && value.magnification > 1.2) { onToggleMode() }
            })
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
        .onChange(of: cursor) { _, _ in
            // The band scrolls on drag and snaps back to the rule on the next step, not on release.
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { drag = 0; dragBase = 0 }
        }
        .onChange(of: mode) { _, _ in drag = 0; dragBase = 0 }
        .accessibilityHidden(true)
    }

    /// How far the content can scroll before its far edge would come into view.
    private func maxOffset(_ layout: BandLayout) -> CGFloat {
        max(0, CGFloat(chart.width) * BandLayout.cell - layout.width)
    }

    /// `drag`, clamped so `offsetX - drag` (what drawing and hit-testing actually use) always
    /// lands inside `[0, maxOffset]` -- applied as the live value changes, not just when drawn, so
    /// slack never compounds across a release into the next drag.
    static func clampedDrag(_ drag: CGFloat, offsetX: CGFloat, maxOffset: CGFloat) -> CGFloat {
        min(max(drag, offsetX - maxOffset), offsetX)
    }

    /// The drag offset, the same value drawing and hit-testing both read.
    private func effectiveOffset(_ layout: BandLayout) -> CGFloat {
        layout.offsetX - drag
    }

    private func longPressJump(layout: BandLayout?, pass: Pass?) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5).sequenced(before: DragGesture(minimumDistance: 0)).onEnded { value in
            guard case .second(true, let drag?) = value, let layout, let pass, mode == .band else { return }
            let location = drag.location
            let x = layout.cellAt(x: location.x + effectiveOffset(layout) - layout.offsetX)
            guard let i = pass.runs.firstIndex(where: { r in r.x0.map { $0 <= x && x < $0 + r.count } ?? false }) else { return }
            let run = pass.runs[i]
            let ltr = pass.direction != .rtl
            let stitch = ltr ? x - run.x0! : run.x0! + run.count - 1 - x
            onJump(i, stitch)
        }
    }

    private func fill(_ code: Int) -> Color { ChartImage.color(chart.palette[code].hex) }

    private func drawRow(gridRow: Int, top: CGFloat, height: CGFloat, opacity: Double, context: inout GraphicsContext, offset: CGFloat) {
        guard gridRow >= 0, gridRow < chart.height else { return }
        let cell = BandLayout.cell
        for run in chart.runsByRow[gridRow] {
            let rect = CGRect(x: CGFloat(run.x0) * cell - offset, y: top, width: CGFloat(run.count) * cell, height: height)
            context.fill(Path(rect), with: .color(fill(run.colorIndex).opacity(opacity)))
        }
        // cell hairlines, then the row's bottom hairline
        for x in 0...chart.width {
            let px = CGFloat(x) * cell - offset
            context.fill(Path(CGRect(x: px - 0.25, y: top, width: 0.5, height: height)), with: .color(Color.ink.opacity(0.10 * opacity)))
        }
        context.fill(Path(CGRect(x: -offset, y: top + height - 0.25, width: CGFloat(chart.width) * cell, height: 0.5)), with: .color(Color.ink.opacity(0.15 * opacity)))
    }

    private func drawBand(context: inout GraphicsContext, layout: BandLayout, pass: Pass, size: CGSize) {
        guard let y = pass.gridRow else { return }
        let offset = effectiveOffset(layout)
        let cell = BandLayout.cell
        // Bottom-up charts sequence rows with decreasing grid row per pass, so the next pass's grid
        // row sits below the current one; that sign carries to every k so a `start: top` chart (whose
        // next pass has the larger grid row) draws the right way up too.
        let sign = (sequence.pass(at: cursor.row + 1)?.gridRow).map { $0 < y ? -1 : 1 } ?? -1
        // rows: the two above faint, the current, then the rows below
        for k in -BandLayout.rowsAbove...layout.rowsBelow {
            let gridRow = y - k * sign
            drawRow(gridRow: gridRow, top: layout.rowTop(k), height: layout.rowHeight(k), opacity: layout.rowOpacity(k), context: &context, offset: offset)
        }
        // The current row past the run is faint: cover it with Ground at 70%. Inside the run the
        // ring says what is left (#74): the counted stitches sit outside it at full colour, and
        // nothing is overlaid on the remainder, because on Cream a 70% Ground wash is invisible.
        let top = layout.rowTop(0)
        if let ring = layout.ring, cursor.run < pass.runs.count {
            let ltr = pass.direction != .rtl
            let restOfRow = ltr
                ? CGRect(x: ring.maxX - offset, y: top, width: CGFloat(chart.width) * cell - ring.maxX, height: ring.height)
                : CGRect(x: -offset, y: top, width: ring.minX, height: ring.height)
            context.fill(Path(restOfRow), with: .color(Color.ground.opacity(0.7)))
            // the ring, around the remainder
            let ringRect = CGRect(x: ring.minX - offset + 1.5, y: top + 1.5, width: ring.width - 3, height: ring.height - 3)
            context.stroke(Path(ringRect), with: .color(.heather), lineWidth: 3)
            // ruler, with the hook's own tick where the count stands (#74)
            // The ruler sits in its own strip directly under the current row (spec §5.3, #72). Its
            // labels are chart annotations at a fixed size: scaled with Dynamic Type they overflow
            // the strip and vanish under the next row.
            let base = layout.rulerTop
            let hook = layout.ticks.isEmpty ? nil : layout.hook
            for tick in layout.ticks {
                context.fill(Path(CGRect(x: tick.x - offset - 0.5, y: base, width: 1, height: 6)), with: .color(.ink2))
                let underHook = hook.map { abs($0.x - tick.x) < 0.5 } ?? false
                if tick.label > 0, !underHook {
                    context.draw(Text("\(tick.label)").font(Font.Heather.annotation).foregroundStyle(Color.ink2), at: CGPoint(x: tick.x - offset, y: base + 14))
                }
            }
            if let hook {
                context.fill(Path(CGRect(x: hook.x - offset - 1, y: base - 4, width: 2, height: 10)), with: .color(.heather))
                context.draw(Text("\(hook.stitch)").font(Font.Heather.annotation.bold()).foregroundStyle(Color.heather), at: CGPoint(x: hook.x - offset, y: base + 14))
            }
        } else if let bx = layout.boundaryX {
            // the whole row is worked: mark its end and point at the next row's first stitch
            let ltr = pass.direction != .rtl
            context.fill(Path(CGRect(x: bx - offset - (ltr ? 3 : 0), y: top - 8, width: 3, height: layout.rowHeight(0) + 8)), with: .color(.heather))
            var arc = Path()
            arc.move(to: CGPoint(x: bx - offset, y: top - 8))
            arc.addQuadCurve(to: CGPoint(x: bx - offset + (ltr ? -80 : 80), y: top - 8), control: CGPoint(x: bx - offset + (ltr ? -40 : 40), y: top - 22))
            context.stroke(arc, with: .color(.heather), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        }
        // bracket above the current row
        if let b = layout.bracket {
            var path = Path()
            path.move(to: CGPoint(x: b.x0 - offset + 1, y: top - 4))
            path.addLine(to: CGPoint(x: b.x0 - offset + 1, y: top - 10))
            path.addLine(to: CGPoint(x: b.x1 - offset - 1, y: top - 10))
            path.addLine(to: CGPoint(x: b.x1 - offset - 1, y: top - 4))
            context.stroke(path, with: .color(.heather), lineWidth: 2)
            let lx = min(max((b.x0 + b.x1) / 2 - offset, 60), size.width - 60)
            context.draw(Text(b.label).font(Font.Heather.caption).foregroundStyle(Color.heather), at: CGPoint(x: lx, y: top - 19))
        }
    }

    /// The whole chart at true aspect: worked rows solid, the current row a Heather line, rows ahead faint (decision 1).
    private func drawWhole(context: inout GraphicsContext, size: CGSize) {
        let rect = BandLayout.wholeChartRect(chart: chart, in: size)
        let cw = rect.width / CGFloat(chart.width)
        let ch = rect.height / CGFloat(chart.height)
        let currentGridRow = sequence.pass(at: cursor.row)?.gridRow
        let worked = Set((1..<cursor.row).compactMap { sequence.pass(at: $0)?.gridRow })
        for gy in 0..<chart.height {
            let opacity: Double = worked.contains(gy) || gy == currentGridRow ? 1 : 0.28
            for run in chart.runsByRow[gy] {
                let r = CGRect(x: rect.minX + CGFloat(run.x0) * cw, y: rect.minY + CGFloat(gy) * ch, width: CGFloat(run.count) * cw + 0.3, height: ch + 0.3)
                context.fill(Path(r), with: .color(fill(run.colorIndex).opacity(opacity)))
            }
        }
        if let gy = currentGridRow {
            context.fill(Path(CGRect(x: rect.minX, y: rect.minY + CGFloat(gy) * ch - 1, width: rect.width, height: 2)), with: .color(.heather))
        }
    }
}
