import SwiftUI
import WidgetKit
import GraphghanCore

/// The run whose colour the activity's chrome (panel, buttons) should paint: the current run,
/// or -- at the boundary, where `currentCode` is nil -- the next row's first run, so the turn
/// reads as "here's what's coming" rather than going blank.
extension WorkActivityState {
    var surfaceCode: String? { atBoundary ? nextCode : currentCode }
}

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
struct RunPanel: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    /// The expanded island has less vertical room than the lock screen, so its panel is shorter.
    var height: CGFloat = 44

    var body: some View {
        if let code = state.surfaceCode, let _ = state.currentCount ?? state.nextCount {
            let hex = info.swatch(for: code)?.hex ?? YarnSurface.unknownHex
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if !state.atBoundary {
                    Text(Self.countText(state: state))
                        .font(.system(size: height * 0.68, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text(code).font(.system(.title3, design: .default).weight(.bold))
                    Text(info.swatch(for: code)?.name ?? code).font(.system(.title3, design: .serif).weight(.semibold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(nextText).font(.footnote.weight(.semibold)).opacity(0.8).lineLimit(2).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: height)
            .yarnSurface(hex, radius: 12)
            .accessibilityElement(children: .combine)
        }
    }

    private var nextText: String { Self.nextText(info: info, state: state) }

    /// The panel's count: `stitch of count` inside a fill, else the run's count; empty when there is none.
    static func countText(state: WorkActivityState) -> String {
        guard let count = state.currentCount else { return "" }
        return state.counting ? "\(state.stitch) of \(count)" : "\(count)"
    }

    /// The trailing line of the panel: the next run, the turn, or nothing.
    static func nextText(info: WorkActivityInfo, state: WorkActivityState) -> String {
        if state.atBoundary {
            let chain = info.turningChain.map { $0 > 0 ? "ch \($0), turn" : "turn" } ?? "turn"
            let next = state.nextCode.map { info.swatch(for: $0)?.name ?? $0 }
            return [chain, next.map { "Row \(state.row + 1) starts in \($0)" }].compactMap { $0 }.joined(separator: " · ")
        }
        if let code = state.nextCode, let count = state.nextCount { return "then \(count) \(info.swatch(for: code)?.name ?? code)" }
        guard state.isLastInRow else { return "" }
        return state.row < state.rowCount ? "" : "last in row"
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
        let doneHex = state.surfaceCode.flatMap { info.swatch(for: $0)?.hex }
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
                Text(state.atBoundary ? "Turned" : "Done").font(size.doneFont).frame(maxWidth: .infinity, minHeight: size.height)
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
            RunSwatch(info: info, code: code, count: state.counting ? state.stitch : count, size: 24)
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
            RunSwatch(info: info, code: code, count: state.counting ? state.stitch : count, size: 22)
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
