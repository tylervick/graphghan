import GraphghanCore

/// Everything the panel shows for one cursor position, computed once and rendered by `WorkPanel`
/// (spec §5.2). Pure, so every state is a value test.
struct WorkPanelContent: Equatable {
    enum Kind: Equatable { case run, braid, `repeat`, fill, turn, finished }
    enum PartState: Equatable { case done, current, upcoming }
    struct Part: Equatable { let text: String; let state: PartState }

    let kind: Kind
    let hex: String
    let count: Int?
    let total: Int?
    let badge: String?
    let code: String?
    let name: String?
    let segmentLabel: String?
    /// The band's bracket label. It names the repeat by its unit where the panel's caption names
    /// the segment: "×22 · 3 of 22" against "repeat · 3 of 22" (spec §5.3).
    let bandLabel: String?
    let parts: [Part]
    let repetitions: Int?
    let landmark: String?
    let onDeck: String?
    /// The segment spelled out for VoiceOver -- counts with colour names, the current run marked --
    /// because the band that draws it is `accessibilityHidden` (spec §6). Nil where there is no
    /// segment line to read.
    let spokenValue: String?
    let title: String?
    let subtitle: String?
    let detail: String?
    let actionLabel: String
    let capsule: String

    /// The turn and finished surfaces. Lives in `YarnSurface` because `Work/` may not hold a raw hex (DesignRulesTests).
    static let creamHex = YarnSurface.creamHex

