import CoreGraphics
import SwiftUI
import Testing
import UIKit
import GraphghanCore
@testable import Graphghan

/// The look-ahead view's zoom (#250): the pure rules, then the scroll view that applies them.
@MainActor
@Suite struct LookAheadZoomTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let viewport = CGSize(width: 366, height: 370)
    static let fitted = BandLayout.wholeChartRect(chart: chart, in: viewport)

    // MARK: the rules

    @Test func fullyZoomedInACellIsAsWideAsTheBandDrawsIt() {
        let limit = LookAheadZoom.maxZoom(fittedWidth: Self.fitted.width, chartWidth: Self.chart.width)
        #expect(limit > 1)
        #expect(abs(Self.fitted.width * limit / CGFloat(Self.chart.width) - BandLayout.cell) < 0.0001)
    }

    @Test func aChartAlreadyAtStitchScaleDoesNotZoom() {
        #expect(LookAheadZoom.maxZoom(fittedWidth: 300, chartWidth: 20) == 1)
        #expect(LookAheadZoom.maxZoom(fittedWidth: 0, chartWidth: 20) == 1)
    }

    @Test func atZoomOneTheChartIsTheFittedRect() {
        let rect = LookAheadZoom.rect(fitted: Self.fitted.size, in: Self.viewport, zoom: 1, focus: CGPoint(x: 0.5, y: 0.9))
        #expect(abs(rect.minX - Self.fitted.minX) < 0.0001 && abs(rect.minY - Self.fitted.minY) < 0.0001)
        #expect(rect.size == Self.fitted.size)
    }

    @Test func zoomedInTheFocusIsCentredWhereTheEdgesAllow() {
        let fitted = CGSize(width: 200, height: 400), viewport = CGSize(width: 300, height: 400)
        // Twice the size: 400 x 800 in 300 x 400. The middle of the chart goes to the middle of the band.
        let mid = LookAheadZoom.rect(fitted: fitted, in: viewport, zoom: 2, focus: CGPoint(x: 0.5, y: 0.5))
        #expect(mid == CGRect(x: -50, y: -200, width: 400, height: 800))
        // A row near the bottom cannot be centred without showing past the chart's end: the end is pinned.
        let low = LookAheadZoom.rect(fitted: fitted, in: viewport, zoom: 2, focus: CGPoint(x: 0.5, y: 0.98))
        #expect(low.maxY == viewport.height)
        let high = LookAheadZoom.rect(fitted: fitted, in: viewport, zoom: 2, focus: CGPoint(x: 0.5, y: 0.01))
        #expect(high.minY == 0)
        // Still narrower than the band at 1.2: centred across, scrolled down.
        let narrow = LookAheadZoom.rect(fitted: fitted, in: viewport, zoom: 1.2, focus: CGPoint(x: 0.5, y: 0.5))
        #expect(abs(narrow.minX - 30) < 0.0001 && abs(narrow.minY + 40) < 0.0001)
    }

    @Test func theFocusIsTheCurrentRowsCentre() {
        #expect(LookAheadZoom.focus(gridRow: 0, chartHeight: 10) == CGPoint(x: 0.5, y: 0.05))
        #expect(LookAheadZoom.focus(gridRow: nil, chartHeight: 10) == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func aSpreadAtTheLimitReturnsToTheBand() {
        // Fully zoomed in, the old 1.2 is all it takes.
        #expect(LookAheadZoom.returnsToBand(startZoom: 3, pinchScale: 1.25, maxZoom: 3))
        #expect(!LookAheadZoom.returnsToBand(startZoom: 3, pinchScale: 1.2, maxZoom: 3))
        // A spread that only gets there stops there, however far it was thrown.
        #expect(!LookAheadZoom.returnsToBand(startZoom: 1, pinchScale: 9, maxZoom: 3))
        #expect(!LookAheadZoom.returnsToBand(startZoom: 2.9, pinchScale: 4, maxZoom: 3))
        // Nearly there is not there (CodeRabbit on #251).
        #expect(!LookAheadZoom.returnsToBand(startZoom: 2.98, pinchScale: 1.21, maxZoom: 3))
        // A chart that cannot zoom keeps the two-level rule exactly.
        #expect(!LookAheadZoom.returnsToBand(startZoom: 1, pinchScale: 1.2, maxZoom: 1))
        #expect(LookAheadZoom.returnsToBand(startZoom: 1, pinchScale: 1.21, maxZoom: 1))
        // Pinching in never does.
        #expect(!LookAheadZoom.returnsToBand(startZoom: 3, pinchScale: 0.5, maxZoom: 3))
    }

    // MARK: the scroll view

    private func surface(zoom: CGFloat, focus: CGPoint = CGPoint(x: 0.5, y: 0.5), limit: CGFloat = 3) -> (ZoomScrollView, () -> (CGRect, CGFloat)?) {
        let view = ZoomScrollView()
        let box = Box()
        view.onChange = { box.last = ($0, $1) }
        view.frame = CGRect(origin: .zero, size: CGSize(width: 300, height: 400))
        view.configure(fitted: CGSize(width: 200, height: 400), maxZoom: limit, zoom: zoom, focus: focus)
        view.layoutIfNeeded()
        return (view, { box.last })
    }
    private final class Box { var last: (CGRect, CGFloat)? }

    @Test func theSurfaceOpensFittedAndCentred() throws {
        let (view, last) = surface(zoom: 1)
        #expect(view.chartRect == CGRect(x: 50, y: 0, width: 200, height: 400))
        #expect(view.minimumZoomScale == 1 && view.maximumZoomScale == 3)
        let reported = try #require(last())
        #expect(reported.0 == view.chartRect && reported.1 == 1)
    }

    @Test func theSurfaceOpensWhereTheRuleSays() {
        for (zoom, focus) in [(CGFloat(2), CGPoint(x: 0.5, y: 0.98)), (2, CGPoint(x: 0.5, y: 0.3)), (1.2, CGPoint(x: 0.5, y: 0.5)), (3, CGPoint(x: 0.5, y: 0.01))] {
            let (view, _) = surface(zoom: zoom, focus: focus)
            let rule = LookAheadZoom.rect(fitted: CGSize(width: 200, height: 400), in: CGSize(width: 300, height: 400), zoom: zoom, focus: focus)
            #expect(abs(view.chartRect.minX - rule.minX) < 0.01 && abs(view.chartRect.minY - rule.minY) < 0.01, "zoom \(zoom) focus \(focus)")
            #expect(abs(view.chartRect.width - rule.width) < 0.01 && abs(view.chartRect.height - rule.height) < 0.01)
        }
    }

    @Test func anOpeningZoomPastTheLimitIsHeldToIt() {
        let (view, _) = surface(zoom: 9)
        #expect(view.zoomScale == 3)
    }

    @Test func zoomingAndPanningReportWhereTheChartIs() throws {
        let (view, last) = surface(zoom: 1)
        view.setZoomScale(2, animated: false)
        view.layoutIfNeeded()
        #expect(view.chartRect.size == CGSize(width: 400, height: 800))
        view.contentOffset = CGPoint(x: 100, y: 400)
        view.layoutIfNeeded()
        let reported = try #require(last())
        #expect(reported.0 == CGRect(x: -100, y: -400, width: 400, height: 800) && reported.1 == 2)
    }

    // MARK: in the band

    /// The band on screen, with the zoom surface it lays over the whole view.
    private func hosted(_ band: ChartBand) throws -> (UIWindow, ZoomScrollView) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 366, height: 420)
        window.rootViewController = UIHostingController(rootView: band)
        window.isHidden = false
        window.layoutIfNeeded()
        settle()
        func find(_ view: UIView) -> ZoomScrollView? { (view as? ZoomScrollView) ?? view.subviews.lazy.compactMap(find).first }
        return (window, try #require(find(window)))
    }
    /// One turn of the run loop: what the surface reports becomes state, and the band answers it.
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    private func band(openingZoom: CGFloat = 1) -> ChartBand {
        let seq = try! WorkSequence(chart: Self.chart)
        return ChartBand(chart: Self.chart, sequence: seq, cursor: Cursor(row: 60, run: 0), segmentLabel: nil, mode: .whole, style: .fabric,
                         onAdvance: {}, onJump: { _, _ in }, onToggleMode: {}, returnLabel: "Back to Row 60", openingZoom: openingZoom)
    }

    /// The band redraws from what the surface reports and tells the surface nothing back that
    /// would move it: a zoom in stays in, and a zoom back out stays out.
    @Test func theBandLeavesTheSurfaceWhereTheFingersPutIt() throws {
        let (window, view) = try hosted(band())
        defer { window.isHidden = true }
        #expect(view.zoomScale == 1 && view.maximumZoomScale > 3)
        let fitted = view.chartRect
        view.setZoomScale(3, animated: false)
        view.layoutIfNeeded()
        settle()
        #expect(view.zoomScale == 3)
        #expect(abs(view.chartRect.width - fitted.width * 3) < 0.01)
        view.contentOffset.y += 40
        view.layoutIfNeeded()
        let panned = view.chartRect
        settle()
        #expect(view.chartRect == panned)
        view.setZoomScale(1.5, animated: false)
        view.layoutIfNeeded()
        settle()
        #expect(view.zoomScale == 1.5)
        view.setZoomScale(1, animated: false)
        view.layoutIfNeeded()
        settle()
        #expect(view.zoomScale == 1)
        #expect(abs(view.chartRect.minX - fitted.minX) < 0.01 && abs(view.chartRect.minY - fitted.minY) < 0.01)
    }

    /// Opened at the limit, the zoom the surface reads back is the limit near enough that the next
    /// spread is one that began there (spec §3.4).
    @Test func reopenedFullyZoomedInASpreadReturns() throws {
        let (window, view) = try hosted(band(openingZoom: 99))
        defer { window.isHidden = true }
        #expect(LookAheadZoom.returnsToBand(startZoom: view.zoomScale, pinchScale: 1.3, maxZoom: view.maximumZoomScale))
        view.setZoomScale(view.maximumZoomScale * 0.5, animated: false)
        view.layoutIfNeeded()
        view.setZoomScale(view.maximumZoomScale, animated: false)
        view.layoutIfNeeded()
        #expect(LookAheadZoom.returnsToBand(startZoom: view.zoomScale, pinchScale: 1.3, maxZoom: view.maximumZoomScale))
    }

    /// Opened zoomed in, the surface is where the band drew its first frame: on the current row.
    @Test func theBandOpensTheSurfaceOnTheCurrentRow() throws {
        let (window, view) = try hosted(band(openingZoom: 3))
        defer { window.isHidden = true }
        #expect(view.zoomScale == 3)
        // Row 60 of 184, bottom-up, is grid row 124: its centre is mid-band.
        let y = view.chartRect.minY + view.chartRect.height * 124.5 / 184
        #expect(abs(y - view.bounds.height / 2) < 0.5)
    }

    @Test func aChangeOfSizePlacesTheChartAgainAtTheSameZoom() {
        let (view, _) = surface(zoom: 2)
        view.configure(fitted: CGSize(width: 150, height: 300), maxZoom: 4, zoom: 2, focus: CGPoint(x: 0.5, y: 0.5))
        view.frame.size = CGSize(width: 300, height: 300)
        view.layoutIfNeeded()
        #expect(view.chartRect == CGRect(x: 0, y: -150, width: 300, height: 600))
        #expect(view.maximumZoomScale == 4)
    }
}
