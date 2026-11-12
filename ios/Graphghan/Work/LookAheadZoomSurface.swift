import SwiftUI
import UIKit

/// The fingers of the look-ahead view (look-ahead zoom spec §4, #250): a clear `UIScrollView` laid
/// over the chart. It draws nothing. It owns the pinch, the pan, the momentum and the bounce, and
/// says where the chart now is; `ChartBand` redraws the chart there, sharp at every scale, with
/// its marks at their own size. A scaled picture of the fitted chart would blur and would blow the
/// labels up with it.
struct LookAheadZoomSurface: UIViewRepresentable {
    /// The chart's size at zoom 1.
    let fitted: CGSize
    let maxZoom: CGFloat
    /// What the view opens on, in the chart's unit coordinates (`LookAheadZoom.focus`).
    let focus: CGPoint
    /// The zoom the view opens at and leaves behind, always inside `1...maxZoom`.
    @Binding var zoom: CGFloat
    /// The chart's rect in this view's coordinates, as the scroll view has it now.
    @Binding var chartRect: CGRect?
    let onTap: () -> Void
    /// A spread with the view already fully zoomed in (spec §3.4); nil where there is no band to return to.
    let onSpreadAtLimit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        let coordinator = context.coordinator
        view.onChange = { [weak coordinator] rect, zoom in coordinator?.moved(rect: rect, zoom: zoom) }
        view.addGestureRecognizer(UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped)))
        // The scroll view's own pinch is switched off on a chart that cannot zoom, and at the limit
        // its scale only rubber-bands; this one always runs and reports what the fingers did.
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:)))
        pinch.delegate = coordinator
        view.addGestureRecognizer(pinch)
        view.configure(fitted: fitted, maxZoom: maxZoom, zoom: zoom, focus: focus)
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        context.coordinator.parent = self
        view.configure(fitted: fitted, maxZoom: maxZoom, zoom: zoom, focus: focus)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: LookAheadZoomSurface
        private var pinchStart: CGFloat = 1
        /// Set once a spread has asked for the band: the view is on its way out, and what its
        /// bounce does on the way must not be remembered as the zoom.
        private var returning = false

        init(_ parent: LookAheadZoomSurface) { self.parent = parent }

        func moved(rect: CGRect, zoom: CGFloat) {
            guard !returning else { return }
            if parent.chartRect != rect { parent.chartRect = rect }
            // Past either limit the scroll view is mid-bounce; the zoom to keep is the one it settles on.
            let kept = min(max(1, zoom), parent.maxZoom)
            if abs(parent.zoom - kept) > 0.0001 { parent.zoom = kept }
        }

        @objc func tapped() { parent.onTap() }

        @objc func pinched(_ pinch: UIPinchGestureRecognizer) {
            switch pinch.state {
            case .began:
                pinchStart = parent.zoom
            case .ended:
                guard let back = parent.onSpreadAtLimit,
                      LookAheadZoom.returnsToBand(startZoom: pinchStart, pinchScale: pinch.scale, maxZoom: parent.maxZoom) else { return }
                // The view is on its way out: what its bounce does from here is not a zoom to keep.
                returning = true
                back()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// The scroll view under `LookAheadZoomSurface`: an empty view the size of the chart to zoom, kept
/// centred while it is smaller than the bounds, as a photo viewer does. Its own delegate, so it
/// zooms and reports with nothing else attached.
final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let zoomView = UIView()
    /// The chart's rect in the bounds' coordinates and the zoom scale, on every change.
    var onChange: ((CGRect, CGFloat) -> Void)?

    private var fitted: CGSize = .zero
    private var maxZoom: CGFloat = 1
    private var openingZoom: CGFloat = 1
    private var focus = CGPoint(x: 0.5, y: 0.5)
    /// The fitted size and bounds the content was last placed for; a change in either places it again.
    private var placed: (fitted: CGSize, bounds: CGSize)?
    private var reported: (rect: CGRect, zoom: CGFloat)?

    init() {
        super.init(frame: .zero)
        addSubview(zoomView)
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        scrollsToTop = false
        bouncesZoom = true
        // Fitted, there is nothing to scroll, and a scroll view with nothing to scroll lets a drag
        // through to whatever is behind it, which here is the screen's swipe back a stitch. With a
        // bounce the drag is always this view's own, as it is in a photo viewer.
        alwaysBounceVertical = true
        alwaysBounceHorizontal = true
        delegate = self
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { setNeedsLayout() }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    /// The chart's rect in the bounds' coordinates.
    var chartRect: CGRect { zoomView.frame.offsetBy(dx: -contentOffset.x, dy: -contentOffset.y) }

    func configure(fitted: CGSize, maxZoom: CGFloat, zoom: CGFloat, focus: CGPoint) {
        openingZoom = zoom
        self.focus = focus
        guard fitted != self.fitted || maxZoom != self.maxZoom else { return }
        self.fitted = fitted
        self.maxZoom = maxZoom
        placed = nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, fitted.width > 0, fitted.height > 0 else { return }
        if placed.map({ $0.fitted != fitted || $0.bounds != bounds.size }) ?? true { place() }
        centre()
        let now = (rect: chartRect, zoom: zoomScale)
        if reported.map({ $0.rect != now.rect || $0.zoom != now.zoom }) ?? true {
            reported = now
            onChange?(now.rect, now.zoom)
        }
    }

    /// Lays the content out afresh at the opening zoom, on the focus (`LookAheadZoom.rect`): when
    /// the view opens, and again if the band changes size under it.
    private func place() {
        placed = (fitted, bounds.size)
        minimumZoomScale = 1
        maximumZoomScale = 1
        zoomScale = 1
        zoomView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        maximumZoomScale = maxZoom
        let zoom = min(max(1, openingZoom), maxZoom)
        zoomScale = zoom
        let rect = LookAheadZoom.rect(fitted: fitted, in: bounds.size, zoom: zoom, focus: focus)
        contentOffset = CGPoint(x: max(0, -rect.minX), y: max(0, -rect.minY))
    }

    /// Smaller than the bounds on an axis, the content sits in the middle of it.
    private func centre() {
        var frame = zoomView.frame
        frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
        if frame.origin != zoomView.frame.origin { zoomView.frame = frame }
    }
}
