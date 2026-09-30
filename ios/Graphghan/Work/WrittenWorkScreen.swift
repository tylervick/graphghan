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

    /// What the panel says when the cursor's row is not in the document (it lost rows since the
    /// cursor was made); nil whenever there is a row, or the finished panel, to show instead.
    static func missingRowMessage(sequence: WrittenSequence, row: Int, finished: Bool) -> String? {
        finished || sequence.pass(at: row) != nil ? nil : "This row isn't in the pattern any more."
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if finished {
                finishedPanel.padding(.top, 14)
                Spacer(minLength: 0)
            } else if let pass {
                // The row card scrolls; the bar below is pinned outside the scroll region via
                // `safeAreaInset`, so a long row (or an accessibility text size) never pushes
                // Back/Done off-screen. `ImageRenderer` can't flatten this `ScrollView` (#67), so
                // its content renders blank in a full-screen snapshot -- `WrittenRowPanel` is
                // snapshotted on its own to pin the row text down.
                ScrollView {
                    WrittenRowPanel(pass: pass, rowText: Self.rowText(row: cursor.row, total: sequence.totalRows))
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }
            } else if let message = Self.missingRowMessage(sequence: sequence, row: cursor.row, finished: finished) {
                Card {
                    Text(message).font(Font.Heather.body).foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                Spacer(minLength: 0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !finished {
                VStack(spacing: 14) {
                    if sequence.isOpen {
                        Button("Finish piece", action: onFinishPiece)
                            .buttonStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    bar
                }
            }
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

    /// "`title` done", the Next/Close action, and a low-emphasis Back -- Done on the last row
    /// finishes a piece, but Back must still be able to un-finish it in place (spec §5.4, review
    /// focus 1), so the finished panel keeps a way back rather than becoming a dead end.
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
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .font(Font.Heather.label)
                    .foregroundStyle(Color.ink2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .accessibilityAction(named: "Back", onBack)
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
