import SwiftUI
import GraphghanCore

/// The Work screen without the model (spec §6.1): stone ground, the strip and chips on a small
/// card, and below them the color columns under glass that carry the run and the actions.
/// `WorkView` owns state and haptics and feeds this.
struct WorkScreen: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    let onDone: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let onJump: () -> Void
    let onSelectRun: (Int) -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var finished: Bool { WorkEngine.isFinished(cursor, in: sequence) }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 0) {
                    VStack(spacing: 14) { header; card }.frame(maxWidth: .infinity)
                    field.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 14) { header; card; field }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The field is the tap target down to the display edge; the controls' own bottom padding
        // keeps them above the home indicator.
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ground.weave().ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink2)
            .accessibilityLabel("Close")
            Spacer()
            VStack(spacing: 4) {
                if let pass = sequence.pass(at: cursor.row) {
                    (Text("\(pass.label) ") + Text("of").fontWeight(.medium).foregroundStyle(Color.ink2) + Text(" \(sequence.passes.count)"))
                        .font(Font.Heather.rowNumber).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .onLongPressGesture(perform: onJump)
                        .accessibilityHint("Long press to jump to a row")
                        .accessibilityAction(named: "Jump to row", onJump)
                    Text(finished ? "Every row worked" : sideText(pass)).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The strip and the chips: the row's context, in a small Panel card above the field.
    private var card: some View {
        VStack(spacing: 10) {
            RowStripView(chart: chart, sequence: sequence, cursor: cursor)
            if !finished, let pass = sequence.pass(at: cursor.row) {
                RunChipsView(chart: chart, pass: pass, cursor: cursor, onSelect: onSelectRun)
            }
        }
        .padding(10)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {}  // the card swallows taps: nothing inside advances by accident
        .padding(.horizontal, 12)
        .foregroundStyle(Color.ink)
    }

    /// The color columns under glass: previous, current, and a sliver of the next.
    private var field: some View {
        WorkField(finished: finished, canGoBack: cursor != .start, content: fieldContent, doneLabel: doneLabel,
                  doneForeground: (currentEntry?.hex).map(YarnSurface.foreground) ?? Color.ink,
                  backForeground: (previousEntry?.hex).map(YarnSurface.foreground) ?? Color.ink2,
                  stops: trackStops,
                  onDone: finished ? onClose : onDone, onBack: onBack)
            .frame(maxHeight: .infinity)
            .padding(.bottom, 44)
    }

    private var fieldContent: WorkFieldContent? {
        guard !finished, let pass = sequence.pass(at: cursor.row), let entry = currentEntry else { return nil }
        return WorkFieldContent(count: pass.runs[cursor.run].count, code: entry.code, name: entry.name,
                                onDeck: OnDeckRule.onDeck(cursor: cursor, chart: chart, sequence: sequence)?.text,
                                stitch: chart.stitch?.code)
    }

    /// The run Back returns to: the one before the cursor, or the last run of the previous row.
    private var previousEntry: ChartDocument.PaletteEntry? {
        guard let step = WorkEngine.apply(.back, to: cursor, in: sequence) else { return nil }
        return entry(at: step.cursor)
    }

    /// The runs two back through two ahead of the cursor, walked with the engine so row boundaries
    /// behave exactly as Back and Done do; the ones off screen are what make the slide possible.
    private var trackStops: [TrackStop] {
        var stops: [TrackStop] = []
        var back = cursor
        for offset in 1...2 {
            guard let step = WorkEngine.apply(.back, to: back, in: sequence) else { break }
            back = step.cursor
            stops.insert(TrackStop(cursor: back, offset: -offset, hex: entry(at: back)?.hex), at: 0)
        }
        stops.append(TrackStop(cursor: cursor, offset: 0, hex: entry(at: cursor)?.hex))
        var ahead = cursor
        for offset in 1...2 {
            guard let step = WorkEngine.apply(.advance, to: ahead, in: sequence) else { break }
            ahead = step.cursor
            stops.append(TrackStop(cursor: ahead, offset: offset, hex: entry(at: ahead)?.hex))
        }
        return stops
    }

    private func entry(at c: Cursor) -> ChartDocument.PaletteEntry? {
        guard let pass = sequence.pass(at: c.row), c.run < pass.runs.count else { return nil }
        return chart.palette[chart.colorIndex(of: pass.runs[c.run].code) ?? 0]
    }

    /// The palette entry of the run under the cursor; nil once finished or past the last run.
    private var currentEntry: ChartDocument.PaletteEntry? { finished ? nil : entry(at: cursor) }

    private var doneLabel: String { Self.doneLabel(chart: chart, sequence: sequence, cursor: cursor) }

    /// "Done with 4 single crochet in Charcoal": the stitch name when the chart states one the
    /// tables know, its abbreviation otherwise, nothing when the chart is silent (spec §6.4).
    static func doneLabel(chart: Chart, sequence: WorkSequence, cursor: Cursor) -> String {
        guard !WorkEngine.isFinished(cursor, in: sequence) else { return "Close" }
        guard let pass = sequence.pass(at: cursor.row), cursor.run < pass.runs.count else { return "Done" }
        let run = pass.runs[cursor.run]
        let entry = chart.palette[chart.colorIndex(of: run.code) ?? 0]
        if let stitch = chart.stitch {
            return "Done with \(run.count) \(stitch.name ?? stitch.code) in \(entry.name)"
        }
        return "Done with \(run.count) \(entry.name)"
    }

    private func sideText(_ pass: Pass) -> String {
        let dir = pass.direction.map { $0 == .ltr ? "read left to right" : "read right to left" } ?? "read direction not specified"
        guard let side = pass.side else { return dir }
        return "\(side == .ws ? "Wrong side" : "Right side") · \(dir)"
    }
}
