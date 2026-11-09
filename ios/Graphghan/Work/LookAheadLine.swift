import GraphghanCore

/// The header's look-ahead line (look-ahead spec §4): how many more rows like this one, then
/// what changes. Pure, so every row is a value test. Says what differs ("Cream joins"), never
/// what the texture is called, because the chart states the one and not the other.
enum LookAheadLine {
    /// Titles longer than this say "the blanket" (spec §4.2, builder's call).
    static let titleLimit = 24

    /// The header line; nil for one stretch, the finished state, or the last row of the last stretch.
    static func text(row: Int, stretches: [Stretch], sequence: WorkSequence, chart: Chart) -> String? {
        guard stretches.count > 1, let i = Stretches.index(containing: row, in: stretches) else { return nil }
        let s = stretches[i]
        let left = s.rows.upperBound - row
        let next = i + 1 < stretches.count ? stretches[i + 1] : nil
        let head: String
        switch left {
        case 0: head = "Last row like this"
        case 1: head = "1 more row like this"
        default: head = "\(left) more rows like this"
        }
        guard let next else {
            return left == 0 ? nil : "\(head) · \(ending(title: chart.title))"
        }
        let count = next.rows.count
        return "\(head) · then \(change(from: s, to: next, sequence: sequence, chart: chart)) for \(count) \(count == 1 ? "row" : "rows")"
    }

    /// "then <title> is done", or "then the blanket is done" when the title is empty or over `titleLimit`.
    static func ending(title: String) -> String { "then \(blanketName(title: title)) is done" }

    /// The title when it is short enough to say, else "the blanket".
    static func blanketName(title: String) -> String {
        title.isEmpty || title.count > titleLimit ? "the blanket" : title
    }

    /// What differs between `s` and `next`, in the spec's order: the kind when it changes, else the
    /// first colour (in palette order) that joins, else the first that leaves, else the run count.
    static func change(from s: Stretch, to next: Stretch, sequence: WorkSequence, chart: Chart) -> String {
        if next.kind == .plain, s.kind != .plain { return "plain rows" }
        if next.kind == .repeat, s.kind != .repeat { return "the repeat rows" }
        let before = Set(s.colours), after = Set(next.colours)
        let palette = chart.palette.map(\.code)
        if let joins = palette.first(where: { after.contains($0) && !before.contains($0) }) { return "\(name(joins, chart: chart)) joins" }
        if let ends = palette.first(where: { before.contains($0) && !after.contains($0) }) { return "\(name(ends, chart: chart)) ends" }
        let from = sequence.pass(at: s.rows.upperBound)?.runs.count ?? 0
        let to = sequence.pass(at: next.rows.lowerBound)?.runs.count ?? 0
        return to > from ? "busier rows" : "simpler rows"
    }

    /// "Rows 15 to 16, 2 plain rows." / "Rows 17 to 20, 4 rows in Deep Green and Gold." / "Row 41, 1 row in …".
    static func sentence(for stretch: Stretch, chart: Chart) -> String {
        let rows = stretch.rows
        let range = rows.count == 1 ? "Row \(rows.lowerBound)" : "Rows \(rows.lowerBound) to \(rows.upperBound)"
        let noun: String
        switch stretch.kind {
        case .plain: noun = rows.count == 1 ? "plain row" : "plain rows"
        case .repeat: noun = rows.count == 1 ? "repeat row" : "repeat rows"
        case .pattern: noun = rows.count == 1 ? "row" : "rows"
        }
        let names = stretch.colours.map { name($0, chart: chart) }
        let colours: String
        switch names.count {
        case 0: colours = ""
        case 1: colours = " in \(names[0])"
        default: colours = " in \(names.dropLast().joined(separator: ", ")) and \(names.last!)"
        }
        return "\(range), \(rows.count) \(noun)\(colours)."
    }

    /// `text` followed by `sentence` for the next two stretches; for the rotor action (spec §4.3).
    /// The dot separator becomes a comma so VoiceOver does not read it. Where the header shows no
    /// line it still answers: a one-stretch chart counts down to the end, and the last row of
    /// the last stretch says so. Nil only without stretches or a row.
    static func spoken(row: Int, stretches: [Stretch], sequence: WorkSequence, chart: Chart) -> String? {
        guard let i = Stretches.index(containing: row, in: stretches) else { return nil }
        let lead: String
        if let line = text(row: row, stretches: stretches, sequence: sequence, chart: chart) {
            lead = line.replacingOccurrences(of: " · ", with: ", ") + "."
        } else {
            let left = stretches[i].rows.upperBound - row
            switch left {
            case 0: lead = "Last row of \(blanketName(title: chart.title))."
            case 1: lead = "1 more row like this, \(ending(title: chart.title))."
            default: lead = "\(left) more rows like this, \(ending(title: chart.title))."
            }
        }
        let ahead = stretches.dropFirst(i + 1).prefix(2).map { sentence(for: $0, chart: chart) }
        return ([lead] + ahead).joined(separator: " ")
    }

    private static func name(_ code: String, chart: Chart) -> String {
        chart.colorIndex(of: code).map { chart.palette[$0].name } ?? code
    }
}
