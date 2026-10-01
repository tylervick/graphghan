import GraphghanCore
import ProseReaderKit

// What a pattern PDF holds, as pieces and assembly steps, before the maker sees it (pieces spec
// §7). Code fills it from what it found (`FoundOutline`); a better reader (#200) can fill the same
// list another way behind `PieceReading`, and the review list and the save do not change.

/// A chart region found on a page: its page (1-based), its left edge in the page image, and its size.
struct FoundChart: Sendable, Equatable {
    let page: Int
    let x0: Int
    let cols: Int
    let rows: Int
}

/// Everything code found in the PDF before anything is offered (spec §7.1).
struct FoundParts: Sendable {
    /// In reading order: page, then left to right.
    let charts: [FoundChart]
    /// `RowText.sections`, in document order.
    let sections: [RowSection]
    let pageTexts: [String]
    /// The first chart's palette, for a written row's "(Name)" → code.
    let palette: [ChartDraft.Palette]
}

enum PieceKind: Sendable, Equatable {
    /// An index into `FoundParts.charts`.
    case chart(Int)
    /// An index into `FoundParts.sections`.
    case rows(Int)
}

struct PieceOutline: Sendable, Equatable {
    var title: String
    var kind: PieceKind
    var make: Int
    /// 1-based.
    var pages: [Int]
    /// For a chart piece: the section of its own rows (spec §7.2), nil when none matched.
    var pairedSection: Int?
    /// For a written piece: its parsed rows; empty for a chart.
    var entries: [RowsDocument.Entry]
}

struct AssemblyOutline: Sendable, Equatable {
    var title: String
    var text: String?
    var pages: [Int]
}

struct PatternOutline: Sendable, Equatable {
    var pieces: [PieceOutline]
    var assembly: [AssemblyOutline]
    /// What was found and not offered, said in the sheet so the maker knows (spec §7.2).
    var leftOut: [String]
}

/// Where a better reader (#200) plugs in: the same list, filled differently.
protocol PieceReading: Sendable {
    func outline(pages: [String], found: FoundParts) async -> PatternOutline
}
