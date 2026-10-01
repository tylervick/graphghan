import Testing
import GraphghanCore
@testable import Graphghan

/// The review list's editable draft (pieces spec §7.3): unique slugs, edits by position that
/// keep each piece's identity, and the single-chart fallback (§7.4, §7.5).
@Suite struct OutlineDraftTests {
    static func draft() -> OutlineDraft {
        let outline = PatternOutline(pieces: [
            PieceOutline(title: "Front Panel", kind: .chart(0), make: 1, pages: [9, 17], pairedSection: 7, entries: []),
            PieceOutline(title: "Strap", kind: .rows(1), make: 1, pages: [13], pairedSection: nil,
                         entries: [.init(label: "R 1", from: 1, to: 20, text: "6 sc", count: 6, code: nil, repeatText: nil)]),
            PieceOutline(title: "Strap", kind: .rows(2), make: 1, pages: [14], pairedSection: nil,
                         entries: [.init(label: "R 1", from: 1, to: 5, text: "6 sc", count: 6, code: nil, repeatText: nil)]),
        ], assembly: [AssemblyOutline(title: "Pages 13–16", text: nil, pages: [13, 14, 15, 16])], leftOut: [])
        return OutlineDraft(outline, charts: [])
    }

    /// Review focus 2.
    @Test func sameTitlesGetUniqueIDs() {
        #expect(Self.draft().pieceIDs() == [0: "front-panel", 1: "strap", 2: "strap-2"])
    }

    @Test func editsKeepIDsAndRespectOrder() {
        var d = Self.draft()
        d.rename(1, to: "Handle")
        d.setMake(2, 2); d.setMake(2, 0)
        d.move(fromOffsets: [2], toOffset: 0)
        #expect(d.pieces.map(\.id) == [2, 0, 1] && d.pieces[0].make == 1 && d.pieces[2].title == "Handle")
        d.remove(0)
        #expect(d.pieces.map(\.id) == [2, 1])
    }

    @Test func oneChartAloneIsSingle() {
        var d = Self.draft()
        #expect(!d.isSingleChart)
        d.remove(1); d.remove(2); d.removeStep(0)
        #expect(d.isSingleChart)
    }
}
