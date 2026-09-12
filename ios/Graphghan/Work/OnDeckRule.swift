import GraphghanCore

/// What sits under the current swatch (spec §6.1): the next run, the next row's first color, or nothing.
struct OnDeck: Hashable {
    let text: String
    let hex: String
}

enum OnDeckRule {
    static func onDeck(cursor: Cursor, chart: Chart, sequence: WorkSequence) -> OnDeck? {
        guard let pass = sequence.pass(at: cursor.row) else { return nil }
        func entry(_ code: String) -> (name: String, hex: String) {
            let e = chart.palette[chart.colorIndex(of: code) ?? 0]
            return (e.name, e.hex)
        }
        if cursor.run + 1 < pass.runs.count {
            let next = pass.runs[cursor.run + 1]
            let e = entry(next.code)
            return OnDeck(text: "then \(next.count) \(e.name)", hex: e.hex)
        }
        if let nextPass = sequence.pass(at: cursor.row + 1), let first = nextPass.runs.first {
            let e = entry(first.code)
            return OnDeck(text: "next row starts in \(e.name)", hex: e.hex)
        }
        return nil
    }
}
