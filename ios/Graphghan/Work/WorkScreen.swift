import SwiftUI
import GraphghanCore

/// The Work screen without the model (spec §5): header, the panel in the run's colour, the chart
/// band at stitch scale, and the bar. `WorkView` owns state, persistence and haptics and feeds this.
struct WorkScreen: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    let step: CountStep
    let onDone: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let onJump: () -> Void
    let onJumpWithinRow: (_ run: Int, _ stitch: Int) -> Void
    let onSetStep: (CountStep) -> Void

    @State private var mode: ChartBand.Mode = .band
    @State private var showRunList = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var finished: Bool { WorkEngine.isFinished(cursor, in: sequence) }
    private var content: WorkPanelContent { WorkPanelContent.make(chart: chart, sequence: sequence, cursor: cursor, step: step) }
    private var canGoBack: Bool { WorkEngine.apply(.back, to: cursor, in: sequence, step: step) != nil }

    static func actionLabel(chart: Chart, sequence: WorkSequence, cursor: Cursor, step: CountStep) -> String {
        WorkPanelContent.make(chart: chart, sequence: sequence, cursor: cursor, step: step).actionLabel
    }

    var body: some View {
        let c = content
        Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 14) {
                    VStack(spacing: 14) { header; panel(c); Spacer(minLength: 0); bar(c) }.frame(maxWidth: .infinity)
                    band(c).frame(maxWidth: .infinity)
                }
                .padding(.bottom, 16)
            } else {
                VStack(spacing: 14) { header; panel(c); band(c); bar(c) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ground.weave().ignoresSafeArea())
        .sheet(isPresented: $showRunList) {
            if let pass = sequence.pass(at: cursor.row) {
                RunListSheet(chart: chart, pass: pass, current: cursor.run) { onJumpWithinRow($0, 0) }
            }
        }
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
                        .onTapGesture { withAnimation { mode = mode == .band ? .whole : .band } }
                        .onLongPressGesture(perform: onJump)
                        .accessibilityHint("Long press to jump to a row")
                        .accessibilityAction(named: "Jump to row", onJump)
                    Text(finished ? "Every row worked" : sideText(pass)).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The panel is the spoken element: one label, the on-deck line as its value, the actions as rotor actions (spec §6).
    private func panel(_ c: WorkPanelContent) -> some View {
        WorkPanel(content: c)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture(perform: finished ? onClose : onDone)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(c.actionLabel)
            .accessibilityValue([c.spokenValue, c.onDeck].compactMap { $0 }.joined(separator: ". "))
            .accessibilityAction { finished ? onClose() : onDone() }
            .accessibilityAction(named: "Back", onBack)
            .accessibilityAction(named: "Jump to row", onJump)
            .accessibilityAction(named: "Jump within row") { showRunList = true }
            .accessibilityAction(named: "Choose counting step") { onSetStep(step.next) }
    }

    private func band(_ c: WorkPanelContent) -> some View {
        // Finished: the whole chart solid, not the last row with a turn marker on it (spec §5.1).
        // The band is then locked to `.whole`, so its tap -- which returns from the whole chart --
        // has nowhere to go and closes, the same thing every other surface does when finished.
        ChartBand(chart: chart, sequence: sequence, cursor: cursor, segmentLabel: c.bandLabel, mode: finished ? .whole : mode,
                  onAdvance: finished ? onClose : onDone, onJump: onJumpWithinRow,
                  onToggleMode: finished ? onClose : { withAnimation { mode = mode == .band ? .whole : .band } })
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
    }

    private func bar(_ c: WorkPanelContent) -> some View {
        let nextHex = sequence.pass(at: cursor.row + 1)?.runs.first.map { chart.palette[chart.colorIndex(of: $0.code) ?? 0].hex }
        let doneHex = c.kind == .turn ? (nextHex ?? WorkPanelContent.creamHex) : c.hex
        // Back can itself land on a boundary position (`run == runs.count`); clamp to that row's
        // last run so the capsule wears the colour it returns to rather than falling back to Cream.
        let prevHex = WorkEngine.apply(.back, to: cursor, in: sequence, step: step).flatMap { s in
            sequence.pass(at: s.cursor.row).flatMap { p in p.runs.isEmpty ? nil : p.runs[min(s.cursor.run, p.runs.count - 1)] }
        }.map { chart.palette[chart.colorIndex(of: $0.code) ?? 0].hex } ?? YarnSurface.creamHex
        let action = Button(action: finished ? onClose : onDone) {
            Group {
                if c.capsule == "checkmark" { Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)) }
                else { Text(c.capsule).font(Font.Heather.done).minimumScaleFactor(0.6).lineLimit(1) }
            }
            .frame(maxWidth: .infinity).frame(height: 72)
            .foregroundStyle(YarnSurface.foreground(doneHex))
            .contentShape(Capsule())
            .capsuleGlass(doneHex)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.actionLabel)
        return HStack(spacing: 12) {
            if !finished {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 22, weight: .semibold))
                        // At an accessibility size the word no longer fits beside the arrow in 110 pt,
                        // and truncating it is worse than dropping it: the label still says "Back".
                        if !dynamicTypeSize.isAccessibilitySize { Text("Back").font(Font.Heather.label) }
                    }
                    .frame(width: 110, height: 72)
                    .foregroundStyle(YarnSurface.foreground(prevHex).opacity(canGoBack ? 1 : 0.4))
                    .contentShape(Capsule())
                    .capsuleGlass(prevHex)
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .accessibilityLabel("Back")
            }
            // The step picker hangs off the capsule for every kind, not only fills and runs (spec
            // §5.4); finished has nothing to pick, and an empty `contextMenu` is a dead long press.
            if finished {
                action
            } else {
                action.contextMenu {
                    ForEach(CountStep.allCases, id: \.rawValue) { s in
                        Button { onSetStep(s) } label: {
                            if s == step { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 44)
    }

    private func sideText(_ pass: Pass) -> String {
        let dir = pass.direction.map { $0 == .ltr ? "read left to right" : "read right to left" } ?? "read direction not specified"
        guard let side = pass.side else { return dir }
        return "\(side == .ws ? "Wrong side" : "Right side") · \(dir)"
    }
}

extension CountStep {
    var title: String {
        switch self {
        case .one: "Count every stitch"
        case .five: "Count by 5"
        case .ten: "Count by 10"
        case .twenty: "Count by 20"
        case .wholeRun: "One tap per run"
        }
    }
    /// The next step in the picker's order, for the VoiceOver action that cycles it.
    var next: CountStep {
        let all = CountStep.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

private extension View {
    /// Clear Liquid Glass over the yarn colour on iOS 26; a thin material over it before that.
    @ViewBuilder func capsuleGlass(_ hex: String) -> some View {
        if #available(iOS 26, *) {
            background(YarnSurface.fill(hex).opacity(0.85), in: Capsule())
                .glassEffect(.clear.interactive(), in: Capsule())
        } else {
            background(YarnSurface.fill(hex), in: Capsule())
                .overlay(Capsule().strokeBorder(YarnSurface.hairline, lineWidth: 1))
        }
    }
}
