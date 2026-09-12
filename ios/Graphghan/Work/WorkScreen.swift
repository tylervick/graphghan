import SwiftUI
import GraphghanCore

/// The Work screen without the model (spec §6.1): stone ground, the work on one card, and below it
/// the Done field with the glass Back and Done controls floating at its bottom. `WorkView` owns
/// state and haptics and feeds this.
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

    private var card: some View {
        VStack(spacing: 12) {
            if finished {
                VStack(spacing: 8) {
                    Text("Finished").font(Font.Heather.title)
                    Text("Every row is done. Block it, weave in the ends, and take a picture.")
                        .font(Font.Heather.body).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .foregroundStyle(Color.ink)
                .background(Color.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
            } else {
                RowStripView(chart: chart, sequence: sequence, cursor: cursor)
                if let pass = sequence.pass(at: cursor.row) {
                    RunChipsView(chart: chart, pass: pass, cursor: cursor, onSelect: onSelectRun)
                }
                SwatchStack(chart: chart, sequence: sequence, cursor: cursor)
            }
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
        .contentShape(Rectangle())
        .onTapGesture {}  // the card swallows taps: nothing inside advances by accident
        .padding(.horizontal, 12)
        .foregroundStyle(Color.ink)
    }

    /// Everything below the card is the Done target; the controls float at its bottom.
    private var field: some View {
        ZStack(alignment: .bottom) {
            Button(action: finished ? onClose : onDone) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneLabel)
            DoneField(finished: finished, canGoBack: cursor != .start, doneLabel: doneLabel,
                      doneForeground: (currentEntry?.hex).map(YarnSurface.foreground) ?? Color.ink,
                      backForeground: (previousEntry?.hex).map(YarnSurface.foreground) ?? Color.ink2,
                      stops: trackStops,
                      onDone: finished ? onClose : onDone, onBack: onBack)
                .padding(.horizontal, 16)
                .padding(.bottom, 44)
        }
        .frame(maxHeight: .infinity)
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

    private var doneLabel: String {
        guard !finished else { return "Close" }
        guard let pass = sequence.pass(at: cursor.row), let entry = currentEntry else { return "Done" }
        return "Done with \(pass.runs[cursor.run].count) \(entry.name)"
    }

    private func sideText(_ pass: Pass) -> String {
        let dir = pass.direction.map { $0 == .ltr ? "read left to right" : "read right to left" } ?? "read direction not specified"
        guard let side = pass.side else { return dir }
        return "\(side == .ws ? "Wrong side" : "Right side") · \(dir)"
    }
}
