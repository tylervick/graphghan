import Testing
import GraphghanCore
import ProseReaderKit
@testable import Graphghan

@Suite struct FoundOutlineTests {
    static let pages = [
        "Materials\nhook",                                                               // 1
        "Front Back",                                                                    // 2: both charts
        "R 1: (Black) ch 7, 6 sc [6]\nR 2 - R 10: ch 1, turn, 6 sc [6]\nSide Panel",      // 3: 10 rows, so no 4-row chart pairs with it
        "R 1: ch 3, 2 sc [2]\nR 2: ch 1, turn, 2 sc [2]\nR 1: ch 2, 1 inc [2]\nR 2: ch 1, turn, 2 sc [2]\nDorsal Fin\nPectoral Fin (Front)", // 4
        "Sew the fins on",                                                               // 5
        "Lining and zipper",                                                             // 6
        "Front Panel\n" + (1...4).map { "R \($0): (Black) \($0) sc, (White) 1 sc [\($0 + 1)]" }.joined(separator: "\n"), // 7
        "Back Panel\n" + (1...4).map { "R \($0): (Black) \($0) sc, (White) 1 sc [\($0 + 1)]" }.joined(separator: "\n"),  // 8
    ]
    static let charts = [FoundChart(page: 2, x0: 100, cols: 5, rows: 4), FoundChart(page: 2, x0: 900, cols: 5, rows: 4)]
    static let palette: [ChartDraft.Palette] = [.init(code: "A", name: "black", hex: "#201b18"), .init(code: "B", name: "white", hex: "#ffffff")]
    static func outline() async -> PatternOutline {
        await FoundOutline().outline(pages: pages, found: FoundParts(charts: charts, sections: RowText.sections(in: pages), pageTexts: pages, palette: palette))
    }

    @Test func theFixtureSplitsAsItsCommentsSay() {
        let sections = RowText.sections(in: Self.pages)
        #expect(sections.map { $0.blocks.map(\.page) } == [[2, 2], [3, 3], [3, 3], [6, 6, 6, 6], [7, 7, 7, 7]])
        #expect(sections.map(\.lastRow) == [10, 2, 2, 4, 4] && sections[3].isColour && sections[4].isColour)
    }

    @Test func chartsPairWithTheirOwnRowsInOrder() async {
        let o = await Self.outline()
        let charts = o.pieces.filter { if case .chart = $0.kind { true } else { false } }
        #expect(charts.map(\.title) == ["Front Panel", "Back Panel"])
        #expect(charts.map(\.pairedSection) == [3, 4])   // sections: 0 side, 1 and 2 page 4, 3 front, 4 back
    }

    @Test func writtenPiecesTakeTheirPagesHeadingsInOrder() async {
        let o = await Self.outline()
        #expect(o.pieces.map(\.title) == ["Front Panel", "Back Panel", "Side Panel", "Dorsal Fin", "Pectoral Fin (Front)"])
        #expect(o.pieces[2].entries.map(\.to) == [1, 10])
    }

    @Test func unusedPagesAfterTheFirstPieceAreAssembly() async {
        #expect(await Self.outline().assembly == [AssemblyOutline(title: "Pages 5–6", text: nil, pages: [5, 6])])
    }

    @Test func headingsSkipProseAndRunningHeaders() {
        #expect(PageHeadings.isHeading("Pectoral Fin (Front)") && PageHeadings.isHeading("Tail") && PageHeadings.isHeading("Side Panel"))
        #expect(!PageHeadings.isHeading("Edging with sc along the side") && !PageHeadings.isHeading("C B A") && !PageHeadings.isHeading("Row 3")
                && !PageHeadings.isHeading("Sew") && !PageHeadings.isHeading("jins.crochetory"))
        #expect(PageHeadings.headings(in: ["Contents\nFront Panel", "Contents\nBack Panel"]) == [["Front Panel"], ["Back Panel"]])
    }

    @Test func aChartWithoutRowsIsNamedByPage() async {
        let o = await FoundOutline().outline(pages: ["x", "y"], found: FoundParts(charts: [FoundChart(page: 2, x0: 0, cols: 9, rows: 9)],
                                                                               sections: [], pageTexts: ["x", "y"], palette: []))
        #expect(o.pieces.map(\.title) == ["Chart 1 (page 2)"] && o.pieces[0].pairedSection == nil)
    }
}
