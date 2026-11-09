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
    /// Fabric-true, or the ribbon that reads one way (#87). The whole-chart view is the fabric either way.
    var style: BandStyle = .fabric
    let onAdvance: () -> Void
    let onJump: (_ run: Int, _ stitch: Int) -> Void
    let onToggleMode: () -> Void
    /// The stretch marks of the whole view (look-ahead spec §5.1); empty draws ticks only.
    var stretches: [Stretch] = []
    /// The return pill's text ("Back to Row 5"); nil draws none (the finished state).
    var returnLabel: String? = nil

    @State private var drag: CGFloat = 0
    @State private var dragBase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let pass = sequence.pass(at: cursor.row)
            let layout = pass.flatMap { p in
                cursor.run <= p.runs.count
                    ? BandLayout(width: geo.size.width, height: geo.size.height, chart: chart, pass: p, cursor: cursor, segmentLabel: segmentLabel, style: style)
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
        .onChange(of: style) { _, _ in drag = 0; dragBase = 0 }
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

    private func drawRow(gridRow: Int, top: CGFloat, height: CGFloat, opacity: Double, context: inout GraphicsContext, layout: BandLayout, offset: CGFloat) {
        guard gridRow >= 0, gridRow < chart.height else { return }
        // A shaped piece's ground is the band's own ground: no yarn, no hairlines (spec §6.3).
        let runs = chart.runsByRow[gridRow].filter { chart.isStitched(colorIndex: $0.colorIndex) }
        for run in runs {
            let rect = layout.runRect(x0: run.x0, count: run.count, top: top, height: height).offsetBy(dx: -offset, dy: 0)
            context.fill(Path(rect), with: .color(fill(run.colorIndex).opacity(opacity)))
        }
        guard let lo = runs.map(\.x0).min(), let hi = runs.map({ $0.x0 + $0.count }).max() else { return }
        // cell hairlines across the stitched span, then the span's bottom hairline
        for x in lo...hi {
            let px = layout.edge(x) - offset
            context.fill(Path(CGRect(x: px - 0.25, y: top, width: 0.5, height: height)), with: .color(Color.ink.opacity(0.10 * opacity)))
        }
        let a = layout.edge(lo), b = layout.edge(hi)
        context.fill(Path(CGRect(x: min(a, b) - offset, y: top + height - 0.25, width: abs(b - a), height: 0.5)), with: .color(Color.ink.opacity(0.15 * opacity)))
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
            drawRow(gridRow: gridRow, top: layout.rowTop(k), height: layout.rowHeight(k), opacity: layout.rowOpacity(k), context: &context, layout: layout, offset: offset)
        }
        // The current row past the run is faint: cover it with Ground at 70%. Inside the run the
        // ring says what is left (#74): the counted stitches sit outside it at full colour, and
        // nothing is overlaid on the remainder, because on Cream a 70% Ground wash is invisible.
        let top = layout.rowTop(0)
        if let ring = layout.ring, cursor.run < pass.runs.count {
            let ltr = layout.flowsRight
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
            let ltr = layout.flowsRight
            context.fill(Path(CGRect(x: bx - offset - (ltr ? 3 : 0), y: top - 8, width: 3, height: layout.rowHeight(0) + 8)), with: .color(.heather))
            var arc = Path()
            arc.move(to: CGPoint(x: bx - offset, y: top - 8))
            arc.addQuadCurve(to: CGPoint(x: bx - offset + (ltr ? -80 : 80), y: top - 8), control: CGPoint(x: bx - offset + (ltr ? -40 : 40), y: top - 22))
            context.stroke(arc, with: .color(.heather), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        }
        if layout.style == .ribbon { drawFolds(context: &context, layout: layout, offset: offset, size: size) }
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

    /// The ribbon's folds (#87): the row reads left to right, so the turn is always at the right
    /// end, where a dotted arc climbs to the row above, and the previous turn at the left end,
    /// where one climbs from the row below. Faint, so they read as the ribbon's shape rather than
    /// a marker; the boundary step still draws its own strong bar and arc at the right end.
    private func drawFolds(context: inout GraphicsContext, layout: BandLayout, offset: CGFloat, size: CGSize) {
        let top = layout.rowTop(0)
        let bottom = top + layout.rowHeight(0)
        let rightX = layout.spanRight - offset
        let leftX = layout.spanLeft - offset
        let style = StrokeStyle(lineWidth: 2, dash: [3, 3])
        // Only where the engine has a turn step (spec §4.4): a chart worked in the round has no fold
        // between passes, so the ribbon there is one unbroken line and draws no arc and no label.
        if sequence.hasBoundaryStep(after: cursor.row), rightX > -40, rightX < size.width + 40 {
            var up = Path()
            up.move(to: CGPoint(x: rightX, y: top + 20))
            up.addQuadCurve(to: CGPoint(x: rightX, y: top - 20), control: CGPoint(x: rightX + 22, y: top))
            context.stroke(up, with: .color(.heather.opacity(0.55)), style: style)
            context.draw(Text("turn").font(Font.Heather.annotation).foregroundStyle(Color.heather.opacity(0.8)),
                         at: CGPoint(x: min(rightX - 16, size.width - 16), y: layout.rulerTop + 14), anchor: .center)
        }
        if sequence.hasBoundaryStep(after: cursor.row - 1), leftX > -40, leftX < size.width + 40 {
            var from = Path()
            from.move(to: CGPoint(x: leftX, y: layout.rowTop(1) + 20))
            from.addQuadCurve(to: CGPoint(x: leftX, y: bottom - 20), control: CGPoint(x: leftX - 22, y: bottom + (layout.rowTop(1) - bottom) / 2))
            context.stroke(from, with: .color(.heather.opacity(0.55)), style: style)
        }
    }

    /// The whole chart at true aspect: worked rows solid, the current row a Heather line, rows ahead faint (decision 1).
    private func drawWhole(context: inout GraphicsContext, size: CGSize) {
        // The return pill gets its own strip at the bottom, so it never covers the rows she is
        // on, which at the start of a blanket are exactly the bottom ones.
        let pill = returnPill(context: context, size: size)
        let fitted = CGSize(width: size.width, height: size.height - (pill.map { $0.capsule.height + Self.returnMargin } ?? 0))
        let rect = BandLayout.wholeChartRect(chart: chart, in: fitted)
        let cw = rect.width / CGFloat(chart.width)
        let ch = rect.height / CGFloat(chart.height)
        let currentGridRow = sequence.pass(at: cursor.row)?.gridRow
        let worked = Set((1..<cursor.row).compactMap { sequence.pass(at: $0)?.gridRow })
        for gy in 0..<chart.height {
            let opacity: Double = worked.contains(gy) || gy == currentGridRow ? 1 : 0.28
            for run in chart.runsByRow[gy] where chart.isStitched(colorIndex: run.colorIndex) {
                let r = CGRect(x: rect.minX + CGFloat(run.x0) * cw, y: rect.minY + CGFloat(gy) * ch, width: CGFloat(run.count) * cw + 0.3, height: ch + 0.3)
                context.fill(Path(r), with: .color(fill(run.colorIndex).opacity(opacity)))
            }
        }
        if let gy = currentGridRow {
            context.fill(Path(CGRect(x: rect.minX, y: rect.minY + CGFloat(gy) * ch - 1, width: rect.width, height: 2)), with: .color(.heather))
        }
        drawLookAhead(context: &context, rect: rect, size: size)
        if let pill {
            context.fill(Path(roundedRect: pill.capsule, cornerRadius: pill.capsule.height / 2), with: .color(.heather))
            context.draw(pill.text, at: CGPoint(x: pill.capsule.midX, y: pill.capsule.midY), anchor: .center)
        }
    }

    /// The pill sits this far above the band's bottom edge (spec §5.1).
    static let returnMargin: CGFloat = 14

    /// The return pill's text and capsule: 36 pt tall at the default size, and taller when the label's
    /// font (which scales with Dynamic Type) needs it, so the text never spills past the capsule.
    private func returnPill(context: GraphicsContext, size: CGSize) -> (text: GraphicsContext.ResolvedText, capsule: CGRect)? {
        guard let returnLabel else { return nil }
        let text = context.resolve(Text(returnLabel).font(Font.Heather.label).foregroundStyle(Color.cream))
        let measured = text.measure(in: CGSize(width: size.width - 60, height: 200))
        let height = max(36, measured.height + 12)
        let width = measured.width + 28
        return (text, CGRect(x: (size.width - width) / 2, y: size.height - Self.returnMargin - height, width: width, height: height))
    }

    /// The look-ahead marks over the whole chart (spec §5.1): row ticks on the leading edge, a
    /// hairline before each stretch, the current stretch bracketed at the trailing edge, the
    /// labels that fit, and the way back. Geometry comes from `LookAheadLayout`.
    private func drawLookAhead(context: inout GraphicsContext, rect: CGRect, size: CGSize) {
        // Finished, the cursor still sits on the last row; a row past the end leaves no current
        // stretch, so nothing is bracketed or labelled and every hairline reads as worked.
        let row = WorkEngine.isFinished(cursor, in: sequence) ? sequence.passes.count + 1 : cursor.row
        let layout = LookAheadLayout(rect: rect, chartHeight: chart.height, sequence: sequence, stretches: stretches, row: row)
        for tick in layout.ticks {
            context.fill(Path(CGRect(x: rect.minX, y: tick.y - 0.5, width: LookAheadLayout.tickLength, height: 1)), with: .color(Color.ink.opacity(0.5)))
            // backed like the labels, so a number over a solid row still reads
            let text = context.resolve(Text("\(tick.row)").font(Font.Heather.annotation).foregroundStyle(Color.ink2))
            let tw = text.measure(in: CGSize(width: 60, height: 40)).width
            let x = rect.minX + LookAheadLayout.tickLength + 3
            context.fill(Path(roundedRect: CGRect(x: x - 3, y: tick.y - 8, width: tw + 6, height: 16), cornerRadius: 4), with: .color(Color.panel.opacity(0.88)))
            context.draw(text, at: CGPoint(x: x, y: tick.y), anchor: .leading)
        }
        for line in layout.hairlines {
            context.fill(Path(CGRect(x: rect.minX, y: line.y - 0.5, width: rect.width, height: 1)), with: .color(.heather.opacity(line.ahead ? 1 : 0.35)))
        }
        if let b = layout.bracket {
            let x = rect.maxX - LookAheadLayout.bracketInset
            var path = Path()
            path.move(to: CGPoint(x: x - 6, y: b.lowerBound + 1))
            path.addLine(to: CGPoint(x: x, y: b.lowerBound + 1))
            path.addLine(to: CGPoint(x: x, y: b.upperBound - 1))
            path.addLine(to: CGPoint(x: x - 6, y: b.upperBound - 1))
            context.stroke(path, with: .color(.heather), lineWidth: 2)
        }
        for label in layout.labels {
            let text = context.resolve(Text(label.text).font(label.current ? Font.Heather.annotation.bold() : Font.Heather.annotation)
                .foregroundStyle(label.current ? Color.heather : Color.ink))
            let tw = text.measure(in: CGSize(width: rect.width, height: 40)).width
            let dots = CGFloat(label.codes.count) * 9
            let right = rect.maxX - LookAheadLayout.labelInset
            let pill = CGRect(x: right - tw - dots - 6, y: label.y - LookAheadLayout.labelHeight / 2, width: tw + dots + 12, height: LookAheadLayout.labelHeight)
            context.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(Color.panel.opacity(0.88)))
            context.draw(text, at: CGPoint(x: right, y: label.y), anchor: .trailing)
            for (j, code) in label.codes.enumerated() {
                let cx = pill.minX + 6 + 3.5 + CGFloat(j) * 9
                let dot = Path(ellipseIn: CGRect(x: cx - 3.5, y: label.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(fill(chart.colorIndex(of: code) ?? 0)))
                context.stroke(dot, with: .color(Color.ink.opacity(0.15)), lineWidth: 0.5)
            }
        }
    }
}
