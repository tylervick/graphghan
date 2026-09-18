import GraphghanCore

/// What sits under the current swatch (spec §6.1): the next run in the row, or the foundation at
/// the start; the turn is its own step.
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
        // At the very start the line is the foundation, when the chart states one (spec §6.4).
        if cursor == .start, let foundation = chart.foundation, let first = pass.runs.first {
            var text = "Chain \(foundation.chain)"
            if let into = foundation.firstStitchIn {
                let stitch = chart.stitch?.code ?? "stitch"
                text += ", first \(stitch) in the \(ordinal(into)) chain"
            }
            return OnDeck(text: text, hex: entry(first.code).hex)
        }
        if cursor.run + 1 < pass.runs.count {
            let next = pass.runs[cursor.run + 1]
            let e = entry(next.code)
            let noun = chart.cellKind == .stitch ? "" : " \(chart.cellKind.nounPlural)"
            return OnDeck(text: "then \(next.count) \(e.name)\(noun)", hex: e.hex)
        }
        return nil
    }

    /// 1 → "1st", 2 → "2nd", 11 → "11th", 22 → "22nd".
    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if (11...13).contains(tens) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}
