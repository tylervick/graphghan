import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct WorkPanelContentTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static func make(_ cursor: Cursor, step: CountStep = .ten) -> WorkPanelContent {
        WorkPanelContent.make(chart: chart, sequence: seq, cursor: cursor, step: step)
    }
    static func name(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].name }

    @Test func plainRun() {
        let c = Self.make(Cursor(row: 42, run: 8))   // 7 C
        #expect(c.kind == .run && c.count == 7 && c.total == nil && c.code == "C" && c.name == "Cream" && c.badge == "sc")
        #expect(c.parts.isEmpty && c.segmentLabel == nil && c.landmark == nil)
        #expect(c.onDeck == "then 11 Purple")
        #expect(c.actionLabel == "Done with 7 single crochet in Cream" && c.capsule == "checkmark")
        #expect(c.hex == "#f2e8d5")
    }

    @Test func braidListsTheSequence() {
        let c = Self.make(Cursor(row: 42, run: 2))   // 4 Y, third run of the braid
        #expect(c.kind == .braid && c.segmentLabel == "border braid" && c.count == 4)
        #expect(c.parts.map(\.text) == ["2Y", "2G", "4Y", "2G", "2Y", "2G", "1Y", "3G"])
        #expect(c.parts.map(\.state) == [.done, .done, .current, .upcoming, .upcoming, .upcoming, .upcoming, .upcoming])
    }

    @Test func repeatShowsTheUnitAndTheRepetition() {
        let c = Self.make(Cursor(row: 179, run: 8))   // third repetition, first half
        #expect(c.kind == .repeat && c.segmentLabel == "repeat · 3 of 22" && c.repetitions == 22)
        #expect(c.parts.map(\.text) == ["5 Y", "2 G"] && c.parts.map(\.state) == [.current, .upcoming])
    }

    @Test func fillCountsUpWithALandmark() {
        let c = Self.make(Cursor(row: 42, run: 10, stitch: 40))   // 117 C
        #expect(c.kind == .fill && c.count == 40 && c.total == 117)
        #expect(c.landmark == "ends 1 before where Purple starts below")
        #expect(c.actionLabel == "40 of 117 single crochet in Cream, next ten" && c.capsule == "+10")
        #expect(Self.make(Cursor(row: 42, run: 10), step: .wholeRun).capsule == "checkmark")
        #expect(Self.make(Cursor(row: 42, run: 10), step: .five).capsule == "+5")
    }

    @Test func turnSaysWhatTheChartKnows() {
        let runs = Self.seq.pass(at: 42)!.runs.count
        let c = Self.make(Cursor(row: 42, run: runs))
        #expect(c.kind == .turn && c.title == "Ch 1 in Gold, turn")
        #expect(c.subtitle == "Right side · read right to left" && c.detail == "Row 43 starts in Gold")
        #expect(c.capsule == "Turned" && c.actionLabel == "Ch 1 in Gold, turn. Right side, read right to left. Row 43 starts in Gold")
        #expect(c.hex == "#F4F5F0" && c.onDeck == nil)
    }

    @Test func boundaryTitleVariants() {
        // craigh: turn, chain 1, color next → named colour
        #expect(WorkPanelContent.boundaryTitle(chart: Self.chart, nextColorName: "Gold") == "Ch 1 in Gold, turn")
        let plain = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))   // no boundary at all
        #expect(WorkPanelContent.boundaryTitle(chart: plain, nextColorName: "Gold") == "Turn")
        let zero = OnDeckRuleTests.authored(boundary: #"{"kind":"turn","chain":0}"#)
        #expect(WorkPanelContent.boundaryTitle(chart: zero, nextColorName: nil) == "Turn")
        let counts = OnDeckRuleTests.authored(boundary: #"{"kind":"turn","chain":3,"counts_as_stitch":true}"#)
        #expect(WorkPanelContent.boundaryTitle(chart: counts, nextColorName: nil) == "Ch 3, turn (counts as a st)")
    }

    @Test func finishedState() {
        let end = Cursor(row: Self.seq.passes.count, run: Self.seq.passes.last!.runs.count)
        let c = Self.make(end)
        #expect(c.kind == .finished && c.title == "Finished" && c.capsule == "Close" && c.actionLabel == "Close")
    }

    @Test func nonStitchKindNamesTheCellInTheLabel() throws {
        // filet-blocks: cell.kind is "block", no stitch stated; Row 1 (RS, rtl) runs O5, F2, O5
        let chart = try Chart.load(TestFixtures.data("filet-blocks.chart.json"))
        let seq = try WorkSequence(chart: chart)
        let c = WorkPanelContent.make(chart: chart, sequence: seq, cursor: .start, step: .ten)
        #expect(c.actionLabel == "Done with 5 blocks in Color O")
        #expect(c.badge == nil)
    }
}
