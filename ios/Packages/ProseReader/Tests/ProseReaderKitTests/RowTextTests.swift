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
    var spellings: [String: String] = [:]
    let out = RowText.cleanRuns(runs, key: ["black": "A", "white": "B"], spellings: &spellings)
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
    #expect(parts.count == 3 && parts.allSatisfy { $0.hasPrefix("Row 41 (RS): ") } && parts.last!.hasSuffix("(189 sts)"))  // chunks alone keep the text; normalized strips it
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
    #expect(RowText.normalized("R 2 [→]: (Black) ch 1, turn, 1 inc, 7 sc, (White) 1 inc [11]") == "R 2 [→]: (Black) 9 sc, (White) 2 sc")
    #expect(RowText.normalized("R 57 [←]: 9 sc, (White) 15 sc, 1 dec [25]") == "R 57 [←]: 9 sc, (White) 16 sc")
    #expect(RowText.normalized("R 1 [←]: (Black) ch 10, from the second stitch from the hook, 9 sc [9]") == "R 1 [←]: (Black) 9 sc")
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
    #expect(RowText.normalized("Rows 1-10: Sc in each st across, turn.") == "Row 1: Sc in each st across, turn.")
    #expect(RowText.normalized("Row 6 (>>):(green) sc 10, (white) sc 3") == "Row 6 (>>): 10 green, 3 white")
    #expect(RowText.normalized("Row 12 (WS): 4 Y, 3 G") == "Row 12 (WS): 4 Y, 3 G")
    #expect(RowText.normalized("R 57 [←]: 9 sc, (White) 15 sc, 1 dec [25]") == "R 57 [←]: 9 sc, (White) 16 sc")
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
    #expect(RowText.normalized("Row 15 [WS]: (dg) x 3, (gh) x 2, c2, w, c, gh, dg") == "Row 15 [WS]: (dg) x 3, (gh) x 2, 2 c, 1 w, 1 c, 1 gh, 1 dg")
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
    var spellings: [String: String] = [:]
    let out = RowText.cleanRuns(runs, key: [:], spellings: &spellings)
    let codes = out.map { pair -> String in
        for v in pair { if case .code(let s) = v { return s } }
        return ""
    }
    #expect(codes == ["A", "B", "A"])
}


@Test func printedKeyLinesGiveCodesAndNames() {
    let page = "Abbreviations\nc = Carrot - this is the background color - if you like, replace it\nbl= Black\nch = Charcoal\nbf =Buff / deconstructed RH Super Saver\nw= (Soft) White\nRow 1 [WS]: c\n"
    let key = RowText.printedKey(in: [page])
    #expect(key.map(\.code) == ["c", "bl", "ch", "bf", "w"] && key.map(\.name) == ["carrot", "black", "charcoal", "buff", "soft white"])
}

@available(macOS 26.0, *)
@Test func aPrintedCodeThatSpellsAStitchWordIsKept() {
    let runs = [RunOut(count: 4, code: "lb"), RunOut(count: 1, code: "ch"), RunOut(count: 2, code: "ch"), RunOut(count: 1, code: "turn")]
    var spellings: [String: String] = [:]
    let out = RowText.cleanRuns(runs, key: ["lb": "A", "ch": "E"], printed: ["lb", "ch"], spellings: &spellings)
    let flat = out.map { pair -> (String, Int) in
        var code = "", count = 0
        for v in pair { switch v { case .code(let s): code = s; case .count(let n): count = n } }
        return (code, count)
    }
    #expect(flat.map(\.0) == ["A", "E"] && flat.map(\.1) == [4, 3])
    #expect(RowText.cleanRuns([RunOut(count: 1, code: "ch")], key: [:], spellings: &spellings).isEmpty)
}


@Test func printedCodesBecomeTheirPaletteLettersBeforeThePrompt() {
    let map = ["lb": "A", "a": "I", "ch": "C", "bf": "G", "c": "D"]
    #expect(RowText.normalized("Row 15 [WS]: (lb) x 3, a, ch, a, bf, c2, (bf) x 2, c", printed: map) == "Row 15 [WS]: (A) x 3, 1 I, 1 C, 1 I, 1 G, 2 D, (G) x 2, 1 D")
    #expect(RowText.normalized("Row 4: Join in a new colour, then c", printed: map) == "Row 4: Join in a new colour, then D")  // not a run item
    #expect(RowText.normalized("Row 30 [RS]: (lb) x 5, bf, c.", printed: map) == "Row 30 [RS]: (A) x 5, 1 G, 1 D.")
}

