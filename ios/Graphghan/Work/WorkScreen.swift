import SwiftUI
import GraphghanCore

/// The Work screen without the model (spec §6.1): Moss is the ground and the Done target; the work
/// floats on one stone card. `WorkView` owns state and haptics and feeds this.
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
        .background(Color.moss.weave(.cream, opacity: 0.05).ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.cream.opacity(0.75))
            .accessibilityLabel("Close")
            Spacer()
            VStack(spacing: 4) {
                if let pass = sequence.pass(at: cursor.row) {
                    (Text("\(pass.label) ") + Text("of").fontWeight(.medium).foregroundStyle(Color.cream.opacity(0.7)) + Text(" \(sequence.passes.count)"))
                        .font(Font.Heather.rowNumber).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .onLongPressGesture(perform: onJump)
                        .accessibilityHint("Long press to jump to a row")
                        .accessibilityAction(named: "Jump to row", onJump)
                    Text(finished ? "Every row worked" : sideText(pass)).font(Font.Heather.caption).foregroundStyle(Color.cream.opacity(0.75))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(Color.cream)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var card: some View {
        VStack(spacing: 12) {
            RowStripView(chart: chart, sequence: sequence, cursor: cursor)
            if finished {
                VStack(spacing: 8) {
                    Text("Finished").font(Font.Heather.title)
                    Text("Every row is done. Block it, weave in the ends, and take a picture.")
                        .font(Font.Heather.body).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .yarnSurface("#F2E8D5", radius: 16)
            } else {
                if let pass = sequence.pass(at: cursor.row) {
                    RunChipsView(chart: chart, pass: pass, cursor: cursor, onSelect: onSelectRun)
                }
                SwatchStack(chart: chart, sequence: sequence, cursor: cursor)
            }
        }
        .padding(12)
        .background(Color.ground.weave().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        .contentShape(Rectangle())
        .onTapGesture {}  // the card swallows taps: nothing inside advances by accident
        .padding(.horizontal, 12)
        .foregroundStyle(Color.ink)
    }

    private var field: some View {
        DoneField(finished: finished, canGoBack: cursor != .start, onDone: finished ? onClose : onDone, onBack: onBack)
            .frame(maxHeight: .infinity)
    }

    private func sideText(_ pass: Pass) -> String {
        let dir = pass.direction.map { $0 == .ltr ? "read left to right" : "read right to left" } ?? "read direction not specified"
        guard let side = pass.side else { return dir }
        return "\(side == .ws ? "Wrong side" : "Right side") · \(dir)"
    }
}
