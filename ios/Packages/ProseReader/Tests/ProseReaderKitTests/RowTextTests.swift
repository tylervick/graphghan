import Testing
@testable import ProseReaderKit

@Test func blocksRejoinWrappedRowsAndSkipFooters() {
    let text = "Written rows\nRow 1 (RS): 189 Y (189 sts)\nRow 2 (WS): ch 1, turn, 2 Y, 3 G,\n4 Y (9 sts)\nCraigh Page 17\n"
    #expect(RowText.blocks(in: text) == ["Row 1 (RS): 189 Y (189 sts)", "Row 2 (WS): ch 1, turn, 2 Y, 3 G, 4 Y (9 sts)"])
}

@Test func orcaRowsAreFound() {
    let text = "Front Panel\nR 1 [←]: (Black) ch 10, from the second stitch from the hook, 9 sc [9]\nR 2 [→]: (Black) ch 1, turn, 1 inc, 7 sc, (White) 1 inc [11]\n"
    #expect(RowText.blocks(in: text).count == 2)
}

@Test func codes() {
    #expect(RowText.isCode("Gd") && RowText.isCode("A") && !RowText.isCode("White") && !RowText.isCode(""))
}

@available(macOS 26.0, *)
@Test func cleanRunsDropChainsMapNamesAndMergeNeighbours() {
    let runs = [RunOut(count: 1, code: "ch"), RunOut(count: 1, code: "turn"), RunOut(count: 9, code: "Black"),
                RunOut(count: 2, code: "White"), RunOut(count: 3, code: "White"), RunOut(count: 4, code: "Gd")]
    let out = RowText.cleanRuns(runs, key: ["black": "A", "white": "B"])
    let flat = out.map { pair -> (String, Int) in
        var code = "", count = 0
        for v in pair { switch v { case .code(let s): code = s; case .count(let n): count = n } }
        return (code, count)
    }
    #expect(flat.map(\.0) == ["A", "B", "Gd"] && flat.map(\.1) == [9, 5, 4])
}


@Test func longRowsAreCutIntoPartsThatKeepTheirHead() {
    let row = "Row 41 (RS): ch 1, turn, " + (1...20).map { "\($0) Y" }.joined(separator: ", ") + " (189 sts)"
    let parts = RowText.chunks(of: row, maxRuns: 8)
    #expect(parts.count == 3 && parts.allSatisfy { $0.hasPrefix("Row 41 (RS): ") } && parts.last!.hasSuffix("(189 sts)"))
    #expect(RowText.chunks(of: "Row 1 (RS): 189 Y (189 sts)", maxRuns: 8) == ["Row 1 (RS): 189 Y (189 sts)"])
    #expect(RowText.chunks(of: row, maxRuns: 0) == [row])
}


@Test func aLineHoldingTwoRowHeadsIsCutAndASentenceStartingWithRowIsNot() {
    let text = "Row 22 (WS): ch 1, turn, 2 Y, 3 G (5 sts) Row 23 (RS): ch 1, turn, 5 Y (5 sts)\nRow 1 starts at the bottom right; odd rows are RS and read right to left.\n189\n188\n"
    #expect(RowText.blocks(in: text) == ["Row 22 (WS): ch 1, turn, 2 Y, 3 G (5 sts)", "Row 23 (RS): ch 1, turn, 5 Y (5 sts)"])
    #expect(RowText.blocks(in: "Row 4 WS: (terra) x 18, (agave) x 86\nRow1: sc across in color 1\n").count == 2)
}


@Test func rowNumbersComeFromTheHeadAndIncreasesBecomeStitches() {
    #expect(RowText.rowNumber(of: "Row 1 (RS): 189 Y (189 sts)") == 1)
    #expect(RowText.rowNumber(of: "R 57 [←]: (Black) ch 1, turn, 9 sc [25]") == 57)
    #expect(RowText.rowNumber(of: "Total: 3673") == nil)
    #expect(RowText.normalized("R 2 [→]: (Black) ch 1, turn, 1 inc, 7 sc, (White) 1 inc [11]") == "R 2 [→]: (Black) 9 sc, (White) 2 sc [11]")
    #expect(RowText.normalized("R 57 [←]: 9 sc, (White) 15 sc, 1 dec [25]") == "R 57 [←]: 9 sc, (White) 16 sc [25]")
    #expect(RowText.normalized("R 1 [←]: (Black) ch 10, from the second stitch from the hook, 9 sc [9]") == "R 1 [←]: (Black) 9 sc [9]")
    #expect(RowText.normalized("Row 3 RS: (agave) x 85, (terra) x 19") == "Row 3 RS: (agave) x 85, (terra) x 19")
}


