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
