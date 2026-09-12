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
        let hex = info.swatch(for: code)?.hex ?? YarnSurface.unknownHex
        Text("\(count)")
            .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .frame(minWidth: size * 1.3, minHeight: size)
            .padding(.horizontal, 6)
            .yarnSurface(hex, radius: size * 0.22)
            .accessibilityLabel("\(count) \(info.swatch(for: code)?.name ?? code)")
    }
}

/// The current run as the Work screen shows it: count, code, and name on a panel in its own yarn
/// color, with the next run on deck at the trailing end. Shared by the lock screen and the
/// expanded Dynamic Island so the two stay the same view (spec §6.8).
private struct RunPanel: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    /// The expanded island has less vertical room than the lock screen, so its panel is shorter.
    var height: CGFloat = 44

    var body: some View {
        if let code = state.currentCode, let count = state.currentCount {
            let hex = info.swatch(for: code)?.hex ?? YarnSurface.unknownHex
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(count)")
                    .font(.system(size: height * 0.68, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text(code).font(.system(.title3, design: .default).weight(.bold))
                Text(info.swatch(for: code)?.name ?? code).font(.system(.title3, design: .serif).weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Text(nextText).font(.footnote.weight(.semibold)).opacity(0.8).lineLimit(2).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: height)
            .yarnSurface(hex, radius: 12)
            .accessibilityElement(children: .combine)
        }
    }

    private var nextText: String {
        if let code = state.nextCode, let count = state.nextCount { return "then \(count) \(info.swatch(for: code)?.name ?? code)" }
        return state.isLastInRow ? "last in row" : ""
    }
}

/// Back + Done, wired to the intents, each tinted with the run it takes you to: Back the previous
/// run's yarn color, Done the current one's, as on the Work screen. `size` picks the lock screen's
/// roomy labels or the island's compact ones.
private struct RunButtons: View {
    /// The island has less room for text than the lock screen, so its labels drop to the body
    /// font. Both keep 40pt-tall labels: anything shorter stops being a comfortable tap target.
    enum Size {
        case lockScreen, island
        var symbolFont: Font { self == .lockScreen ? .title3 : .body }
        var doneFont: Font { self == .lockScreen ? .system(.title3, design: .default).weight(.bold) : .body.bold() }
        /// The island's expanded regions clip a hair sooner than the lock screen's 160pt budget
        /// (seen on an iPhone 15 Pro), so its controls give back a few points.
        var height: CGFloat { self == .lockScreen ? 40 : 34 }
    }

    let info: WorkActivityInfo
    let state: WorkActivityState
    var size: Size = .lockScreen

    var body: some View {
        let doneHex = state.currentCode.flatMap { info.swatch(for: $0)?.hex }
        let backHex = state.previousCode.flatMap { info.swatch(for: $0)?.hex }
        HStack(spacing: 10) {
            Button(intent: BackRunIntent(projectID: info.projectID)) {
                Image(systemName: "arrow.uturn.backward").font(size.symbolFont).frame(width: 44, height: size.height)
                    .foregroundStyle(backHex.map(YarnSurface.foreground) ?? Color.cream)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(backHex.map(YarnSurface.fill) ?? Color.mossDeep)
            .disabled(backHex == nil)
            .accessibilityLabel("Back one run")
            Button(intent: AdvanceRunIntent(projectID: info.projectID)) {
                Text("Done").font(size.doneFont).frame(maxWidth: .infinity, minHeight: size.height)
                    .foregroundStyle(doneHex.map(YarnSurface.foreground) ?? Color.cream)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(doneHex.map(YarnSurface.fill) ?? Color.moss)
        }
    }
}

/// Title and "Row 42 of 184", shared by the lock screen and the expanded island.
private struct ActivityHeader: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        HStack {
            Text(info.title).font(.system(.headline, design: .serif).weight(.semibold)).lineLimit(1)
            Spacer()
            if state.message == nil { Text("Row \(state.row) of \(state.rowCount)").font(.subheadline.bold()).monospacedDigit().opacity(0.75) }
        }
    }
}

/// Lock screen content (spec §6.8). No painted card: the system supplies the activity's material
/// (Liquid Glass on iOS 26), so the text uses the adaptive primary color and only the run panel
/// and the buttons carry our colors. The expanded Dynamic Island is the same content.
struct WorkLockScreenView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActivityHeader(info: info, state: state)
            if let message = state.message {
                Text(message).font(.subheadline)
            } else if state.finished {
                Text("Finished").font(.system(.title2, design: .serif).weight(.semibold))
            } else {
                // Two rows: the run, then the buttons. On one row at lock-screen width the fixed
                // button widths squeeze the colour name and the "then …" line down to an ellipsis.
                RunPanel(info: info, state: state)
                RunButtons(info: info, state: state, size: .lockScreen)
            }
        }
        // Apple's Lock Screen activity budget is 160pt tall and the system clips past it, so the
        // card is sized to stay inside that: 44pt panel, 40pt button labels, 12pt padding, 8pt stack.
        .padding(12)
        .foregroundStyle(.primary)
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

/// Spec §6.8 wants the expanded island to read as the lock screen does: the same header and the
/// same run panel, minus the buttons (they live in the bottom region); the island paints its own
/// background.
struct WorkExpandedCenterView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActivityHeader(info: info, state: state)
            if let message = state.message {
                Text(message).font(.subheadline)
            } else if state.finished {
                Text("Finished").font(.system(.title2, design: .serif).weight(.semibold))
            } else {
                RunPanel(info: info, state: state, height: 38)
            }
        }
        .foregroundStyle(.primary)
    }
}

struct WorkExpandedBottomView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        if state.message == nil, !state.finished {
            RunButtons(info: info, state: state, size: .island)
                .foregroundStyle(.primary)
        }
    }
}
