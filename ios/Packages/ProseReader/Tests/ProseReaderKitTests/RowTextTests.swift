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
    let text = "Row 1. Ch22 with yarn C1 (aqua). Beginning in 2nd ch from hook, sc in each ch.\nRow 2-4. Ch1, 21sc. Turn.\nRow 3 - Sc in first 2 sts, (P in nxt st, Sc in nxt 3 sts) 14 times.\nRow 5 – Sc in first 29 sts, Hsc in nxt 3 sts.\nRow 1 starts at the bottom right; odd rows are RS and read right to left.\nRow 1 starts here. Continue in the same colour to the end.\nRow 1-4 (main color - ecru): 25 sc\nRow 5-10 (left): ch1, sc across, turn.\n"
    let blocks = RowText.blocks(in: text)
    #expect(blocks.count == 6, "got \(blocks)")
    #expect(blocks.map { RowText.rowNumber(of: $0) } == [1, 2, 3, 5, 1, 5])
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
    #expect(RowText.normalized("Row 1. 21sc with C1 (aqua).") == "Row 1: 21sc with A (aqua).")
    #expect(RowText.normalized("Row 3 - Sc in first 2 sts.") == "Row 3: Sc in first 2 sts.")
    #expect(RowText.normalized("Rows 1-10: Sc in each st across, turn.") == "Row 1-10: Sc in each st across, turn.")
    #expect(RowText.normalized("Row 6 (>>):(green) sc 10, (white) sc 3") == "Row 6 (>>): 10 green, 3 white")
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

// #148: run spellings the model mishandles, rewritten to "N code" or "N name" before the prompt.
@Test func gluedCodesNumberedColoursAndBareNamesAreRewritten() {
    #expect(RowText.normalized("Row 15 [WS]: (dg) x 3, (gh) x 2, c2, w, c, gh, dg") == "Row 15 [WS]: (dg) x 3, (gh) x 2, 2 c, w, c, gh, dg")
    #expect(RowText.normalized("Row 13 [WS]: (lb) x 4, c2, (lb) x 7") == "Row 13 [WS]: (lb) x 4, 2 c, (lb) x 7")
    #expect(RowText.normalized("Row 4: Join in color 2 at start of row. 8sc in c1, 1sc in c2, 8sc in c1.") == "Row 4: Join in B at start of row. 8 A, 1 B, 8 A.")
    #expect(RowText.normalized("Row 6. Ch1, 6sc with C1, 9sc with C2, 6sc with C1. Turn.") == "Row 6: 6 A, 9 B, 6 A. Turn.")
    #expect(RowText.normalized("Row 3: sc 8 in white, sc 2 in pink, sc 8 in white, ch 1, turn.") == "Row 3: 8 white, 2 pink, 8 white, .")
    #expect(RowText.normalized("Row 6 (>>):(green) sc 10, (white) sc 3, (dark green) sc 1") == "Row 6 (>>): 10 green, 3 white, 1 dark green")
    #expect(RowText.normalized("Row 11 [RS]: (White) x 6, (Pale Rose), (White) x 13, (Pale Rose) x 6, (White), (Pale Rose) x 13") == "Row 11 [RS]: (White) x 6, (Pale Rose) x 1, (White) x 13, (Pale Rose) x 6, (White) x 1, (Pale Rose) x 13")
    // Stitch words glued to counts stay, "ch2" goes with the foundation chain as before, and a code
    // glued after its count ("W14") becomes "14 W"; the grammars that already read well are untouched.
    #expect(RowText.normalized("Row 2: ch2, 3 dc, dc2tog, sc2tog, 4W, W14, (Black) 9 sc, 189 Y, (agave) x 85") == "Row 2: 3 dc, dc2tog, sc2tog, 4W, 14 W, (Black) 9 sc, 189 Y, (agave) x 85")
}

@available(macOS 26.0, *)
@Test func cleanRunsMapNumberedColoursToKeyOrder() {
    let runs = [RunOut(count: 8, code: "c1"), RunOut(count: 1, code: "C2"), RunOut(count: 8, code: "c1")]
    let out = RowText.cleanRuns(runs, key: [:])
    let codes = out.map { pair -> String in
        for v in pair { if case .code(let s) = v { return s } }
        return ""
    }
    #expect(codes == ["A", "B", "A"])
}


@Test func printedKeyLinesGiveCodesAndNames() {
    let page = "Abbreviations\nc = Carrot - this is the background color - if you like, replace it\nbl= Black\nch = Charcoal\nbf =Buff / deconstructed RH Super Saver\nRow 1 [WS]: c\n"
    let key = RowText.printedKey(in: [page])
    #expect(key.map(\.code) == ["c", "bl", "ch", "bf"] && key.map(\.name) == ["carrot", "black", "charcoal", "buff"])
}

@available(macOS 26.0, *)
@Test func aPrintedCodeThatSpellsAStitchWordIsKept() {
    let runs = [RunOut(count: 4, code: "lb"), RunOut(count: 1, code: "ch"), RunOut(count: 2, code: "ch"), RunOut(count: 1, code: "turn")]
    let out = RowText.cleanRuns(runs, key: ["lb": "A", "ch": "E"], printed: ["lb", "ch"])
    let flat = out.map { pair -> (String, Int) in
        var code = "", count = 0
        for v in pair { switch v { case .code(let s): code = s; case .count(let n): count = n } }
        return (code, count)
    }
    #expect(flat.map(\.0) == ["A", "E"] && flat.map(\.1) == [4, 3])
    #expect(RowText.cleanRuns([RunOut(count: 1, code: "ch")], key: [:]).isEmpty)
}


@Test func printedCodesBecomeTheirPaletteLettersBeforeThePrompt() {
    let map = ["lb": "A", "a": "I", "ch": "C", "bf": "G", "c": "D"]
    #expect(RowText.normalized("Row 15 [WS]: (lb) x 3, a, ch, a, bf, c2, (bf) x 2, c", printed: map) == "Row 15 [WS]: (A) x 3, I, C, I, G, 2 D, (G) x 2, D")
    #expect(RowText.normalized("Row 4: Join in a new colour, then c", printed: map) == "Row 4: Join in a new colour, then D")
}
