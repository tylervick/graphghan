# Graphghan: zoom in the look-ahead view

Date: 2026-11-11
Status: direction from Tyler in conversation 2026-11-11 ("existing interactions stay intact if
possible, but we want the native ability to zoom out/in"); the questions were skipped, so every
decision below not in that sentence is the builder's call and is marked so in §2.
Builds on: `2026-11-09-look-ahead-design.md` (the look-ahead view, its marks, `LookAheadLayout`).
Amends that spec's §5.4, §9 and §10, which ruled a zoom out two days before this feedback arrived.
Closes the design step for: #250. Takes the continuous-zoom half of #89; what is left of #89 is in §8.

## 1. Purpose

A TestFlight tester on build 35, the first with the look-ahead view, at Row 23 of Craigh na Dun:
"I can either zoom all the way out or all the way in, would like to be able to control zoom on
some page."

The band has two scales. At stitch scale a cell is 8 pt and about five rows are on screen. In the
look-ahead view the whole chart is fitted to the band, which on a phone is a little over 1 pt a
stitch: the stretches are marked, but the lettering cannot be read and the labels cover half of
it. The pinch switches between the two. Nothing shows the next thirty rows at a size where the
stitches can be seen, which is what looking ahead is for.

## 2. Decisions

1. **The look-ahead view zooms; the band at stitch scale does not change.** (Tyler: the native
   ability to zoom. Where it lives is the builder's call: the screenshot is of the look-ahead
   view, and the band's fixed geometry is what the ring, the ruler and the tap depend on.)
2. **The zoom is the platform's.** A `UIScrollView` supplies the pinch anchored under the
   fingers, the pan with momentum, and the bounce at the limits. (Tyler: native. A hand-rolled
   drag has no momentum, which is #142's complaint about the band.)
3. **The chart is redrawn at each scale, not magnified.** Cells stay sharp, and the marks (row
   numbers, labels, hairlines) stay their own size. (Builder's call.)
4. **It goes from fitted to stitch scale and no further.** Fully zoomed in, a cell is 8 pt wide,
   the width the band draws it. (Builder's call. A scale past the band's is #89's magnified
   level and waits on #86.)
5. **Every existing way in and out keeps working.** Tap returns; the pill, the header button,
   the row number and the look-ahead line toggle; a pinch in on the band opens the view. The one
   interaction that has to change is the spread in the view, which now zooms; §3.4 says what is
   kept of it. (Tyler: existing interactions intact if possible.)
6. **The view remembers its zoom while the Work screen is open, and opens on the current row.**
   (Builder's call. Opening fitted every time would make her pinch again on every look.)

## 3. Behaviour (normative)

### 3.1 Range

Zoom 1 is the fitted view, exactly as the look-ahead spec draws it. The limit is the zoom at
which a cell is `BandLayout.cell` (8 pt) wide: `max(1, 8 × chart.width / fittedWidth)`. A chart
whose fitted cells are already 8 pt or wider has a limit of 1 and does not zoom.

### 3.2 Pinch and pan

Inside the chart's area of the look-ahead view (everything above the return pill's strip):

- A pinch zooms about the point between the fingers, continuously, between 1 and the limit,
  with the scroll view's bounce at both ends.
- A drag pans when the chart is larger than the area, with momentum and edge bounce. Fitted, a
  drag only bounces.
- On an axis where the chart is no larger than the area it is centred, as the fitted view is.
- A tap returns to the band, as before.

A drag that starts on the chart never reaches the screen's swipe-back (work-screen spec §5.4),
at any zoom. Before this spec the whole view swallowed drags for the same reason.

### 3.3 Opening

The view opens at the zoom it was last left at, on this visit to the Work screen; the first time,
fitted. Zoomed in, it opens with the current row's centre at the centre of the area, or as near
as the chart's edges allow. Where she had panned to is not kept: every look ahead starts from
the row she is on. `LookAheadZoom.rect` is that rule, and both the first frame the band draws and
the scroll view's opening position come from it. Nothing is stored (§6).

### 3.4 The spread that returns

Before this spec a spread of more than 1.2 in the whole view returned to the band. Now:

- A spread zooms in. One that only arrives at the limit stops there, however far the fingers
  went, so zooming in never drops her out of the view.
- A spread that **begins** with the view already at the limit, and opens past 1.2, returns to
  the band: there is nothing closer to show but the band.
- On a chart with a limit of 1 the view is always at the limit, so the old rule holds exactly.
- Finished, the band is locked to the whole view and there is no band to return to: the spread
  does nothing there. (Before, it closed the screen, as the tap does. The tap still does.)

A pinch in on the band (below 0.8) opens the look-ahead view, unchanged.

### 3.5 Marks while zoomed

The look-ahead spec's marks, with three adjustments so they stay useful when the chart's edges
are off the band:

- **Edges.** Row ticks sit on the leading edge of what is visible of the chart; the bracket and
  the labels on the trailing edge of it. Hairlines span what is visible.
- **Tick interval.** The look-ahead spec's rule (every 20 passes over 60, every 10 over 20, else
  every 5) applied to the pass count divided by the zoom, rounded up. Craigh na Dun's 184 passes
  tick every 20 fitted and every 10 from a zoom of a little over 3.
- **Labels.** Still only the current stretch and those ahead, still never overlapping, still at
  most eight, but chosen among the stretches that show: a stretch off the band takes none of the
  eight. A stretch only partly on the band is labelled at the middle of the part that shows, and
  not at all if that part is shorter than a pill (16 pt) while the stretch itself is not.

At zoom 1 all three reduce to the look-ahead spec's behaviour.

### 3.6 Drawing

Cell edges are rounded to whole pixels, so neighbouring cells share an edge. The whole view used
to overlap rows by 0.3 pt to hide seams, which drew the 28% rows ahead twice where they crossed:
a stripe through every unworked row, faint at fitted scale and plain when zoomed. Rows outside
the area are not drawn.

## 4. Structure

- `Work/LookAheadZoom.swift`: pure. The limit, the opening rect, the focus, the returning-spread
  rule.
- `Work/LookAheadZoomSurface.swift`: a `UIViewRepresentable` over `ZoomScrollView`, a clear
  scroll view whose zooming view is an empty view the size of the fitted chart, kept centred
  while smaller than the bounds. It draws nothing and reports the chart's rect in its own
  coordinates on every change. Its coordinator owns a tap recognizer and its own pinch
  recognizer, which exists only to apply §3.4 (the scroll view's pinch is disabled at a limit of
  1 and rubber-banded past the limit).
- `ChartBand`: in the whole view the canvas draws the chart at the rect the surface reports. The
  return pill becomes a SwiftUI view in its own strip under the canvas, so the canvas is exactly
  the chart's area and the surface overlays exactly that. The surface is laid over the canvas
  after the band's gestures, so those never see a touch meant for it.
- `LookAheadLayout` takes the visible range and the zoom (§3.5); both default to the fitted view.
- `EnvironmentValues.rendersToImage`: `ImageRenderer` paints a placeholder where a UIKit view
  stands, so the snapshot harness sets this and the band leaves the surface out. The band's own
  gestures then answer in the whole view as they did before, which is also the fallback.

## 5. Accessibility

The band is hidden from VoiceOver and stays so; the spoken way to what is ahead is the panel's
"What's ahead" action, unchanged. The marks are chart annotations at a fixed size, as before;
zooming is how they are made larger relative to the chart. Reduce Motion: the zoom follows the
fingers and animates nothing of its own.

## 6. Compatibility

Nothing is stored: no SwiftData field, no progress document key. The zoom lives in view state
and is gone when the Work screen closes. The Live Activity, the intents, written pieces, the
chart browser and the site are untouched.

## 7. Testing

- `LookAheadZoomTests`: the limit; the opening rect at zoom 1 and zoomed, at both edges and
  narrower than the area; the returning-spread rule including the limit-of-1 case; `ZoomScrollView`
  opening where the rule says, holding an opening zoom to the limit, reporting after a zoom and a
  pan, and placing again when the size changes; and the band hosted in a window, zoomed in and
  back out through its surface, to pin that the band never moves the surface in answer to what
  the surface reports.
- `LookAheadLayoutTests`: the tick interval with zoom; a visible range covering the chart changes
  nothing; zoomed and panned, marks are chosen among what shows.
- `ChartBandTests`: `band-look-ahead-zoomed` (Row 60 at 2.5). `band-whole`, `band-look-ahead`,
  `band-look-ahead-ax5`, `band-look-ahead-late` and `work-finished` are re-recorded for §3.6.
- On a device: the pinch, the pan, the tap, the swipe-back not firing, the reopening and the
  returning spread cannot be driven from a unit test and are walked by hand or on a cloud device.

## 8. Rulings and follow-ons

| issue | ruling |
|---|---|
| #250 | closed by this spec's PR |
| #89 | the continuous zoom lands here, in the look-ahead view; a magnified scale past the band's, a zoom on the band itself, and keeping the scale per project stay open there |
| #172 | separate; the chart browser is a different screen with its own pinch |
| #247 | unaffected; a long-press in the look-ahead view still does nothing |

## 9. Non-goals

- Any change to the band at stitch scale, to the panel, or to how a tap advances.
- A scale past stitch scale, and a zoom that is kept between visits to the Work screen (#89).
- Double-tap to zoom: a tap returns, and waiting to see whether a second follows would slow it.
- Cell hairlines or stitch counts in the zoomed view; it is a picture of what is coming, and the
  band is where stitches are counted.
- The chart browser (#172).
