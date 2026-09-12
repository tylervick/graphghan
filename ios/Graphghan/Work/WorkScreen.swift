import SwiftUI
import GraphghanCore

/// The Work screen without the model (spec §6.1): stone ground, the run on one card, and below it
/// the chart itself as the Done target, with the glass Back and Done controls floating over the
/// stitches. `WorkView` owns state and haptics and feeds this.
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

    /// The chart rows around the cursor, full width, are the Done target; the controls float on them.
    private var field: some View {
        ZStack(alignment: .bottom) {
            Button(action: finished ? onClose : onDone) {
                RowStripView(chart: chart, sequence: sequence, cursor: cursor, rowsAround: 5, backdrop: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneLabel)
            DoneField(finished: finished, canGoBack: cursor != .start, doneLabel: doneLabel, doneHex: currentEntry?.hex,
                      onDone: finished ? onClose : onDone, onBack: onBack)
                .padding(.horizontal, 16)
                .padding(.bottom, 44)
        }
        .frame(maxHeight: .infinity)
    }

    /// The palette entry of the run under the cursor; nil once finished or past the last run.
    private var currentEntry: ChartDocument.PaletteEntry? {
        guard !finished, let pass = sequence.pass(at: cursor.row), cursor.run < pass.runs.count else { return nil }
        return chart.palette[chart.colorIndex(of: pass.runs[cursor.run].code) ?? 0]
    }

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