// #146: the corpus ends a row head with a colon, a period or a dash, writes "Rows 1-10", "1st row",
// and bare numbered lists; a sentence that merely starts with "Row 1" is still not a row.
@Test func headsEndInAColonAPeriodOrADash() {
    let text = "Row 1. Ch22 with yarn C1 (aqua). Beginning in 2nd ch from hook, sc in each ch.\nRow 2-4. Ch1, 21sc. Turn.\nRow 3 - Sc in first 2 sts, (P in nxt st, Sc in nxt 3 sts) 14 times.\nRow 5 – Sc in first 29 sts, Hsc in nxt 3 sts.\nRow 1 starts at the bottom right; odd rows are RS and read right to left.\n"
    let blocks = RowText.blocks(in: text)
    #expect(blocks.count == 4)
    #expect(blocks.map { RowText.rowNumber(of: $0) } == [1, 2, 3, 5])
}

@Test func pluralRangeAndOrdinalHeads() {
    let text = "Rows 1-10: Sc in each st across, turn.\nRows 2 & 3: Chain1, (12sc), Turn.\nRow 13-15: sc in c1.\n1st row: (RS) 1 hdc in 3rd ch from hook.\n23rd row: Beg block. (Block in next sp) 3 times with A.\n"
    let blocks = RowText.blocks(in: text)
    #expect(blocks.count == 5)
    #expect(blocks.map { RowText.rowNumber(of: $0) } == [1, 2, 13, 1, 23])
}

@Test func numberedListsAreRowsOnlyWhenTheyLookLikeRuns() {
    let text = "Increasing rows:\n1. 1G\n7. 2G, 3R, 2G\n12. (w) x 1, (DB) x 3, (gy) x 6\n1. You will use the C2C with the hdc, working the square on the diagonal.\n2. ↗ Uneven rows will be on the wrong side of work from bottom to top ↗.\n3. 4 hdc in next 4 sts, turn.\n"
    let blocks = RowText.blocks(in: text)
    #expect(blocks == ["1. 1G", "7. 2G, 3R, 2G", "12. (w) x 1, (DB) x 3, (gy) x 6"], "got \(blocks)")
    #expect(blocks.map { RowText.rowNumber(of: $0) } == [1, 7, 12])
}

@Test func headsAreRewrittenToOneFormBeforeThePrompt() {
    #expect(RowText.normalized("1st row: (RS) 1 hdc in 3rd ch from hook.") == "Row 1: (RS) 1 hdc in 3rd ch from hook.")
    #expect(RowText.normalized("7. 2G, 3R, 2G") == "Row 7: 2G, 3R, 2G")
    #expect(RowText.normalized("Row 1. 21sc with C1 (aqua).") == "Row 1: 21sc with C1 (aqua).")
    #expect(RowText.normalized("Row 3 - Sc in first 2 sts.") == "Row 3: Sc in first 2 sts.")
    #expect(RowText.normalized("Rows 1-10: Sc in each st across, turn.") == "Row 1-10: Sc in each st across, turn.")
    #expect(RowText.normalized("Row 6 (>>):(green) sc 10, (white) sc 3") == "Row 6 (>>): (green) sc 10, (white) sc 3")
    #expect(RowText.normalized("Row 12 (WS): 4 Y, 3 G") == "Row 12 (WS): 4 Y, 3 G")
    #expect(RowText.normalized("R 57 [←]: 9 sc, (White) 15 sc, 1 dec [25]") == "R 57 [←]: 9 sc, (White) 16 sc [25]")
}

@Test func chunksCutAtTheHeadTheRowRegexMatched() {
    let row = "Row 6 (>>):" + (1...17).map { "(green) sc \($0)" }.joined(separator: ", ")
    let parts = RowText.chunks(of: RowText.normalized(row), maxRuns: 8)
    #expect(parts.count == 3 && parts.allSatisfy { $0.hasPrefix("Row 6 (>>): ") })
    #expect(RowText.chunks(of: "Row 7: 2G, 3R, 2G", maxRuns: 2) == ["Row 7: 2G, 3R", "Row 7: 2G"])
}

@Test func rangeHeadsReportTheirFirstRow() {
    #expect(RowText.rowNumber(of: "Rows 2-10: Ch 1, sc in each st across, turn.") == 2)
    #expect(RowText.rowNumber(of: "Rows 24-32: With A, sc in each st across. Fasten off after Row 32.") == 24)
    #expect(RowText.rowNumber(of: "Rows 2-10:\u{00a0}Ch 1, sc in each st across, turn.") == 2)
}
