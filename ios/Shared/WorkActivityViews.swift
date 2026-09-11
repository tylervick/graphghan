import SwiftUI
import WidgetKit
import GraphghanCore

/// A run as a coloured swatch with its count. `size` is the swatch height.
struct RunSwatch: View {
    let info: WorkActivityInfo
    let code: String
    let count: Int
    var size: CGFloat = 44

    var body: some View {
        let hex = info.swatch(for: code)?.hex ?? "#888888"
        Text("\(count)")
            .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(HexColor.isLight(hex) ? .black : .white)
            .frame(minWidth: size * 1.3, minHeight: size)
            .padding(.horizontal, 6)
            .background(HexColor.color(hex), in: RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityLabel("\(count) \(info.swatch(for: code)?.name ?? code)")
    }
}

/// The current run: swatch, colour name, and what comes after it. Shared by the lock screen and
/// the expanded Dynamic Island so the two stay the same view (spec §7).
private struct RunRow: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var swatchSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let code = state.currentCode, let count = state.currentCount {
                RunSwatch(info: info, code: code, count: count, size: swatchSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.swatch(for: code)?.name ?? code).font(.title3.bold()).lineLimit(1)
                    Text(nextText).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var nextText: String {
        if let code = state.nextCode, let count = state.nextCount { return "then \(count) \(info.swatch(for: code)?.name ?? code)" }
        return state.isLastInRow ? "last run in this row" : ""
    }
}

/// Back + Done, wired to the intents. Shared by the lock screen and the expanded Dynamic Island's
/// bottom region; `size` picks the lock screen's roomy labels or the island's compact ones.
private struct RunButtons: View {
    /// The island has less room for text than the lock screen, so its labels drop to the body
    /// font. Both keep 40pt-tall labels: anything shorter stops being a comfortable tap target.
    enum Size {
        case lockScreen, island
        var symbolFont: Font { self == .lockScreen ? .title3 : .body }
        var doneFont: Font { self == .lockScreen ? .title3.bold() : .body.bold() }
        var height: CGFloat { 40 }
    }

    let info: WorkActivityInfo
    var size: Size = .lockScreen

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: BackRunIntent(projectID: info.projectID)) {
                Image(systemName: "arrow.uturn.backward").font(size.symbolFont).frame(width: 44, height: size.height)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Back one run")
            Button(intent: AdvanceRunIntent(projectID: info.projectID)) {
                Text("Done").font(size.doneFont).frame(maxWidth: .infinity, minHeight: size.height)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Lock screen content (spec §7). The expanded Dynamic Island is the same thing without the
/// opaque card: `WorkExpandedCenterView` reuses the header and `RunRow`, `WorkExpandedBottomView`
/// reuses `RunButtons`.
struct WorkLockScreenView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState

    private static let cardBackground = Color(white: 0.08)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(info.title).font(.headline).lineLimit(1)
                Spacer()
                if state.message == nil { Text("Row \(state.row) of \(state.rowCount)").font(.subheadline.bold()) }
            }
            if let message = state.message {
                Text(message).font(.subheadline)
            } else if state.finished {
                Text("Finished").font(.title2.bold())
            } else {
                // Two rows: the run, then the buttons. On one row at lock-screen width the fixed
                // button widths squeeze the colour name and the "then …" line down to an ellipsis.
                RunRow(info: info, state: state)
                RunButtons(info: info, size: .lockScreen)
            }
        }
        // Apple's Lock Screen activity budget is 160pt tall and the system clips past it, so the
        // card is sized to stay inside that: 44pt swatch, 40pt button labels, 12pt padding, 6pt stack.
        .padding(12)
        // The tint only applies inside a real activity; the opaque background of the same colour
        // keeps the white text legible everywhere else (previews, ImageRenderer snapshots).
        .background(Self.cardBackground)
        .activityBackgroundTint(Self.cardBackground)
        .foregroundStyle(.white)
    }
}

struct WorkCompactLeadingView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        if let code = state.currentCode, let count = state.currentCount {
            RunSwatch(info: info, code: code, count: count, size: 24)
        } else if state.message != nil {
            // Project or chart gone: not something to celebrate with a checkmark.
            Image(systemName: "exclamationmark.circle.fill")
        } else {
            Image(systemName: "checkmark.circle.fill")
        }
    }
}

struct WorkCompactTrailingView: View {
    let state: WorkActivityState
    var body: some View {
        Text(state.message == nil ? "R\(state.row)" : "—").font(.caption.bold()).monospacedDigit()
    }
}

struct WorkMinimalView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        if let code = state.currentCode, let count = state.currentCount {
            RunSwatch(info: info, code: code, count: count, size: 22)
        } else if state.message != nil {
            Image(systemName: "exclamationmark.circle.fill")
        } else {
            Image(systemName: "checkmark.circle.fill")
        }
    }
}

/// Spec §7 wants the expanded island to read as the lock screen does: the same header and the
/// same `RunRow`, minus the buttons (they live in the bottom region) and minus the opaque card
/// (the island paints its own background).
struct WorkExpandedCenterView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(info.title).font(.headline).lineLimit(1)
                Spacer()
                if state.message == nil { Text("Row \(state.row) of \(state.rowCount)").font(.subheadline.bold()) }
            }
            if let message = state.message {
                Text(message).font(.subheadline)
            } else if state.finished {
                Text("Finished").font(.title2.bold())
            } else {
                RunRow(info: info, state: state)
            }
        }
    }
}

struct WorkExpandedBottomView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        if state.message == nil, !state.finished {
            RunButtons(info: info, size: .island)
        }
    }
}
