import Foundation
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

    /// The band is `accessibilityHidden`, so the segment has to be spoken from the panel (spec §6):
    /// counts with colour names, not codes, and the run in hand marked.
    @Test func braidIsSpokenAsNamesWithTheCurrentRunMarked() {
        let c = Self.make(Cursor(row: 42, run: 2))
        #expect(c.spokenValue == "border braid: 2 Gold, 2 Deep Green, 4 Gold (current), 2 Deep Green, 2 Gold, 2 Deep Green, 1 Gold, 3 Deep Green")
        #expect(c.bandLabel == "border braid")
    }

    @Test func repeatIsSpokenWithItsRepetitionAndTheCurrentHalf() {
        let c = Self.make(Cursor(row: 179, run: 8))
        #expect(c.spokenValue == "repeat 3 of 22: 5 Gold (current), 2 Deep Green")
        // the band's bracket names the unit; the panel's caption names the segment
        #expect(c.bandLabel == "×22 · 3 of 22")
    }

    @Test func otherKindsHaveNothingExtraToSpeak() {
        #expect(Self.make(Cursor(row: 42, run: 8)).spokenValue == nil)
        #expect(Self.make(Cursor(row: 42, run: 10, stitch: 40)).spokenValue == nil)
        #expect(Self.make(Cursor(row: 42, run: Self.seq.pass(at: 42)!.runs.count)).spokenValue == nil)
    }

    @Test func fillCountsUpWithALandmark() {
        let c = Self.make(Cursor(row: 42, run: 10, stitch: 40))   // 117 C
        #expect(c.kind == .fill && c.count == 40 && c.total == 117)
        #expect(c.landmark == "ends 1 before where Purple starts below")
        #expect(c.actionLabel == "40 of 117 single crochet in Cream, next ten" && c.capsule == "+10")
        #expect(Self.make(Cursor(row: 42, run: 10), step: .wholeRun).capsule == "checkmark")
        #expect(Self.make(Cursor(row: 42, run: 10), step: .five).capsule == "+5")
    }

    /// Explicit passes that state neither side nor direction, so the turn has no facing to report.
    static let silentPasses: Chart = {
        let passes = try! JSONDecoder().decode(JSONValue.self, from: Data(#"""
        [{"label":"Row 1","grid_row":0,"runs":[{"code":"A","count":2,"x0":0},{"code":"B","count":2,"x0":2}]},
         {"label":"Row 2","grid_row":1,"runs":[{"code":"A","count":4,"x0":0}]}]
        """#.utf8))
        let technique = JSONValue.object(["type": .string("rows")])
        let id = ChartID.compute(codes: ["A", "B"], rows: ["2A2B", "4A"], technique: technique, passes: passes)
        let json = """
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\(id)","width":4,"height":2},
         "palette":[{"code":"A","name":"Alpha","hex":"#1E4D3A"},{"code":"B","name":"Beta","hex":"#D9A21B"}],
         "rows":["2A2B","4A"],"gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"sc"},
         "technique":\(CanonicalJSON.encode(technique)),"passes":\(CanonicalJSON.encode(passes)),"instructions":[]}
        """
        return try! Chart.load(Data(json.utf8))
    }()

    /// A pass that states neither side nor direction says neither; the panel never invents "Right side".
    @Test func turnOmitsWhatTheChartDoesNotState() throws {
        let chart = Self.silentPasses
        let seq = try WorkSequence(chart: chart)
        try #require(seq.pass(at: 2)?.side == nil && seq.pass(at: 2)?.direction == nil)
        let c = WorkPanelContent.make(chart: chart, sequence: seq, cursor: Cursor(row: 1, run: seq.pass(at: 1)!.runs.count), step: .ten)
        #expect(c.kind == .turn && c.subtitle == nil)
        #expect(c.actionLabel == "Turn. Row 2 starts in Alpha")
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
