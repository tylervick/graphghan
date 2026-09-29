import GraphghanCore

/// What the Work screen says about a shaped row beyond its runs (spec 2026-09-25 §6.3): how many
/// stitches it has and how it changed from the row before, and the pattern's own words for it.
enum ShapedRowText {
    /// "5 sts · +1 at start, +1 at end". Nil for a rectangle, whose every row is the chart's width
    /// and whose screen stays exactly as it was.
    static func caption(chart: Chart, sequence: WorkSequence, row: Int) -> String? {
        guard chart.isShaped, let pass = sequence.pass(at: row) else { return nil }
        let count = "\(pass.cells) \(sequence.totalStitches == nil ? "cells" : "sts")"
        return [count, sequence.shaping(at: row)?.sentence].compactMap { $0 }.joined(separator: " · ")
    }

    /// The pattern's printed text for pass `row`, when the chart carries `written`.
    static func written(chart: Chart, row: Int) -> String? {
        guard let written = chart.written, row >= 1, row <= written.count else { return nil }
        return written[row - 1]
    }
}