// #147: ranges and repeats.
@Test func rangeHeadsListEveryRowTheyCover() {
    #expect(RowText.rowNumbers(of: "Rows 1-10: Sc in each st across, turn.") == Array(1...10))
    #expect(RowText.rowNumbers(of: "Rows 2 & 3: Chain1, (12sc), Turn.") == [2, 3])
    #expect(RowText.rowNumbers(of: "Row 13-15: sc in c1.") == [13, 14, 15])
    #expect(RowText.rowNumbers(of: "Rows 9- 10: 3 sc in c1, 11 sc in c2, 3 sc in c1") == [9, 10])
    // The count a progress bar is out of expands ranges the way `read` does (CodeRabbit, PR #163).
    #expect(RowText.rowCount(in: ["Rows 1-10: sc across.\nRow 11: 3 A, 2 B.", "Rows 12 & 13: sc across."]) == 13)
    #expect(RowText.rowNumbers(of: "Rows 2 and 3: sc across") == [2, 3])
    #expect(RowText.rowNumbers(of: "Row 5: 7sc in c1, 3sc in c2, 7sc in c1.") == [5])
    #expect(RowText.rowNumbers(of: "7. 2G, 3R, 2G") == [7])
    #expect(RowText.rowNumbers(of: "Total: 3673") == [])
    #expect(RowText.rowNumbers(of: "Rows 1 – 25 you will be increasing and rows 26 – 49 you will be decreasing.") == [])
    #expect(RowText.blocks(in: "Rows 1 – 25 you will be increasing and rows 26 – 49 you will be decreasing.\nRow 1 [RS]: (w) x 1 (1 square)\n") == ["Row 1 [RS]: (w) x 1 (1 square)"])
    #expect(RowText.normalized("Rows 1-10: Sc in each st across, turn.") == "Row 1: Sc in each st across, turn.")
    #expect(RowText.normalized("Row 13-15: sc in c1.") == "Row 13: sc in A.")
    #expect(RowText.normalized("Row1: sc in second chain, sc across in color 1") == "Row 1: sc in second chain, sc across in A")
    #expect(RowText.plainRowColour(of: RowText.normalized("Row1: sc in second chain, sc across in color 1")) == "A")
}

@Test func aRowThatRepeatsAnotherNamesIt() {
    #expect(RowText.repeatedRow(in: "Row 6: repeat row 5.") == 5)
    #expect(RowText.repeatedRow(in: "Rows 9-10: Rep Row 8.") == 8)
    #expect(RowText.repeatedRow(in: "Row 16: Repeat row 15, then fasten off.") == 15)
    #expect(RowText.repeatedRow(in: "Row 6: 6 white, 6 pink, 6 white") == nil)
    #expect(RowText.repeatedRow(in: "Row 20: A (4), *B (2), A (3); repeat from * across") == nil)
}

@Test func bracketedGroupsWithACountAreExpanded() {
    #expect(RowText.normalized("Row 8: 12 MC, (14 CC, 24 MC) 3 times, 14 CC, 12 MC.") == "Row 8: 12 MC, 14 CC, 24 MC, 14 CC, 24 MC, 14 CC, 24 MC, 14 CC, 12 MC.")
    #expect(RowText.normalized("Row 22: A 5, B 2, A 7, [B 3, A 3] 2 times, B 2, A 10, turn.") == "Row 22: A 5, B 2, A 7, B 3, A 3, B 3, A 3, B 2, A 10, turn.")
    #expect(RowText.normalized("Row 9: (sc 2, dc 1) twice, sc 4") == "Row 9: sc 2, dc 1, sc 2, dc 1, sc 4")
    #expect(RowText.normalized("Row 5 [WS]: (lb) x 5, (bf) x 2") == "Row 5 [WS]: (lb) x 5, (bf) x 2")
}

@Test func starredGroupsRepeatToTheRowsWidthOrACount() {
    let row = "Row 20: Ch 1, A (4), *B (2), A (3), B (2), A (4); repeat from * across, turn."
    #expect(RowText.normalized(row, width: 37) == "Row 20: A (4), B (2), A (3), B (2), A (4), B (2), A (3), B (2), A (4), B (2), A (3), B (2), A (4), turn.")
    #expect(RowText.normalized(row, width: 38) == "Row 20: A (4), *B (2), A (3), B (2), A (4); repeat from * across, turn.")
    #expect(RowText.normalized(row) == "Row 20: A (4), *B (2), A (3), B (2), A (4); repeat from * across, turn.")
    #expect(RowText.normalized("Row 3: 2 A, *3 B, 1 A; rep from * 2 more times, 2 A", width: 100) == "Row 3: 2 A, 3 B, 1 A, 3 B, 1 A, 3 B, 1 A, 2 A")
    #expect(RowText.normalized("Row 4: *3 B, 1 A; rep from * 3 times") == "Row 4: 3 B, 1 A, 3 B, 1 A, 3 B, 1 A")
}

