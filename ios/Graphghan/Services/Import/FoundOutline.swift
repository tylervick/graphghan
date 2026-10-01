import GraphghanCore
import ProseReaderKit

/// The outline code builds from what it found, with no model (pieces spec §7): charts paired with
/// their own rows, the other row sections as written pieces, titles from the pages' headings, the
/// pages no piece uses as assembly, and what a parse stopped short of as left out.
struct FoundOutline: PieceReading {
    func outline(pages: [String], found: FoundParts) async -> PatternOutline {
        let titles = Self.sectionTitles(found.sections, headings: PageHeadings.headings(in: pages))
        let chartOrder = found.charts.indices.sorted { (found.charts[$0].page, found.charts[$0].x0) < (found.charts[$1].page, found.charts[$1].x0) }
        let pairs = Self.pairs(charts: found.charts, order: chartOrder, sections: found.sections)
        var pieces: [(piece: PieceOutline, order: (Int, Int))] = []
        for i in chartOrder {
            let chart = found.charts[i]
            let paired = pairs[i]
            let rowPages = paired.map { found.sections[$0].blocks.map { $0.page + 1 } } ?? []
            let title = paired.flatMap { titles[$0] } ?? "Chart \(i + 1) (page \(chart.page))"
            pieces.append((PieceOutline(title: title, kind: .chart(i), make: 1, pages: Array(Set([chart.page] + rowPages)).sorted(),
                                        pairedSection: paired, entries: []), (0, i)))
        }
        var leftOut: [String] = []
        let pairedSections = Set(pairs.values)
        for (s, section) in found.sections.enumerated() where !pairedSections.contains(s) {
            let parsed = WrittenPieceParser.parse(section, palette: found.palette)
            guard let last = parsed.entries.last?.to, let first = parsed.pages.first else { continue }
            if let page = parsed.stoppedAtPage, let row = parsed.stoppedAfterRow { leftOut.append("text after R \(row) (page \(page))") }
            let title = titles[s] ?? "Rows, page \(first), R 1–\(last)"
            pieces.append((PieceOutline(title: title, kind: .rows(s), make: 1, pages: parsed.pages, pairedSection: nil, entries: parsed.entries), (1, s)))
        }
        // By first page; on one page charts before written pieces; then reading or document order.
        let sorted = pieces.sorted { a, b in
            let pa = a.piece.pages.first ?? 0, pb = b.piece.pages.first ?? 0
            return (pa, a.order.0, a.order.1) < (pb, b.order.0, b.order.1)
        }.map(\.piece)
        return PatternOutline(pieces: sorted, assembly: Self.assembly(pieces: sorted, pageCount: pages.count), leftOut: leftOut)
    }

    /// Each section's title, by index: on each page, the k-th heading titles the k-th section that
    /// starts there (a section starts on the page of its first block).
    static func sectionTitles(_ sections: [RowSection], headings: [[String]]) -> [Int: String] {
        var titles: [Int: String] = [:]
        var startedOn: [Int: Int] = [:]
        for (s, section) in sections.enumerated() {
            guard let page = section.blocks.first?.page else { continue }
            let k = startedOn[page, default: 0]
            startedOn[page] = k + 1
            if page < headings.count, k < headings[page].count { titles[s] = headings[page][k] }
        }
        return titles
    }

    /// Chart index → its section (spec §7.2): the colour sections whose last row is a chart's height,
    /// in document order, go to the charts of that height in reading order, k-th to k-th. Orca's two
    /// 77-row panels print in the order its page draws them.
    static func pairs(charts: [FoundChart], order: [Int], sections: [RowSection]) -> [Int: Int] {
        var unused = sections.indices.filter { sections[$0].isColour }
        var out: [Int: Int] = [:]
        for i in order {
            guard let at = unused.firstIndex(where: { sections[$0].lastRow == charts[i].rows }) else { continue }
            out[i] = unused.remove(at: at)
        }
        return out
    }

    /// The pages after the first page any piece uses that no piece uses, one step per run of
    /// consecutive pages: where a pattern says how the pieces go together.
    static func assembly(pieces: [PieceOutline], pageCount: Int) -> [AssemblyOutline] {
        let used = Set(pieces.flatMap(\.pages))
        guard let first = used.min(), first < pageCount else { return [] }
        var runs: [[Int]] = []
        for p in (first + 1)...pageCount where !used.contains(p) {
            if let last = runs.last?.last, last == p - 1 { runs[runs.count - 1].append(p) } else { runs.append([p]) }
        }
        return runs.map { run in
            AssemblyOutline(title: run.count == 1 ? "Page \(run[0])" : "Pages \(run[0])–\(run[run.count - 1])", text: nil, pages: run)
        }
    }
}
