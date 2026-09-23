import Testing
@testable import ProseReaderKit

// Which written rows a chart's check reads (#176, #197, #198): a PDF carries more than one run of
// rows -- the panel the chart draws, the other panel, the bag's body and strap -- and only one of
// them is the chart's.

/// Orca's shape, cut down: a body of one colour, then two panels that both count from row 1.
let orcaLike = [
    "Body\nR 1: (Black) ch 7, from the second stitch from the hook, 6 sc [6]\nR 2: ch 1, turn, 12 sc, 1 dec [13]\nR 3: ch 1, turn, 1 dec, 11 sc [12]\n",
    "Front Panel\nR 1 [←]: (Black) ch 10, 9 sc [9]\nR 2 [→]: (Black) ch 1, turn, 1 inc, 7 sc, (White) 1 inc [11]\nR 3 [←]: (White) ch 1, turn, 1 inc, 1 sc, (Black) 8 sc, 1 inc [13]\n",
    "Back Panel\nR 1 [←]: (White) ch 10, 9 sc [9]\nR 2 [→]: (White) ch 1, turn, 1 inc, 7 sc, (Black) 1 inc [11]\nR 3 [←]: (Black) ch 1, turn, 1 inc, 1 sc, (White) 8 sc, 1 inc [13]\n",
]

/// The cactus blanket's page 1: c2c construction, the colour is all in the chart picture (#198).
let cactusLike = [
    "Beg = Begin(ning)\nSc = Single crochet\nWith MC and larger hook, ch 6.\n1st row: (RS) 1 dc in 4th ch from hook. 1 dc in each of next 2 ch. Turn. 1 block made.\n"
        + "2nd row: Ch 6. 1 dc in 4th ch from hook. 1 dc in each of next 2 ch - beg block made. (Sl st. Ch 3. 3 dc) in next ch-3 sp - block made. Turn. 2 blocks.\n"
        + "3rd row: Beg block. (Block in next ch-3 sp) twice. Turn. 3 blocks.\n",
]

@Test func sectionsStartWhereTheRowsCountFromOneAgain() {
    let sections = RowText.sections(in: orcaLike)
    #expect(sections.map(\.lastRow) == [3, 3, 3])
    #expect(sections.map { $0.blocks.map(\.page) } == [[0, 0, 0], [1, 1, 1], [2, 2, 2]])
}

@Test func aSectionRunsOnAcrossPagesUntilRowOneComesBack() {
    let pages = ["R 1: (Black) 9 sc\nR 2: (White) 9 sc\n", "R 3: (Black) 9 sc\n", "R 1: (Pink) 4 sc\n"]
    #expect(RowText.sections(in: pages).map { $0.blocks.map(\.page) } == [[0, 0, 1], [2]])
}

@Test func rowsThatNameAColourAreColourRowsAndShapingRowsAreNot() {
    #expect(RowText.namesColour("R 2 [→]: (Black) ch 1, turn, 1 inc, 7 sc, (White) 1 inc [11]"))
    #expect(RowText.namesColour("Row 4: 8 A, 14 B, 8 A"))
    #expect(RowText.namesColour("Row 7: W14, C8, W33"))
    #expect(RowText.namesColour("Row 3: sc 8 in white, sc 2 in green"))
    // The breadth measurement's other grammars (spec §9.1): code before count, "x", glued digits.
    #expect(RowText.namesColour("Row 4: Ch 1, A 23, B 1, A 12, B 1, A 9, turn."))
    #expect(RowText.namesColour("Row 13: Ch 1, A (7), B (1), A (10), turn."))
    #expect(RowText.namesColour("ROW 4 [LR]: White x 46, Black x 9, White x 15, turn"))
    #expect(RowText.namesColour("7. 2G, 3R, 2G"))
    #expect(RowText.namesColour("Row 7 - Sc in first 2 sts, P in nxt st, Sc in nxt 55 sts, P in nxt st. (2P, 59Sc), Ch1, turn."))
    #expect(!RowText.namesColour("Rows 4, 5 & 6 - Sc in all sts. (61Sc), Ch1, turn."))
    #expect(!RowText.namesColour("Row 3: ch4, hdc in third ch from hook, hdc in next ch, *ss into ch-2 sp on next block, ch2, 2hdc into same sp; rep from * to end, turn."))
    #expect(!RowText.namesColour("R 2: ch 1, turn, 12 sc, 1 dec [13]"))
    #expect(!RowText.namesColour("1st row: (RS) 1 dc in 4th ch from hook. 1 dc in each of next 2 ch. Turn. 1 block made."))
    #expect(!RowText.namesColour("3rd row: Beg block. (Block in next ch-3 sp) twice. Turn. 3 blocks."))
}

@Test func aBodyOfOneColourIsNotAColourSection() {
    let sections = RowText.sections(in: orcaLike)
    #expect(sections.map(\.isColour) == [false, true, true])
}

@Test func theChartsRowsAreTheFirstColourSectionAsTallAsTheChart() {
    let chosen = RowText.section(fitting: 3, in: orcaLike)
    #expect(chosen?.blocks.map(\.page) == [1, 1, 1])
}

@Test func withNoSectionAsTallAsTheChartTheLongestColourSectionIsRead() {
    let pages = ["R 1: (Black) 9 sc\nR 2: (White) 9 sc\n", "R 1: (Pink) 4 sc\nR 2: (Pink) 4 sc\nR 3: (Pink) 4 sc\n"]
    #expect(RowText.section(fitting: 40, in: pages)?.lastRow == 3)
}

@Test func constructionProseHasNoRowsToCheck() {
    #expect(RowText.sections(in: cactusLike).allSatisfy { !$0.isColour })
    #expect(RowText.section(fitting: 28, in: cactusLike) == nil)
}

@Test func aSectionCountsEveryRowItsRangeHeadsCover() {
    let pages = ["Row 1: 8 A, 2 B\nRows 2-4: 8 A, 2 B\nRow 5: 10 A\n"]
    #expect(RowText.sections(in: pages).map(\.rows) == [5])
}

@Test func aSectionHoldsItsOwnBlocksAndNoOther() {
    let front = RowText.section(fitting: 3, in: orcaLike)!
    #expect(front.contains(page: 1, index: 0) && front.contains(page: 1, index: 2))
    #expect(!front.contains(page: 0, index: 0) && !front.contains(page: 2, index: 0))
}
