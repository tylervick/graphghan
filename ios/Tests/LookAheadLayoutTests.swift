import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct LookAheadLayoutTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))
    static let rect = BandLayout.wholeChartRect(chart: chart, in: CGSize(width: 366, height: 420))
    static var ch: CGFloat { rect.height / 184 }
    private func layout(row: Int, stretches: [Stretch] = stretches) -> LookAheadLayout {
        LookAheadLayout(rect: Self.rect, chartHeight: Self.chart.height, sequence: Self.seq, stretches: stretches, row: row)
    }

    @Test func tickIntervalFollowsThePassCount() {
        #expect(LookAheadLayout.tickInterval(passCount: 184) == 20)
        #expect(LookAheadLayout.tickInterval(passCount: 61) == 20)
        #expect(LookAheadLayout.tickInterval(passCount: 60) == 10)
        #expect(LookAheadLayout.tickInterval(passCount: 21) == 10)
        #expect(LookAheadLayout.tickInterval(passCount: 20) == 5)
    }

    /// #250: zoomed in, the passes are further apart and the ticks come closer together.
    @Test func tickIntervalTightensWithTheZoom() {
        #expect(LookAheadLayout.tickInterval(passCount: 184, zoom: 1) == 20)
        #expect(LookAheadLayout.tickInterval(passCount: 184, zoom: 3.2) == 10)
        #expect(LookAheadLayout.tickInterval(passCount: 184, zoom: 10) == 5)
        #expect(LookAheadLayout.tickInterval(passCount: 184, zoom: 0.9) == 20)
    }

    /// #250: with the whole fitted rect in view, saying so changes nothing.
    @Test func aVisibleRangeCoveringTheChartChangesNothing() {
        let plain = layout(row: 5)
        let seen = LookAheadLayout(rect: Self.rect, chartHeight: Self.chart.height, sequence: Self.seq, stretches: Self.stretches, row: 5,
                                   visible: 0...420, zoom: 1)
        #expect(seen.ticks == plain.ticks && seen.hairlines == plain.hairlines && seen.labels == plain.labels && seen.bracket == plain.bracket)
    }

    /// #250: zoomed in and panned, only what is on the band is ticked and labelled, and a stretch
    /// taller than the band is named in the part of it that shows.
    @Test func zoomedInTheMarksAreChosenAmongWhatShows() throws {
        let zoom: CGFloat = 3.2
        // The chart over three times the size, scrolled so the band shows its bottom 420 pt.
        let big = CGRect(x: 0, y: 420 - Self.rect.height * zoom, width: Self.rect.width * zoom, height: Self.rect.height * zoom)
        let l = LookAheadLayout(rect: big, chartHeight: Self.chart.height, sequence: Self.seq, stretches: Self.stretches, row: 5,
                                visible: 0...420, zoom: zoom)
        #expect(!l.ticks.isEmpty && l.ticks.allSatisfy { (0...420).contains($0.y) })
        #expect(zip(l.ticks, l.ticks.dropFirst()).allSatisfy { $1.row - $0.row == 10 })
        #expect(!l.labels.isEmpty && l.labels.allSatisfy { (0...420).contains($0.y) })
        #expect(l.labels.first?.current == true)
        // Scrolled to the top of the chart instead: the current stretch is off the band and unnamed,
        // and the stretches up there, which the fitted view's eight labels never reached, are.
        let top = CGRect(x: 0, y: 0, width: big.width, height: big.height)
        let far = LookAheadLayout(rect: top, chartHeight: Self.chart.height, sequence: Self.seq, stretches: Self.stretches, row: 5,
                                  visible: 0...420, zoom: zoom)
        #expect(!far.labels.isEmpty && far.labels.allSatisfy { !$0.current && (0...420).contains($0.y) })
        let fittedTexts = Set(layout(row: 5).labels.map(\.text))
        #expect(far.labels.contains { !fittedTexts.contains($0.text) })
        // One stretch filling the band and more: its label sits mid-band, not at its own centre off screen.
        let one = [Stretch(rows: 1...100, kind: .plain, colours: ["A"]), Stretch(rows: 101...184, kind: .plain, colours: ["B"])]
        let tall = LookAheadLayout(rect: big, chartHeight: Self.chart.height, sequence: Self.seq, stretches: one, row: 5, visible: 0...420, zoom: zoom)
        #expect(tall.labels.count == 1 && abs(tall.labels[0].y - 210) < 0.01)
    }

    @Test func ticksSitOnTheirPassesCentres() {
        let l = layout(row: 5)
        #expect(l.ticks.map(\.row) == Array(stride(from: 20, through: 180, by: 20)))
        // bottom-up: pass 20 is grid row 164
        #expect(abs(l.ticks[0].y - (Self.rect.minY + 164.5 * Self.ch)) < 0.01)
    }

    @Test func hairlinesStandBeforeEveryStretchButTheFirst() {
        let l = layout(row: 5)
        #expect(l.hairlines.count == Self.stretches.count - 1)
        // before stretch 5–14: the bottom edge of pass 5 (grid row 179) in a bottom-up chart
        #expect(abs(l.hairlines[1].y - (Self.rect.minY + 180 * Self.ch)) < 0.01)
        #expect(l.hairlines[0].ahead == false && l.hairlines[1].ahead == true)
    }

    @Test func theBracketSpansTheCurrentStretch() throws {
        let b = try #require(layout(row: 5).bracket)
        // passes 5…14 are grid rows 179…170
        #expect(abs(b.lowerBound - (Self.rect.minY + 170 * Self.ch)) < 0.01)
        #expect(abs(b.upperBound - (Self.rect.minY + 180 * Self.ch)) < 0.01)
    }

    @Test func labelsStartAtTheCurrentStretchNeverOverlapAndStopAtEight() {
        let l = layout(row: 5)
        #expect(l.labels.count == 8)
        #expect(l.labels.first?.text == "Rows 5–14 · 10" && l.labels.first?.current == true)
        #expect(l.labels.first?.codes == ["Y", "G"])
        // centres at least a pill's height apart, so two pills never overlap
        for (a, b) in zip(l.labels, l.labels.dropFirst()) { #expect(abs(a.y - b.y) >= LookAheadLayout.labelHeight) }
        #expect(l.labels.allSatisfy { $0.y <= l.labels.first!.y })  // ahead is upward on a bottom-up chart
        #expect(LookAheadLayout.labelText(Stretch(rows: 41...41, kind: .pattern, colours: [])) == "Row 41 · 1")
    }

    @Test func lateInTheBlanketFewLabelsRemain() {
        let l = layout(row: 150)
        #expect(l.labels.count <= 7 && l.labels.first?.text == "Rows 140–160 · 21")
        for (a, b) in zip(l.labels, l.labels.dropFirst()) { #expect(abs(a.y - b.y) >= LookAheadLayout.labelHeight) }
    }

    @Test func aOneRowStretchGetsNoLabel() {
        // a one-row first stretch is current: the hairline and the bracket mark it, the label is for two rows or more
        let passes = (0..<5).map { Pass(label: "Row \($0 + 1)", side: .rs, direction: .ltr, gridRow: $0, runs: [Run(code: "A", count: 3, x0: 0)]) }
        let seq = WorkSequence(passes: passes)
        let l = LookAheadLayout(rect: CGRect(x: 0, y: 0, width: 300, height: 100), chartHeight: 5, sequence: seq,
                                stretches: [Stretch(rows: 1...1, kind: .plain, colours: ["A"]), Stretch(rows: 2...5, kind: .plain, colours: ["A"])], row: 1)
        #expect(l.bracket == 0...20)
        #expect(l.labels.map(\.text) == ["Rows 2–5 · 4"])
    }

    @Test func aRowPastTheEndHasNoCurrentStretch() {
        // the finished whole view: every hairline worked, nothing bracketed or labelled
        let l = layout(row: 185)
        #expect(l.bracket == nil && l.labels.isEmpty)
        #expect(l.hairlines.count == Self.stretches.count - 1 && l.hairlines.allSatisfy { !$0.ahead })
    }

    @Test func oneStretchDrawsTicksOnly() {
        let l = layout(row: 42, stretches: [Stretch(rows: 1...184, kind: .pattern, colours: ["C"])])
        #expect(!l.ticks.isEmpty && l.hairlines.isEmpty && l.bracket == nil && l.labels.isEmpty)
        let none = layout(row: 42, stretches: [])
        #expect(!none.ticks.isEmpty && none.hairlines.isEmpty && none.bracket == nil && none.labels.isEmpty)
    }

    @Test func aTopDownChartPutsTheHairlineOnTheTopEdge() {
        // five passes, grid rows 0…4, top-down; stretches 1–2 and 3–5
        let passes = (0..<5).map { Pass(label: "Row \($0 + 1)", side: .rs, direction: .ltr, gridRow: $0, runs: [Run(code: "A", count: 3, x0: 0)]) }
        let seq = WorkSequence(passes: passes)
        let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
        let l = LookAheadLayout(rect: rect, chartHeight: 5, sequence: seq, stretches: [Stretch(rows: 1...2, kind: .plain, colours: ["A"]), Stretch(rows: 3...5, kind: .plain, colours: ["A"])], row: 1)
        #expect(l.hairlines.map(\.y) == [40])            // top edge of pass 3 (grid row 2)
        #expect(l.bracket == 0...40)
    }

    @Test func passesWithoutAGridRowGetNoMarks() throws {
        let chart = try Chart.load(TestFixtures.data("explicit-passes.chart.json"))
        let seq = try WorkSequence(chart: chart)
        let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))
        let rect = BandLayout.wholeChartRect(chart: chart, in: CGSize(width: 366, height: 420))
        let l = LookAheadLayout(rect: rect, chartHeight: chart.height, sequence: seq, stretches: stretches, row: 1)
        let withRow = Set(seq.passes.indices.filter { seq.passes[$0].gridRow != nil }.map { $0 + 1 })
        #expect(l.ticks.allSatisfy { withRow.contains($0.row) })
        // a synthetic sequence where the tick row, a stretch start and the current stretch's end have no grid row
        let run = [Run(code: "A", count: 3, x0: 0)]
        var passes = (0..<10).map { Pass(label: "Row \($0 + 1)", side: .rs, direction: .ltr, gridRow: $0, runs: run) }
        passes[4] = Pass(label: "Row 5", side: .rs, direction: .ltr, gridRow: nil, runs: run)   // the tick at 5 and stretch 5–10's start
        passes[3] = Pass(label: "Row 4", side: .rs, direction: .ltr, gridRow: nil, runs: run)   // the current stretch's last pass
        let s = WorkSequence(passes: passes)
        let two = [Stretch(rows: 1...4, kind: .plain, colours: ["A"]), Stretch(rows: 5...10, kind: .plain, colours: ["A"])]
        let m = LookAheadLayout(rect: CGRect(x: 0, y: 0, width: 300, height: 100), chartHeight: 10, sequence: s, stretches: two, row: 1)
        #expect(m.ticks.map(\.row) == [10])
        #expect(m.hairlines.isEmpty && m.bracket == nil)
        #expect(m.labels.isEmpty)   // both stretches contain a pass with no grid row
    }
}
