import Testing
@testable import GraphghanCore

@Suite struct StretchesTests {
    static let chart = try! Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let codes = chart.palette.map(\.code)
    static let stretches = Stretches.of(seq, codes: codes)

    private func pass(_ runs: [(Int, String)]) -> Pass {
        Pass(label: "Row", side: .rs, direction: .ltr, gridRow: 0, runs: runs.map { Run(code: $0.1, count: $0.0, x0: nil) })
    }
    private func seq(_ passes: [Pass]) -> WorkSequence { WorkSequence(passes: passes) }

    @Test func craighNaDunHasTwentyFourStretches() {
        // spec §3.3, the whole table
        let expected: [(ClosedRange<Int>, Stretch.Kind, String)] = [
            (1...2, .plain, "Y"), (3...4, .plain, "G Y"), (5...14, .repeat, "Y G"), (15...16, .plain, "G Y"),
            (17...20, .pattern, "G Y"), (21...22, .pattern, "C G Y"), (23...41, .pattern, "C G Y K P"),
            (42...45, .pattern, "C G P Y"), (46...51, .pattern, "C G Y"), (52...64, .pattern, "C K G Y"),
            (65...69, .pattern, "C G Y"), (70...84, .pattern, "C K G Y"), (85...88, .pattern, "C G Y"),
            (89...101, .pattern, "C K G Y"), (102...108, .pattern, "C G Y"), (109...124, .pattern, "C K G Y"),
            (125...139, .pattern, "G C Y"), (140...160, .pattern, "C G Y K"), (161...164, .pattern, "C G Y"),
            (165...168, .pattern, "G Y"), (169...170, .plain, "G Y"), (171...180, .repeat, "Y G"),
            (181...182, .plain, "G Y"), (183...184, .plain, "Y"),
        ]
        #expect(Self.stretches == expected.map { Stretch(rows: $0.0, kind: $0.1, colours: $0.2.split(separator: " ").map(String.init)) })
    }

    @Test func indexFindsTheStretchOfARow() {
        #expect(Stretches.index(containing: 5, in: Self.stretches) == 2)
        #expect(Stretches.index(containing: 41, in: Self.stretches) == 6)   // absorbed blip
        #expect(Stretches.index(containing: 185, in: Self.stretches) == nil)
    }

    @Test func onePassIsOneStretch() {
        #expect(Stretches.of(seq([pass([(10, "A")])]), codes: ["A"]) == [Stretch(rows: 1...1, kind: .plain, colours: ["A"])])
    }

    @Test func identicalRowsAreOneStretch() {
        let s = seq(Array(repeating: pass([(5, "A"), (5, "B")]), count: 6))
        #expect(Stretches.of(s, codes: ["A", "B"]) == [Stretch(rows: 1...6, kind: .plain, colours: ["A", "B"])])
    }

    @Test func ratioOfThreeIsABoundaryAndJustUnderIsNot() {
        let three = [(1, "A"), (1, "A"), (1, "A")], nine = Array(repeating: (1, "A"), count: 9), eight = Array(repeating: (1, "A"), count: 8)
        #expect(Stretches.of(seq([pass(three), pass(three), pass(nine), pass(nine)]), codes: ["A"]).map(\.rows) == [1...2, 3...4])
        #expect(Stretches.of(seq([pass(three), pass(three), pass(eight), pass(eight)]), codes: ["A"]).map(\.rows) == [1...4])
    }

    @Test func aColourJoiningIsABoundary() {
        let s = seq([pass([(5, "A")]), pass([(5, "A")]), pass([(4, "A"), (1, "B")]), pass([(4, "A"), (1, "B")])])
        #expect(Stretches.of(s, codes: ["A", "B"]).map(\.rows) == [1...2, 3...4])
    }

    @Test func aOneRowStretchJoinsTheOneBefore() {
        let a = pass([(5, "A")]), b = pass([(5, "B")])
        #expect(Stretches.of(seq([a, a, b, a, a]), codes: ["A", "B"]).map(\.rows) == [1...3, 4...5])
    }

    @Test func aOneRowFirstStretchIsKept() {
        let a = pass([(5, "A")]), b = pass([(5, "B")])
        #expect(Stretches.of(seq([a, b, b]), codes: ["A", "B"]).map(\.rows) == [1...1, 2...3])
    }

    @Test func anEmptyPassIsItsOwnBoundary() {
        let a = pass([(5, "A")]), empty = pass([])
        #expect(Stretches.of(seq([a, a, empty, empty, a, a]), codes: ["A"]).map(\.rows) == [1...2, 3...4, 5...6])
    }

    @Test func coloursOrderByCellsThenPalette() {
        let s = seq([pass([(3, "B"), (3, "A")]), pass([(3, "B"), (3, "A")])])
        #expect(Stretches.of(s, codes: ["A", "B"]).first?.colours == ["A", "B"])
    }
}
