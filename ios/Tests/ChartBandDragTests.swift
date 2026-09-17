import CoreGraphics
import Testing
@testable import Graphghan

/// `ChartBand.clampedDrag` is the pure arithmetic behind the band's drag: no rendering, no gesture
/// plumbing, just the invariant that `offsetX - drag` always lands inside `[0, maxOffset]`.
@Suite struct ChartBandDragTests {
    @Test func clampedDragKeepsTheOffsetInsideTheChart() {
        // Past the left edge: the offset would go negative, so the drag clamps down to offsetX.
        #expect(ChartBand.clampedDrag(500, offsetX: 100, maxOffset: 1146) == 100)
        // Past the right edge: the offset would exceed maxOffset, so the drag clamps up to offsetX - maxOffset.
        // Cast on the right: a bare Int arithmetic literal here trips the Swift Testing `#expect`
        // macro defect noted in BandLayoutTests.swift; the values are exactly equal.
        #expect(ChartBand.clampedDrag(-2000, offsetX: 100, maxOffset: 1146) == CGFloat(100 - 1146))
        // Inside the range: unchanged.
        #expect(ChartBand.clampedDrag(40, offsetX: 100, maxOffset: 1146) == 40)
    }
}
