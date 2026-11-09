import SwiftUI
import GraphghanCore

/// The Work screen without the model (spec §5): header, the panel in the run's colour, the chart
/// band at stitch scale, and the bar. `WorkView` owns state, persistence and haptics and feeds this.
struct WorkScreen: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    let step: CountStep
    /// Inside a repeat segment a tap is one repetition (#81); the project's setting.
    let perRepetition: Bool
    let onDone: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let onJump: () -> Void
    let onJumpWithinRow: (_ run: Int, _ stitch: Int) -> Void
    let onSetStep: (CountStep) -> Void
    let onSetPerRepetition: (Bool) -> Void
    /// Fabric-true band or the ribbon that reads one way (#87); the project's setting.
    var bandStyle: BandStyle = .default
    var onSetBandStyle: (BandStyle) -> Void = { _ in }
    /// The chart's stretches (look-ahead spec §3), computed once by `WorkView`; empty means no
    /// look-ahead line and no stretch marks, which is also what a one-stretch chart gets.
    var stretches: [Stretch] = []

    @State private var mode: ChartBand.Mode = .band
    @State private var showRunList = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var finished: Bool { WorkEngine.isFinished(cursor, in: sequence) }
    private var content: WorkPanelContent { WorkPanelContent.make(chart: chart, sequence: sequence, cursor: cursor, step: step, perRepetition: perRepetition) }
    private var canGoBack: Bool { WorkEngine.apply(.back, to: cursor, in: sequence, step: step, perRepetition: perRepetition) != nil }

    static func actionLabel(chart: Chart, sequence: WorkSequence, cursor: Cursor, step: CountStep, perRepetition: Bool = true) -> String {
        WorkPanelContent.make(chart: chart, sequence: sequence, cursor: cursor, step: step, perRepetition: perRepetition).actionLabel
    }

    /// The header's spoken value (spec §4.3): the side text, the shaped caption, the look-ahead line.
    static func headerValue(chart: Chart, sequence: WorkSequence, cursor: Cursor, stretches: [Stretch]) -> String {
        guard !WorkEngine.isFinished(cursor, in: sequence), let pass = sequence.pass(at: cursor.row) else { return "Every row worked" }
        // The dot separator becomes a comma, as `LookAheadLine.spoken` does, so VoiceOver does not read it.
        return [sideText(pass), ShapedRowText.caption(chart: chart, sequence: sequence, row: cursor.row),
                LookAheadLine.text(row: cursor.row, stretches: stretches, sequence: sequence, chart: chart)]
            .compactMap { $0 }.joined(separator: ". ").replacingOccurrences(of: " · ", with: ", ")
    }

    private var lookAheadLine: String? {
        finished ? nil : LookAheadLine.text(row: cursor.row, stretches: stretches, sequence: sequence, chart: chart)
    }

    /// What the whole view's control is called in each direction; nil once finished, when the band
    /// is locked to the whole chart and there is nothing to toggle.
    static func lookAheadActionName(mode: ChartBand.Mode, finished: Bool) -> String? {
        finished ? nil : mode == .band ? "Look ahead" : "Back to the row"
    }

    private func toggleMode() {
        guard !finished else { return }
        withAnimation { mode = mode == .band ? .whole : .band }
    }

    var body: some View {
        let c = content
        Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 14) {
                    VStack(spacing: 14) { header; panel(c); writtenLine; Spacer(minLength: 0); bar(c) }.frame(maxWidth: .infinity)
                    band(c).frame(maxWidth: .infinity)
                }
                .padding(.bottom, 16)
            } else {
                VStack(spacing: 14) { header; panel(c); writtenLine; band(c); bar(c) }
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
                        .onTapGesture(perform: toggleMode)
                        .onLongPressGesture(perform: onJump)
                    Text(finished ? "Every row worked" : Self.sideText(pass)).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                    if !finished, let caption = ShapedRowText.caption(chart: chart, sequence: sequence, row: cursor.row) {
                        Text(caption).font(Font.Heather.caption).foregroundStyle(Color.heather)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    // The look-ahead line (spec §4): how many more rows like this one, then what changes.
                    // At an accessibility size the whole sentence cannot fit on one line and the screen
                    // has no height to wrap it, so only the first clause is drawn (spec §6); the full
                    // sentence is still the header's spoken value and the look-ahead view has the rest.
                    if let line = lookAheadLine {
                        let shown = dynamicTypeSize.isAccessibilitySize ? (line.components(separatedBy: " · ").first ?? line) : line
                        Text(shown).font(Font.Heather.caption).foregroundStyle(Color.heather)
                            .lineLimit(1).minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.6 : 0.8)
                            .onTapGesture(perform: toggleMode)
                    }
                }
            }
            // One element: the row as its label, everything under it as its value (spec §4.3).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sequence.pass(at: cursor.row).map { "\($0.label) of \(sequence.passes.count)" } ?? "")
            .accessibilityValue(Self.headerValue(chart: chart, sequence: sequence, cursor: cursor, stretches: stretches))
            .accessibilityHint("Long press to jump to a row")
            .accessibilityAction(named: "Jump to row", onJump)
            .accessibilityActions {
                if let name = Self.lookAheadActionName(mode: mode, finished: finished) { Button(name, action: toggleMode) }
            }
            Spacer()
            // The whole view's visible control (spec §5.3), in the slot that was empty; nothing to
            // open once finished, when the band is already the whole chart.
            if let name = Self.lookAheadActionName(mode: mode, finished: finished) {
                Button(action: toggleMode) {
                    Image(systemName: "rectangle.grid.1x2").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink2)
                .accessibilityLabel(name)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The panel is the spoken element: one label, the on-deck line as its value, the actions as rotor actions (spec §6).
    private func panel(_ c: WorkPanelContent) -> some View {
        // A part of the sequence line jumps to that run, so a repetition can still be walked one
        // run at a time when the tap unit is the repetition (#81).
        WorkPanel(content: c, onSelectPart: { onJumpWithinRow($0, 0) })
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
            .accessibilityAction(named: perRepetition ? "Switch to one tap per run in repeats" : "Switch to one tap per repetition") { onSetPerRepetition(!perRepetition) }
            .accessibilityAction(named: "Chart: \(bandStyle.other.title.lowercased())") { onSetBandStyle(bandStyle.other) }
            // The chart-free path to what is ahead (spec §4.3): the line, then the next two stretches;
            // "Every row worked" once finished. Offered only when there is something to say.
            .accessibilityActions {
                if let spoken = finished ? "Every row worked." : LookAheadLine.spoken(row: cursor.row, stretches: stretches, sequence: sequence, chart: chart) {
                    Button("What's ahead") { AccessibilityNotification.Announcement(spoken).post() }
                }
            }
    }

    private func band(_ c: WorkPanelContent) -> some View {
        // Finished: the whole chart solid, not the last row with a turn marker on it (spec §5.1).
        // The band is then locked to `.whole`, so its tap -- which returns from the whole chart --
        // has nowhere to go and closes, the same thing every other surface does when finished.
        ChartBand(chart: chart, sequence: sequence, cursor: cursor, segmentLabel: c.bandLabel, mode: finished ? .whole : mode, style: bandStyle,
                  onAdvance: finished ? onClose : onDone, onJump: onJumpWithinRow,
                  onToggleMode: finished ? onClose : toggleMode,
                  stretches: stretches,
                  returnLabel: finished ? nil : sequence.pass(at: cursor.row).map { "Back to \($0.label)" })
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
    }

    private func bar(_ c: WorkPanelContent) -> some View {
        let nextHex = sequence.pass(at: cursor.row + 1)?.runs.first.map { chart.palette[chart.colorIndex(of: $0.code) ?? 0].hex }
        let doneHex = c.kind == .turn ? (nextHex ?? WorkPanelContent.creamHex) : c.hex
        // Back can itself land on a boundary position (`run == runs.count`); clamp to that row's
        // last run so the capsule wears the colour it returns to rather than falling back to Cream.
        let prevHex = WorkEngine.apply(.back, to: cursor, in: sequence, step: step, perRepetition: perRepetition).flatMap { s in
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
                    Divider()
                    // The same menu for the other tap unit (#81): what a tap means in a repeat.
                    Button { onSetPerRepetition(!perRepetition) } label: {
                        if perRepetition { Label("One tap per repetition", systemImage: "checkmark") } else { Text("One tap per repetition") }
                    }
                    // Which way the band lays the chart out (#87): the experiment's switch, so it
                    // has to be reachable mid-row without leaving the screen.
                    Section("Chart") {
                        ForEach(BandStyle.allCases, id: \.rawValue) { s in
                            Button { onSetBandStyle(s) } label: {
                                if s == bandStyle { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 44)
    }

    /// The pattern's own words for the row, under the panel (spec §6.3): how the shaping is made.
    @ViewBuilder private var writtenLine: some View {
        if !finished, let text = ShapedRowText.written(chart: chart, row: cursor.row) {
            Text(text).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                .lineLimit(3).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }

    private static func sideText(_ pass: Pass) -> String {
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

extension View {
    /// Clear Liquid Glass over the yarn colour on iOS 26; a thin material over it before that.
    /// Shared with `WrittenWorkScreen`, whose bar wears the same capsules.
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