// A plain row carries no count: the previous row's width in the colour it names, or none named.
@Test func plainRowsNameAtMostOneColourAndNoCount() {
    #expect(RowText.plainRowColour(of: "Row 1: sc in second chain, sc across in A") == "A")
    #expect(RowText.plainRowColour(of: "Row 2: sc in each st across, ch 1, turn. (18)") == "")
    #expect(RowText.plainRowColour(of: "Rows 24-32: With A, sc in each st across. Fasten off after Row 32.") == "A")
    #expect(RowText.plainRowColour(of: "Row 20 (>>): 60 white") == nil)
    #expect(RowText.plainRowColour(of: "Row 3: 8 white, 2 pink, 8 white") == nil)
    #expect(RowText.plainRowColour(of: "Row 13: sc in A.") == "A")
}

// #149: a bracketed total at the row's end is read in code and removed from the prompt; alone in
// the last chunk the model read "(14 boxes)" as runs.
@Test func bracketedTotalsAreReadInCodeAndRemovedFromThePrompt() {
    #expect(RowText.printedTotal(of: "Row 14: blue x 5, gray x 1, buff x 2 (14 boxes)") == 14)
    #expect(RowText.printedTotal(of: "Row 1 (RS): 189 Y (189 sts)") == 189)
    #expect(RowText.printedTotal(of: "R 57 [←]: 9 sc, (White) 15 sc, 1 dec [25]") == 25)
    #expect(RowText.printedTotal(of: "Row 6 [WS]: (Duck Egg) x 24, (White) x 4 (52 squares)") == 52)
    #expect(RowText.printedTotal(of: "Row 3: 8 white, 2 pink, 8 white") == nil)
    #expect(RowText.normalized("Row 2: blue x 2 (2 boxes)") == "Row 2: blue x 2")
    #expect(RowText.normalized("Row 1 (RS): 189 Y (189 sts)") == "Row 1 (RS): 189 Y")
    #expect(RowText.normalized("R 57 [←]: 9 sc, (White) 15 sc, 1 dec [25]") == "R 57 [←]: 9 sc, (White) 16 sc")
    let parts = RowText.chunks(of: RowText.normalized("Row 14: blue x 5, gray x 1, buff x 2, white x 4, buff x 1, blue x 1 (14 boxes)"), maxRuns: 4)
    #expect(parts == ["Row 14: blue x 5, gray x 1, buff x 2, white x 4", "Row 14: buff x 1, blue x 1"])
}


@available(macOS 26.0, *)
@Test func aCodesSpellingIsTheFirstSeen() {
    var spellings: [String: String] = [:]
    _ = RowText.cleanRuns([RunOut(count: 3, code: "w")], key: [:], spellings: &spellings)
    let out = RowText.cleanRuns([RunOut(count: 2, code: "W"), RunOut(count: 1, code: "Gd")], key: [:], spellings: &spellings)
    let codes = out.map { pair -> String in
        for v in pair { if case .code(let s) = v { return s } }
        return ""
    }
    #expect(codes == ["w", "Gd"])
}

// #150: a code the model made up (copied from the example grammars) is dropped: a run's code must
// be a palette code, a printed code, or a token of the row's own text.
@available(macOS 26.0, *)
@Test func runsNameOnlyColoursTheDocumentOrTheRowKnows() {
    var spellings: [String: String] = [:]
    func codes(_ runs: [RunOut], key: [String: String], printed: Set<String> = [], text: String) -> [String] {
        RowText.cleanRuns(runs, key: key, printed: printed, spellings: &spellings, text: text).map { pair -> String in
            for v in pair { if case .code(let s) = v { return s } }
            return ""
        }
    }
    let key = ["white": "A", "pink": "B"]
    #expect(codes([RunOut(count: 8, code: "Bla"), RunOut(count: 60, code: "aga")], key: key, text: "Row 6: repeat row 5.") == [])
    #expect(codes([RunOut(count: 3, code: "white"), RunOut(count: 2, code: "pink")], key: key, text: "Row 3: 8 white, 2 pink") == ["A", "B"])
    #expect(codes([RunOut(count: 3, code: "A")], key: key, text: "Row 3: 8 white") == ["A"])  // a palette code
    #expect(codes([RunOut(count: 3, code: "a")], key: key, text: "Row 3: 8 white") == ["A"])  // the palette code in the model's case, spelled as first seen
    #expect(codes([RunOut(count: 2, code: "lb")], key: [:], printed: ["lb"], text: "Row 5: (lb) x 2") == ["lb"])
    #expect(codes([RunOut(count: 5, code: "Gd")], key: [:], text: "Row 1: 5 Gd, 3 Y") == ["Gd"])
    #expect(codes([RunOut(count: 5, code: "Gd")], key: [:], text: "Row 1: 5 Y") == [])
}

@Test func theRowCountIsTheNumberOfBlocksAcrossPages() {
    let pages = ["Key\nA red\nRow 1: 3 A, 4 B\nRow 2: 7 A\n", "Row 3: 7 B\nCraigh Page 2\n", "Nothing here"]
    #expect(RowText.rowCount(in: pages) == 3)
    #expect(RowText.rowCount(in: []) == 0)
}
