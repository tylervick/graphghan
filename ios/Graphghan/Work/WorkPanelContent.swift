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
    let parts: [Part]
    let repetitions: Int?
    let landmark: String?
    let onDeck: String?
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
                                    segmentLabel: nil, parts: [], repetitions: nil, landmark: nil, onDeck: nil,
                                    title: "Finished", subtitle: "Every row is done. Block it, weave in the ends, and take a picture.", detail: nil,
                                    actionLabel: "Close", capsule: "Close")
        }
        guard let pass = sequence.pass(at: cursor.row) else {
            return WorkPanelContent(kind: .finished, hex: creamHex, count: nil, total: nil, badge: nil, code: nil, name: nil, segmentLabel: nil,
                                    parts: [], repetitions: nil, landmark: nil, onDeck: nil, title: nil, subtitle: nil, detail: nil, actionLabel: "Close", capsule: "Close")
        }
        func entry(_ code: String) -> ChartDocument.PaletteEntry { chart.palette[chart.colorIndex(of: code) ?? 0] }
        let stitchName = chart.stitch.map { $0.name ?? $0.code }

        if cursor.run >= pass.runs.count {
            let next = sequence.pass(at: cursor.row + 1)
            let nextName = next?.runs.first.map { entry($0.code).name }
            let side = next?.side == .ws ? "Wrong side" : "Right side"
            let direction = next?.direction == .ltr ? "read left to right" : "read right to left"
            let title = boundaryTitle(chart: chart, nextColorName: nextName)
            let detail = nextName.map { "Row \(cursor.row + 1) starts in \($0)" }
            return WorkPanelContent(kind: .turn, hex: creamHex, count: nil, total: nil, badge: nil, code: nil, name: nil, segmentLabel: nil,
                                    parts: [], repetitions: nil, landmark: nil, onDeck: nil,
                                    title: title, subtitle: "\(side) · \(direction)", detail: detail,
                                    actionLabel: [title, "\(side), \(direction)", detail].compactMap { $0 }.joined(separator: ". "), capsule: "Turned")
        }

        let run = pass.runs[cursor.run]
        let e = entry(run.code)
        let segment = Segments.segment(containing: cursor.run, in: pass)
        let onDeck = OnDeckRule.onDeck(cursor: cursor, chart: chart, sequence: sequence)?.text
        let noun = stitchName ?? (chart.cellKind == .stitch ? "" : chart.cellKind.nounPlural)
        func label(_ n: Int) -> String { ["Done with \(n)", stitchName, "in \(e.name)"].compactMap { $0 }.joined(separator: " ") }

        switch segment?.kind {
        case .fill:
            let counting = WorkEngine.isCounting(cursor, in: sequence)
            let stride = WorkEngine.stride(step, for: run)
            let capsule = step == .wholeRun || !counting ? "checkmark" : "+\(stride)"
            let below = sequence.pass(at: cursor.row - 1)
            let landmark = Segments.landmark(for: run, direction: pass.direction, below: below).map { landmarkText($0, chart: chart) }
            let nextWord = step == .wholeRun ? "next \(run.count - cursor.stitch)" : "next \(stride == 10 ? "ten" : String(stride))"
            let action = "\(cursor.stitch) of \(run.count) \(noun.isEmpty ? "" : noun + " ")in \(e.name), \(nextWord)".replacingOccurrences(of: "  ", with: " ")
            return WorkPanelContent(kind: .fill, hex: e.hex, count: cursor.stitch, total: run.count, badge: chart.stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: nil, parts: [], repetitions: nil, landmark: landmark, onDeck: onDeck,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: action, capsule: capsule)
        case .braid:
            let parts = segment!.runs.map { i -> Part in
                let r = pass.runs[i]
                return Part(text: "\(r.count)\(r.code)", state: i < cursor.run ? .done : i == cursor.run ? .current : .upcoming)
            }
            return WorkPanelContent(kind: .braid, hex: e.hex, count: run.count, total: nil, badge: chart.stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: "border braid", parts: parts, repetitions: nil, landmark: nil, onDeck: onDeck,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: label(run.count), capsule: "checkmark")
        case .repeat:
            let seg = segment!
            let which = Segments.repetition(of: cursor.run, in: seg) ?? 0
            let position = (cursor.run - seg.runs.lowerBound) % seg.period
            let parts = (0..<seg.period).map { j -> Part in
                let r = pass.runs[seg.runs.lowerBound + j]
                return Part(text: "\(r.count) \(r.code)", state: j < position ? .done : j == position ? .current : .upcoming)
            }
            return WorkPanelContent(kind: .repeat, hex: e.hex, count: run.count, total: nil, badge: chart.stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: "repeat · \(which + 1) of \(seg.repetitions)", parts: parts, repetitions: seg.repetitions, landmark: nil, onDeck: onDeck,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: label(run.count), capsule: "checkmark")
        default:
            return WorkPanelContent(kind: .run, hex: e.hex, count: run.count, total: nil, badge: chart.stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: nil, parts: [], repetitions: nil, landmark: nil, onDeck: onDeck,
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
