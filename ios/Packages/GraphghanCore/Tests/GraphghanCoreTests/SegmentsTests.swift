import Testing
@testable import GraphghanCore

@Suite struct SegmentsTests {
    static let chart = try! Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static func pass(_ row: Int) -> Pass { seq.pass(at: row)! }

    private func run(_ count: Int, _ code: String, x0: Int? = nil) -> Run { Run(code: code, count: count, x0: x0) }
    private func pass(_ runs: [Run], direction: Direction? = .ltr) -> Pass {
        Pass(label: "Row 1", side: .rs, direction: direction, gridRow: 0, runs: runs)
    }

    @Test func singleRunRowIsOneFill() {
        let segs = Segments.of(Self.pass(1))   // 189 Y
        #expect(segs == [Segment(kind: .fill, runs: 0..<1, period: 0, repetitions: 0)])
    }

    @Test func row42IsBraidFillsAndRuns() {
        // 2Y 2G 4Y 2G 2Y 2G 1Y 3G | 7C 11P 117C 11P 7C | 3G 1Y 2G 2Y 2G 4Y 2G 2Y  (21 runs)
        let segs = Segments.of(Self.pass(42))
        #expect(segs.first == Segment(kind: .braid, runs: 0..<8, period: 0, repetitions: 0))
        #expect(segs.last == Segment(kind: .braid, runs: 13..<21, period: 0, repetitions: 0))
        #expect(segs.map(\.kind) == [.braid, .run, .run, .fill, .run, .run, .braid])
        #expect(Segments.segment(containing: 10, in: Self.pass(42))?.kind == .fill)
        #expect(Segments.segment(containing: 21, in: Self.pass(42)) == nil)   // the boundary position has no segment
    }

    @Test func row179HasARepeatBand() {
        // rtl: 4Y 8G 2Y 1G then (5Y 2G) x 22 ... ; the band starts at run 4
        let segs = Segments.of(Self.pass(179))
        let band = try! #require(segs.first { $0.kind == .repeat })
        #expect(band.runs.lowerBound == 4 && band.period == 2 && band.repetitions == 22)
        #expect(band.runs.count == 44)
        #expect(Segments.repetition(of: 8, in: band) == 2)
        #expect(Segments.repetition(of: 3, in: band) == nil)
    }

    @Test func braidNeedsEightShortRunsAndSixteenForBothEnds() {
        let eight = (0..<8).map { _ in run(2, "A") }
        #expect(Segments.of(pass(eight)).first?.kind == .braid)
        #expect(Segments.of(pass(eight + [run(3, "B")])).map(\.kind) == [.braid, .run])
        // 10 runs: only the leading braid, never an overlapping trailing one
        let ten = eight + [run(1, "B"), run(1, "A")]
        #expect(Segments.of(pass(ten)).map(\.kind) == [.braid, .run, .run])
        // a 5-count run breaks the braid
        var broken = eight; broken[3] = run(5, "A")
        #expect(Segments.of(pass(broken)).first?.kind != .braid)
    }

    @Test func repeatPicksLongestSpanAtEarliestStart() {
        // A B A B A B C : period 2, 3 reps, then a run
        let runs = [run(5, "A"), run(2, "B"), run(5, "A"), run(2, "B"), run(5, "A"), run(2, "B"), run(1, "C")]
        let segs = Segments.of(pass(runs))
        #expect(segs == [Segment(kind: .repeat, runs: 0..<6, period: 2, repetitions: 3), Segment(kind: .run, runs: 6..<7, period: 0, repetitions: 0)])
        // two repetitions are not a band
        #expect(Segments.of(pass(Array(runs.prefix(4)))).allSatisfy { $0.kind == .run })
    }

    @Test func fillIsTwentyOrMore() {
        #expect(Segments.of(pass([run(19, "A")])).first?.kind == .run)
        #expect(Segments.of(pass([run(20, "A")])).first?.kind == .fill)
    }

    @Test func landmarkNamesTheNearestColourStartBelow() {
        // ltr fill x0 10, count 30 → ends at x 40; below: A 0..<25, B 25..<45, C 45..<60
        let below = pass([run(25, "A", x0: 0), run(20, "B", x0: 25), run(15, "C", x0: 45)])
        let fill = run(30, "A", x0: 10)
        #expect(Segments.landmark(for: fill, direction: .ltr, below: below) == Landmark(code: "B", offset: 15))   // 40 - 25
        // rtl: read right to left the fill ends at x 10; a run below "starts" at its right edge, so A starts at 25, B at 45, C at 60;
        // only 25 is inside the fill's span 10..<40, so the landmark is A, 15 cells before the end
        #expect(Segments.landmark(for: fill, direction: .rtl, below: below) == Landmark(code: "A", offset: 15))
        // a plain row below has no landmark
        #expect(Segments.landmark(for: fill, direction: .ltr, below: pass([run(60, "A", x0: 0)])) == nil)
        #expect(Segments.landmark(for: fill, direction: .ltr, below: nil) == nil)
        #expect(Segments.landmark(for: run(30, "A"), direction: .ltr, below: below) == nil)   // no x0, no landmark
    }
}
