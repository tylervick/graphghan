import SwiftUI
import GraphghanCore

/// The Work screen for a written piece (spec §6.4): no strip, no chart band -- the row's own
/// words, worked one row at a time. `WorkView` owns state, persistence and the Live Activity (of
/// which a written piece starts none, #223) and feeds this.
struct WrittenWorkScreen: View {
    let title: String
    let sequence: WrittenSequence
    let cursor: Cursor
    let finished: Bool
    let next: String?
    let onDone: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let onJump: () -> Void
    let onFinishPiece: () -> Void
    let onNext: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var pass: WrittenPass? { sequence.pass(at: cursor.row) }
    private var canGoBack: Bool { !finished && cursor.row > 1 }

    static func rowText(row: Int, total: Int?) -> String { total.map { "Row \(row) of \($0)" } ?? "Row \(row)" }

    var body: some View {
        VStack(spacing: 14) {
            header
            panel
            Spacer(minLength: 0)
            if !finished, sequence.isOpen {
                Button("Finish piece", action: onFinishPiece)
                    .buttonStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            if !finished { bar }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text(Self.rowText(row: cursor.row, total: sequence.totalRows))
                    .font(Font.Heather.rowNumber).monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .onLongPressGesture(perform: onJump)
                    .accessibilityHint("Long press to jump to a row")
                    .accessibilityAction(named: "Jump to row", onJump)
                Text(title).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The pass's label, its text at heading size, and its count as a badge -- one accessibility
    /// element, spoken as the row and the row's own words. No `.lineLimit`, so a long row grows the
    /// panel rather than truncating; a `ScrollView` would do this more gracefully, but `ImageRenderer`
    /// cannot flatten one (its content renders blank, same family of bug as the known List/Form/Toggle
    /// limitation), so the panel grows instead and only clips at the screen's own edge.
    @ViewBuilder private var panel: some View {
        if finished {
            finishedPanel
        } else if let pass {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(pass.label).font(Font.Heather.label).foregroundStyle(Color.ink2)
                    Text(pass.text).font(Font.Heather.heading).foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let count = pass.count {
                        Text("\(count) sts").font(Font.Heather.label).foregroundStyle(Color.ink2)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(Color.ink2.opacity(0.6), lineWidth: 1.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Self.rowText(row: cursor.row, total: sequence.totalRows)). \(pass.text)")
        }
    }

    private var finishedPanel: some View {
        Card {
            VStack(spacing: 14) {
                Text("\(title) done").font(Font.Heather.title).foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                if let next {
                    Button("Next: \(next)", action: onNext).buttonStyle(.primary)
                } else {
                    Button("Close", action: onClose).buttonStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
    }

    private var bar: some View {
        let hex = YarnSurface.creamHex
        return HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 22, weight: .semibold))
                    // At an accessibility size the word no longer fits beside the arrow in 110 pt,
                    // and truncating it is worse than dropping it: the label still says "Back".
                    if !dynamicTypeSize.isAccessibilitySize { Text("Back").font(Font.Heather.label) }
                }
                .frame(width: 110, height: 72)
                .foregroundStyle(YarnSurface.foreground(hex).opacity(canGoBack ? 1 : 0.4))
                .contentShape(Capsule())
                .capsuleGlass(hex)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .accessibilityLabel("Back")
            Button(action: onDone) {
                Image(systemName: "checkmark").font(.system(size: 30, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 72)
                    .foregroundStyle(YarnSurface.foreground(hex))
                    .contentShape(Capsule())
                    .capsuleGlass(hex)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done, next row")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 44)
    }
}
