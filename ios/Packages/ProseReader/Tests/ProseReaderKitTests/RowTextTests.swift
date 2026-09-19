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
