import CoreGraphics

/// The look-ahead view's zoom (look-ahead zoom spec §3, #250): how far in it goes, where the chart
/// sits when the view opens, and when a spread means "back to the row". Pure, so the rules are
/// value tests; `LookAheadZoomSurface` supplies the fingers and the physics.
enum LookAheadZoom {
    /// How far a spread at the limit has to open to mean "back to the row" (spec §3.4): the 1.2 the
    /// two-level pinch always used.
    static let returnFactor: CGFloat = 1.2

    /// Fully zoomed in, a cell is as wide as the band draws it, so the two views meet at one scale.
    /// A chart whose fitted cells are already that wide does not zoom.
    static func maxZoom(fittedWidth: CGFloat, chartWidth: Int) -> CGFloat {
        guard fittedWidth > 0, chartWidth > 0 else { return 1 }
        return max(1, BandLayout.cell * CGFloat(chartWidth) / fittedWidth)
    }

    /// Where the chart sits in a viewport at `zoom`, before a finger has moved it. On an axis where
    /// it is no larger than the viewport it is centred, which at zoom 1 is the fitted rect. Where it
    /// is larger, the point `focus` (unit coordinates in the chart) goes to the viewport's centre,
    /// or as near as the chart's edges allow, so the view never opens past an edge.
    static func rect(fitted: CGSize, in viewport: CGSize, zoom: CGFloat, focus: CGPoint) -> CGRect {
        func origin(_ content: CGFloat, _ view: CGFloat, _ f: CGFloat) -> CGFloat {
            content <= view ? (view - content) / 2 : -min(max(0, f * content - view / 2), content - view)
        }
        let size = CGSize(width: fitted.width * zoom, height: fitted.height * zoom)
        return CGRect(x: origin(size.width, viewport.width, focus.x), y: origin(size.height, viewport.height, focus.y),
                      width: size.width, height: size.height)
    }

    /// The current row's centre in the chart's unit coordinates: what the view opens on.
    static func focus(gridRow: Int?, chartHeight: Int) -> CGPoint {
        guard let gridRow, chartHeight > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: 0.5, y: (CGFloat(gridRow) + 0.5) / CGFloat(chartHeight))
    }

    /// A spread returns to the band when the view was already as far in as it goes when the fingers
    /// came down: there is nothing closer to show but the band. A spread that only arrives at the
    /// limit stops there, however hard it was thrown, so zooming in never drops her out of the view
    /// by accident. On a chart that cannot zoom the limit is where it starts, which is the rule the
    /// two-level pinch had.
    static func returnsToBand(startZoom: CGFloat, pinchScale: CGFloat, maxZoom: CGFloat) -> Bool {
        startZoom >= maxZoom * 0.99 && pinchScale > returnFactor
    }
}
