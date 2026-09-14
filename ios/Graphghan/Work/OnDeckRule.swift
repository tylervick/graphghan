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
            return OnDeck(text: "then \(next.count) \(e.name)", hex: e.hex)
        }
        if let nextPass = sequence.pass(at: cursor.row + 1), let first = nextPass.runs.first {
            let e = entry(first.code)
            var text = "next row starts in \(e.name)"
            // Only a `turn` boundary changes the line; other kinds are for later readers (spec §6.1).
            if let boundary = chart.stitch?.boundary, boundary.kind == .turn {
                let chain: String
                if boundary.chain > 0 {
                    chain = boundary.color == .next ? "ch \(boundary.chain) in \(e.name), turn" : "ch \(boundary.chain), turn"
                } else {
                    chain = "turn"
                }
                text = "\(chain) — \(text)"
                if boundary.countsAsStitch { text += " (counts as a st)" }
            }
            return OnDeck(text: text, hex: e.hex)
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
