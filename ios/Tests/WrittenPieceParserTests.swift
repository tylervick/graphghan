import Testing
import GraphghanCore
import ProseReaderKit
@testable import Graphghan

@Suite struct WrittenPieceParserTests {
    static let palette: [ChartDraft.Palette] = [.init(code: "A", name: "black", hex: "#201b18"), .init(code: "B", name: "white", hex: "#ffffff")]
    static func section(_ page: String) -> RowSection { RowText.sections(in: [page])[0] }

    @Test func rangesCountsAndColoursParse() {
        let s = Self.section("R 1: (Black) ch 7, from the second stitch from the hook, 6 sc [6]\nR 2 - R 26: ch 1, turn, 6 sc [6]\nR 27 - 86: (White) ch 1, turn, 6 sc [6]")
        let p = WrittenPieceParser.parse(s, palette: Self.palette)
        #expect(p.entries == [
            .init(label: "R 1", from: 1, to: 1, text: "(Black) ch 7, from the second stitch from the hook, 6 sc [6]", count: 6, code: "A", repeatText: nil),
            .init(label: "R 2 - R 26", from: 2, to: 26, text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, repeatText: nil),
            .init(label: "R 27 - 86", from: 27, to: 86, text: "(White) ch 1, turn, 6 sc [6]", count: 6, code: "B", repeatText: nil),
        ])
        #expect(p.pages == [1] && p.stoppedAtPage == nil && p.stoppedAfterRow == nil)
    }

    @Test func aHeadThatGoesBackwardsStopsTheParse() {
        let s = Self.section("R 1: 6 sc [6]\nR 2 - R 4: ch 1, turn, 6 sc [6]\nsew around the head to R 8. Later, add a zipper")
        let p = WrittenPieceParser.parse(s, palette: [])
        #expect(p.entries.map(\.to) == [1, 4] && p.stoppedAtPage == 1 && p.stoppedAfterRow == 4)
    }

    @Test func aColourTheKeyDoesNotNameHasNoCode() {
        let p = WrittenPieceParser.parse(Self.section("R 1: (Pink) 3 sc [3]"), palette: Self.palette)
        #expect(p.entries[0].code == nil && p.entries[0].count == 3)
    }

    @Test func aCountBelowOneIsNoCount() {
        #expect(WrittenPieceParser.parse(Self.section("R 1: (Black) 6 sc [0]"), palette: Self.palette).entries[0].count == nil)
    }

    @Test func aCountMayEndWithAPeriodButNotSitMidRow() {
        #expect(WrittenPieceParser.parse(Self.section("R 1: 6 sc [6]."), palette: []).entries[0].count == 6)
        #expect(WrittenPieceParser.parse(Self.section("R 1: 6 sc [6], then turn"), palette: []).entries[0].count == nil)
    }
}