    static func make(chart: Chart, sequence: WorkSequence, cursor: Cursor, step: CountStep) -> WorkPanelContent {
        if WorkEngine.isFinished(cursor, in: sequence) {
            return WorkPanelContent(kind: .finished, hex: creamHex, count: nil, total: nil, badge: nil, code: nil, name: nil,
                                    segmentLabel: nil, bandLabel: nil, parts: [], repetitions: nil, landmark: nil, onDeck: nil, spokenValue: nil,
                                    title: "Finished", subtitle: "Every row is done. Block it, weave in the ends, and take a picture.", detail: nil,
                                    actionLabel: "Close", capsule: "Close")
        }
        guard let pass = sequence.pass(at: cursor.row) else {
            return WorkPanelContent(kind: .finished, hex: creamHex, count: nil, total: nil, badge: nil, code: nil, name: nil, segmentLabel: nil,
                                    bandLabel: nil, parts: [], repetitions: nil, landmark: nil, onDeck: nil, spokenValue: nil,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: "Close", capsule: "Close")
        }
        func entry(_ code: String) -> ChartDocument.PaletteEntry { chart.palette[chart.colorIndex(of: code) ?? 0] }
        // `gauge.stitch` can be stated for gauge math alone on a non-stitch cellKind (filet-blocks
        // states "sc" while counting blocks); withhold it here too, same as the numbers it names (#44).
        let stitch = chart.cellKind == .stitch ? chart.stitch : nil
        let stitchName = stitch.map { $0.name ?? $0.code }

        if cursor.run >= pass.runs.count {
            let next = sequence.pass(at: cursor.row + 1)
            let nextName = next?.runs.first.map { entry($0.code).name }
            // Only what the next pass actually states: a chart that omits the side or the reading
            // direction gets silence, not a confident "Right side" it never claimed.
            let side = next?.side.map { $0 == .ws ? "Wrong side" : "Right side" }
            let direction = next?.direction.map { $0 == .ltr ? "read left to right" : "read right to left" }
            let facing = [side, direction].compactMap { $0 }
            let title = boundaryTitle(chart: chart, nextColorName: nextName)
            let detail = nextName.map { "Row \(cursor.row + 1) starts in \($0)" }
            return WorkPanelContent(kind: .turn, hex: creamHex, count: nil, total: nil, badge: nil, code: nil, name: nil, segmentLabel: nil,
                                    bandLabel: nil, parts: [], repetitions: nil, landmark: nil, onDeck: nil, spokenValue: nil,
                                    title: title, subtitle: facing.isEmpty ? nil : facing.joined(separator: " · "), detail: detail,
                                    actionLabel: [title, facing.isEmpty ? nil : facing.joined(separator: ", "), detail].compactMap { $0 }.joined(separator: ". "), capsule: "Turned")
        }

        let run = pass.runs[cursor.run]
        let e = entry(run.code)
        let segment = Segments.segment(containing: cursor.run, in: pass)
        let onDeck = OnDeckRule.onDeck(cursor: cursor, chart: chart, sequence: sequence)?.text
        let noun = stitchName ?? (chart.cellKind == .stitch ? "" : chart.cellKind.nounPlural)
        // The stitch name when the chart states one; otherwise the cell kind's plural noun when
        // cells aren't stitches; otherwise no noun at all (same rule as `OnDeckRule`, #44).
        func label(_ n: Int) -> String { noun.isEmpty ? "Done with \(n) \(e.name)" : "Done with \(n) \(noun) in \(e.name)" }

        switch segment?.kind {
        case .fill:
            // This is the fill segment, so `WorkEngine.isCounting` is true by construction here.
            let capsule = step == .wholeRun ? "checkmark" : "+\(WorkEngine.stride(step, for: run))"
            let below = sequence.pass(at: cursor.row - 1)
            let landmark = Segments.landmark(for: run, direction: pass.direction, below: below).map { landmarkText($0, chart: chart) }
            // The fixed steps are spelled out, so VoiceOver says "next ten" rather than "next 10";
            // the whole-run step counts down a remainder, which is a number, not a word.
            let nextWord = step == .wholeRun ? "next \(run.count - cursor.stitch)" : "next \(step.spelled)"
            let action = ["\(cursor.stitch) of \(run.count)", noun.isEmpty ? nil : noun, "in \(e.name), \(nextWord)"].compactMap { $0 }.joined(separator: " ")
            return WorkPanelContent(kind: .fill, hex: e.hex, count: cursor.stitch, total: run.count, badge: stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: nil, bandLabel: nil, parts: [], repetitions: nil, landmark: landmark, onDeck: onDeck, spokenValue: nil,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: action, capsule: capsule)
        case .braid:
            let parts = segment!.runs.map { i -> Part in
                let r = pass.runs[i]
                return Part(text: "\(r.count)\(r.code)", state: i < cursor.run ? .done : i == cursor.run ? .current : .upcoming)
            }
            let spoken = segment!.runs.map { i -> String in
                let r = pass.runs[i]
                return "\(r.count) \(entry(r.code).name)\(i == cursor.run ? " (current)" : "")"
            }
            return WorkPanelContent(kind: .braid, hex: e.hex, count: run.count, total: nil, badge: stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: "border braid", bandLabel: "border braid", parts: parts, repetitions: nil, landmark: nil, onDeck: onDeck,
                                    spokenValue: "border braid: \(spoken.joined(separator: ", "))",
                                    title: nil, subtitle: nil, detail: nil, actionLabel: label(run.count), capsule: "checkmark")
        case .repeat:
            let seg = segment!
            let which = Segments.repetition(of: cursor.run, in: seg) ?? 0
            let position = (cursor.run - seg.runs.lowerBound) % seg.period
            let parts = (0..<seg.period).map { j -> Part in
                let r = pass.runs[seg.runs.lowerBound + j]
                return Part(text: "\(r.count) \(r.code)", state: j < position ? .done : j == position ? .current : .upcoming)
            }
            let spoken = (0..<seg.period).map { j -> String in
                let r = pass.runs[seg.runs.lowerBound + j]
                return "\(r.count) \(entry(r.code).name)\(j == position ? " (current)" : "")"
            }
            return WorkPanelContent(kind: .repeat, hex: e.hex, count: run.count, total: nil, badge: stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: "repeat · \(which + 1) of \(seg.repetitions)", bandLabel: "×\(seg.repetitions) · \(which + 1) of \(seg.repetitions)",
                                    parts: parts, repetitions: seg.repetitions, landmark: nil, onDeck: onDeck,
                                    spokenValue: "repeat \(which + 1) of \(seg.repetitions): \(spoken.joined(separator: ", "))",
                                    title: nil, subtitle: nil, detail: nil, actionLabel: label(run.count), capsule: "checkmark")
        default:
            return WorkPanelContent(kind: .run, hex: e.hex, count: run.count, total: nil, badge: stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: nil, bandLabel: nil, parts: [], repetitions: nil, landmark: nil, onDeck: onDeck, spokenValue: nil,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: label(run.count), capsule: "checkmark")
        }
    }

    /// "ends 7 past where Purple starts below" / "ends 2 before …" / "ends where the Purple starts below".
    static func landmarkText(_ landmark: Landmark, chart: Chart) -> String {
        let name = chart.palette[chart.colorIndex(of: landmark.code) ?? 0].name
        if landmark.offset == 0 { return "ends where the \(name) starts below" }
        return "ends \(abs(landmark.offset)) \(landmark.offset > 0 ? "past" : "before") where \(name) starts below"
    }

    /// The boundary step's title from what the chart states (spec §4.4).
    static func boundaryTitle(chart: Chart, nextColorName: String?) -> String {
        guard let boundary = chart.stitch?.boundary, boundary.kind == .turn, boundary.chain > 0 else { return "Turn" }
        var title: String
        if boundary.color == .next, let name = nextColorName {
            title = "Ch \(boundary.chain) in \(name), turn"
        } else {
            title = "Ch \(boundary.chain), turn"
        }
        if boundary.countsAsStitch { title += " (counts as a st)" }
        return title
    }
}

extension CountStep {
    /// The step as a word, for the spoken action label ("next ten"). `wholeRun` has no fixed size,
    /// so it names the remainder instead and never asks for this.
    var spelled: String {
        switch self {
        case .one: "one"
        case .five: "five"
        case .ten: "ten"
        case .twenty: "twenty"
        case .wholeRun: ""
        }
    }
}
