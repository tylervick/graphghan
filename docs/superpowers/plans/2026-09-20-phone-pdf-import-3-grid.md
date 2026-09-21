# Phone PDF Import, PR 3: The Grid — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A PDF with a picture of the chart opens on the phone into that chart in seconds, with the written rows read afterwards as the check and the check's outcome recorded on the chart and shown on the detail screen (spec §4.2, §6.3).

**Architecture:** `rasterchart.py` is ported function for function into `GraphghanCore` as `GridReader` (line finding, lattice fitting, cell sampling, palette clustering), tested against synthetic images the Python draws and against the committed own-PDF rendered by PDFKit. `PDFImporter` gains the grid path between the own-PDF path and the rows path: each page rendered under the §5.1 budget, the largest region taken, `GridChart` turning it into a `ChartDraft`. The row check is a second task the sheet runs after the chart is on screen: the existing `RowReading` reader over the page texts, then `RowsChart.crossCheck` (a port of `_match_by_rows` and `cross_check`); "Add to library" re-encodes the draft with the check's record in `ext.graphghan.import`.

**Tech Stack:** Swift 6 (GraphghanCore, plain `[UInt8]` loops over an RGB buffer; CoreGraphics/ImageIO to decode PNGs), PDFKit in the app for rendering, Swift Testing, Python (Pillow, numpy) only to draw the fixtures and record the answers.

**Spec:** `docs/superpowers/specs/2026-09-20-phone-pdf-import-design.md` (§4.2, §5.1 step 2, §5.2 "Chart found", §5.4, §6.2, §6.3, §7, §8 item 3, §9, §11). PR 1 was `2026-09-20-phone-pdf-import-1-own-pdf.md`, PR 2 `2026-09-20-phone-pdf-import-2-written-rows.md`.

## Global Constraints

- Deployment target iOS 17; the grid path and its sentences run there. The row check needs the model: `AppModel.rowReader` is nil below iOS 26 or without Apple Intelligence, and the check is then recorded `unavailable` (spec §7).
- Constants copied from `rasterchart.py`, same names, same values: `EDGE_THRESHOLD = 16`, `BRIDGE = 3`, `MERGE_PX = 8`, `MIN_LINE_PX = 40`, `MIN_LINES = 5`, `GAP_TOLERANCE = 0.25`, `CENTRE_FRACTION = 0.4`, `MAX_NOISE = 12.0`, `MAX_SILENT = 40`, `MAX_PIXELS = 40_000_000`; `RENDER_SCALE = 4` from `importers.py`; `MISMATCH_LIMIT = 0.10` from `prose.py`.
- Render budget (spec §5.1): at most 40 million pixels a page, from 4× halving until it fits; a page over the cap at 1× is skipped with "page N is too large to read".
- A region counts when it is at least 8×8 cells and its noise is at most `MAX_NOISE` (spec §5.1); the largest by cell count across all pages is the chart.
- `ext.graphghan.import = { source: "pdf", grid: true, check: finished|stopped|unavailable|none, rows_checked: n, rows_total: m, rows_disagree: [..], gauge_printed: bool }` plus, when the rows could not be compared at all, `problem: "<sentence>"`. `rows_total` (for "N+1–M not checked") and `problem` are amendments to §6.3 made in Task 8. The chart id ignores `ext`.
- Sentences are fixed and tested (§5.4, §6.3): "Rows 12, 40 and 41 disagree with the chart. The chart is as drawn; check those rows against the PDF." / "Written rows checked up to row N; N+1–M not checked." / "Written rows not checked on this iPhone." / "Checking written row N of M…" / "Skip the check".
- Design tokens only (`Font.Heather.*`, `Color.ink/ink2/...`); `DesignRulesTests` forbids `.font(.headline)` and `.secondary`.
- Copyrighted PDFs are never committed. The real fixtures under `fixtures/import/real/` stay gitignored; the manual gate (§8 item 3) runs on the mini as a skip-if-absent test (Task 8).
- Deviation from §6.2, stated here: the port uses plain `[UInt8]` loops, not `vImage`. A page is at most 8 megapixels at 4× on Letter/A4, and the loops are a few passes over it; Task 3 prints the time for the Craigh page and Task 8's manual gate records it. If a page takes over two seconds on a device, `vImage` is the follow-on.
- Not in this PR: `box_rows` (Outlander's rows-as-boxes layout; noted on #151), taking the key's names onto the grid palette (#166), stitching an own PDF's tiles (that PDF goes through §4.1).
- Test commands: core `cd ios/Packages/GraphghanCore && swift test`; app `cd ios && xcodegen generate --quiet && DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer xcodebuild test -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E '✘|Test run with|error:'`; Python `mise run check`. A failing app run then sits ten minutes in `simctl diagnose`: kill it, the results are already in the `.xcresult`.

---

## File Structure

| File | Responsibility |
|---|---|
| `fixtures/import/grid/generate.py` | Draws the synthetic charts `tests/test_rasterchart.py` draws and records the Python reader's answers beside them. |
| `fixtures/import/grid/*.png`, `*.json` | The images and the answers (regions, cells, palette). |
| `tests/test_grid_fixtures.py` | Regenerating the fixtures reproduces the committed files. |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridImage.swift` | An RGB byte image: from PNG data, from raw bytes; grey; sub-rectangles. |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridLines.swift` | `_close`, `_runs`, `_lines`, `_merge`, `_clusters`, `_pitch`, `_fits`, `_overlap`: masks to candidate lines. |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridReader.swift` | `Region`, `_refine_axis`, `_band_noise`, `find_regions`, `read_region`, `cell_noise`. |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridColours.swift` | Lab, `snap_to_palette`, `cluster_palette`, `name_colour`, `code(i)`. |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridChart.swift` | A region on an image to a `ChartDraft` with `ext.graphghan.import`. |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/RowsChart.swift` | gains `crossCheck` (`_match_by_rows` + `cross_check`) and `CheckRecord`. |
| `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/Grid*Tests.swift` | Fixture-driven tests for each of the above. |
| `ios/Graphghan/Services/PageRenderer.swift` | PDFKit page to `GridImage` under the §5.1 budget. |
| `ios/Graphghan/Services/PDFImporter.swift` | The grid path, `check(_:progress:)`, `save(_:check:)`. |
| `ios/Graphghan/Patterns/PDFImportSheet.swift`, `AppModel.swift`, `PatternDetailContent.swift` | The check under "Chart found", Skip, Add-before-the-end, the detail sentences. |
| `ios/Tests/PDFImportTests.swift`, `PDFImportSheetTests.swift`, `PDFImportRealTests.swift` | Grid path, check outcomes, sheet states, the skip-if-absent real gate. |

---

### Task 1: Grid fixtures drawn by Python, answers recorded

**Files:**
- Create: `fixtures/import/grid/generate.py`
- Create: `fixtures/import/grid/README.md`
- Create: `tests/test_grid_fixtures.py`
- Commit: `fixtures/import/grid/one-grid.png/.json`, `two-grids.png/.json`, `symbols.png/.json`, `text-page.png/.json` (the photo case is drawn by the Swift test itself: noise does not compress, 968 KB as a PNG)

**Interfaces:**
- Produces: for each image `<name>.json` = `{"regions": [{"cols", "rows", "pitch": [px, py], "bbox": [x0, y0, x1, y1], "noise"}], "palette": [hexes] | null, "cells": [[int]] | null, "cluster": {"hexes": [...], "warnings": [...]} | null}`. `cells` are the Python `snap_to_palette` indexes over `PALETTE` for the first region; `cluster` is `cluster_palette` over that region's samples.

- [ ] **Step 1: Write the generator**

`fixtures/import/grid/generate.py`:

```python
"""Draw the synthetic charts tests/test_rasterchart.py draws and record what the Python grid
reader answers, so the Swift port (GraphghanCore GridReader) is held to the same answers.

Run: uv run python fixtures/import/grid/generate.py
tests/test_grid_fixtures.py fails if the committed files differ from a fresh generation.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from graphghan import rasterchart as rc

OUT = Path(__file__).resolve().parent
PALETTE = ["#f2e8d5", "#2b2f33", "#1e4d3a", "#d9a21b"]
RGB = [tuple(int(h[i : i + 2], 16) for i in (1, 3, 5)) for h in PALETTE]


def pattern(w, h):
    rng = np.random.default_rng(w * 1000 + h)
    a = rng.integers(0, len(PALETTE), size=(h, w))
    a[:, :3] = 1
    a[-2:, :] = 3
    return a


def draw_chart(a, cell=24, origin=(80, 60), numbers=True, symbols=False, bold_every=10, line=(140, 140, 140)):
    h, w = a.shape
    ox, oy = origin
    img = Image.new("RGB", (ox * 2 + w * cell, oy * 2 + h * cell), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for y in range(h):
        for x in range(w):
            d.rectangle([ox + x * cell, oy + y * cell, ox + (x + 1) * cell, oy + (y + 1) * cell], fill=RGB[a[y, x]])
            if symbols and (x + y) % 3 == 0:
                cx, cy = ox + (x + 0.5) * cell, oy + (y + 0.5) * cell
                d.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], outline=(0, 0, 0), width=2)
    for x in range(w + 1):
        bold = (w - x) % bold_every == 0
        d.line([(ox + x * cell, oy), (ox + x * cell, oy + h * cell)], fill=(0, 0, 0) if bold else line, width=3 if bold else 1)
    for y in range(h + 1):
        bold = (h - y) % bold_every == 0
        d.line([(ox, oy + y * cell), (ox + w * cell, oy + y * cell)], fill=(0, 0, 0) if bold else line, width=3 if bold else 1)
    if numbers:
        for x in range(w):
            d.text((ox + x * cell + 6, oy - 14), str(w - x), fill=(0, 0, 0))
        for y in range(h):
            d.text((ox - 24, oy + y * cell + 6), str(h - y), fill=(0, 0, 0))
    return img


def text_page():
    img = Image.new("RGB", (800, 1000), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for i in range(50):
        d.text((40, 20 + i * 19), "Row %d: ch 1, turn, 8 A, 14 B, 8 A (30 sts) and more words here" % i, fill=(0, 0, 0))
    return img


def photo():
    rng = np.random.default_rng(1)
    img = Image.fromarray(rng.integers(0, 255, size=(600, 600, 3), dtype=np.uint8))
    d = ImageDraw.Draw(img)
    for k in range(0, 600, 30):
        d.line([(k, 0), (k, 599)], fill=(0, 0, 0), width=2)
        d.line([(0, k), (599, k)], fill=(0, 0, 0), width=2)
    return img


def answer(img: Image.Image, want_cells: bool) -> dict:
    regions = rc.find_regions(img)
    out = {
        "regions": [
            {"cols": r.cols, "rows": r.rows, "pitch": [round(r.pitch[0], 3), round(r.pitch[1], 3)],
             "bbox": list(r.bbox), "noise": round(r.noise, 3)}
            for r in regions
        ],
        "palette": PALETTE if want_cells else None,
        "cells": None,
        "cluster": None,
    }
    if want_cells and regions:
        samples = rc.read_region(img, regions[0])
        out["cells"] = rc.snap_to_palette(samples, PALETTE).tolist()
        idx, hexes, warnings = rc.cluster_palette(samples)
        out["cluster"] = {"hexes": hexes, "warnings": warnings, "cells": idx.tolist()}
    return out


def images() -> dict[str, tuple[Image.Image, bool]]:
    left, right = draw_chart(pattern(12, 20)), draw_chart(pattern(15, 20))
    two = Image.new("RGB", (left.width + right.width, left.height), (255, 255, 255))
    two.paste(left, (0, 0))
    two.paste(right, (left.width, 0))
    return {
        "one-grid": (draw_chart(pattern(37, 29)), True),
        "two-grids": (two, True),
        "symbols": (draw_chart(pattern(16, 12), cell=32, symbols=True), True),
        "text-page": (text_page(), False),
        "photo": (photo(), False),
    }


def main() -> None:
    for name, (img, want_cells) in images().items():
        img.save(OUT / f"{name}.png", optimize=True)
        (OUT / f"{name}.json").write_text(json.dumps(answer(img, want_cells), indent=1) + "\n", encoding="utf-8")
        print(f"wrote {name}: {img.width}x{img.height}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Write the round-trip test**

`tests/test_grid_fixtures.py`:

```python
"""The committed grid fixtures are what generate.py draws and what the reader answers today."""

import json
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRID = ROOT / "fixtures" / "import" / "grid"


def test_committed_grid_fixtures_regenerate_identically(tmp_path):
    gen = runpy.run_path(str(GRID / "generate.py"))
    for name, (img, want_cells) in gen["images"]().items():
        img.save(tmp_path / f"{name}.png", optimize=True)
        assert (tmp_path / f"{name}.png").read_bytes() == (GRID / f"{name}.png").read_bytes(), name
        assert gen["answer"](img, want_cells) == json.loads((GRID / f"{name}.json").read_text(encoding="utf-8")), name


def test_the_answers_are_what_the_unit_tests_assert():
    one = json.loads((GRID / "one-grid.json").read_text(encoding="utf-8"))
    assert [(r["cols"], r["rows"]) for r in one["regions"]] == [(37, 29)]
    two = json.loads((GRID / "two-grids.json").read_text(encoding="utf-8"))
    assert sorted((r["cols"], r["rows"]) for r in two["regions"]) == [(12, 20), (15, 20)]
    assert json.loads((GRID / "text-page.json").read_text(encoding="utf-8"))["regions"] == []
    assert json.loads((GRID / "photo.json").read_text(encoding="utf-8"))["regions"] == []
```

- [ ] **Step 3: Generate and run**

Run: `uv run python fixtures/import/grid/generate.py && uv run pytest tests/test_grid_fixtures.py -q`
Expected: four PNGs (the charts under 20 KB, the text page about 110 KB) and four JSON files; 2 passed.

- [ ] **Step 4: README and commit**

`fixtures/import/grid/README.md`:

```markdown
# Grid reader fixtures

Synthetic chart pictures, drawn by `generate.py` exactly as `tests/test_rasterchart.py` draws
them, with the Python grid reader's answers recorded beside each (`<name>.json`: regions, cells
snapped to the drawing palette, and the clustered palette). The Swift port in
`ios/Packages/GraphghanCore` (`GridReaderTests`) is held to these answers; a change to
`rasterchart.py` that changes an answer must regenerate them (`uv run python
fixtures/import/grid/generate.py`) and the Swift port must follow. `tests/test_grid_fixtures.py`
fails when the committed files differ from a fresh generation.
```

```bash
git add fixtures/import/grid tests/test_grid_fixtures.py
git commit -m "fixtures: the grid reader's synthetic images and the Python answers, for the Swift port (#112 PR 3)"
```

---

### Task 2: `GridImage` and the line finder (`_close`, `_runs`, `_lines`, `_clusters`, `_pitch`, `_fits`)

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridImage.swift`
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridLines.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/GridLinesTests.swift`
- Modify: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/Fixtures.swift` (a `grid(_:)` accessor)

**Interfaces:**
- Produces: `public struct GridImage: Sendable { let width: Int; let height: Int; let rgb: [UInt8] /* row-major, 3 bytes a pixel */; init(width:height:rgb:); init?(png: Data); func grey() -> [Float]; func pixel(x:y:) -> (UInt8, UInt8, UInt8) }`.
- Produces: `struct Mask { let rows: Int; let cols: Int; var bits: [Bool] }` (row-major, `bits[y * cols + x]`), `Mask.transposed()`.
- Produces: `enum GridLines` with `static func close(_ m: Mask, bridge: Int) -> Mask` (down axis 0), `static func runs(_ m: Mask, minPx: Int) -> (best: [Int], segments: [[(Int, Int)]])`, `static func longestRuns(_ m: Mask, bridge: Int) -> [Int]`, `typealias Line = (centre: Double, segments: [(Int, Int)])`, `static func lines(_ m: Mask, minPx: Int) -> [Line]`, `static func clusters(_ lines: [Line]) -> [[Line]]`, `static func pitch(_ positions: [Double]) -> Double?`, `static func fits(_ line: Line, lo: Double, hi: Double) -> Bool`, `static func median(_ xs: [Double]) -> Double`.

- [ ] **Step 1: Write the failing tests**

`GridLinesTests.swift`:

```swift
import Foundation
import Testing
@testable import GraphghanCore

/// The line finder's parts against hand-drawn masks (`rasterchart.py` `_close`, `_runs`,
/// `_lines`, `_clusters`, `_pitch`, `_fits`), and the image type against a fixture PNG.
@Suite struct GridLinesTests {
    /// A (rows × cols) mask from strings of "#" and ".".
    static func mask(_ rows: [String]) -> Mask {
        Mask(rows: rows.count, cols: rows[0].count, bits: rows.flatMap { $0.map { $0 == "#" } })
    }

    @Test func aFixturePNGDecodesToRGBBytes() throws {
        let img = try #require(GridImage(png: try Data(contentsOf: Fixtures.grid("one-grid", ext: "png"))))
        #expect(img.width == 80 * 2 + 37 * 24 && img.height == 60 * 2 + 29 * 24)
        #expect(img.pixel(x: 1, y: 1) == (255, 255, 255))  // page white
        #expect(img.rgb.count == img.width * img.height * 3)
        #expect(img.grey().count == img.width * img.height)
        // Orientation: the column numbers are printed above the grid (y = 46..56), nothing below it.
        let white: (UInt8, UInt8, UInt8) = (255, 255, 255)
        #expect((0..<img.width).contains { img.pixel(x: $0, y: 50) != white })
        #expect(!(0..<img.width).contains { img.pixel(x: $0, y: img.height - 1 - 50) != white })
    }

    @Test func closingBridgesGapsUpToTwiceTheRadiusDownAColumn() {
        // Column 0: a run with a 2-pixel gap (bridged at radius 1); column 1: a 3-pixel gap (kept).
        let m = Self.mask(["##", "##", "..", "..", "##", "..", "##", "##"])
        let c = GridLines.close(m, bridge: 1)
        #expect((0..<8).map { c.bits[$0 * 2] } == [true, true, true, true, true, true, true, true])
        let m2 = Self.mask(["#", "#", ".", ".", ".", "#", "#"])
        let c2 = GridLines.close(m2, bridge: 1)
        #expect((0..<7).map { c2.bits[$0] } == [true, true, false, false, false, true, true])
    }

    @Test func runsReportTheLongestAndEverySegmentAtLeastMinPx() {
        // A gap of seven survives the closing (radius 3 bridges up to six); a gap of five would not.
        let m = Self.mask(["#.", "#.", "#.", "..", "..", "..", "..", "..", "..", "..", "#.", "#."])
        let (best, segments) = GridLines.runs(m, minPx: 2)
        #expect(best == [3, 0])
        #expect(segments[0].map { [$0.0, $0.1] } == [[0, 2], [10, 11]] && segments[1].isEmpty)
        let bridged = GridLines.runs(Self.mask(["#", "#", "#", ".", ".", ".", ".", ".", "#", "#"]), minPx: 2)
        #expect(bridged.best == [10] && bridged.segments[0].map { [$0.0, $0.1] } == [[0, 9]])
    }

    @Test func linesMergeNeighbouringColumnsWithinMergePx() {
        // Three long columns at x = 2, 3 (one bold line) and x = 20 (a thin one), 50 rows tall.
        var rows: [String] = []
        for _ in 0..<50 { rows.append(String((0..<30).map { $0 == 2 || $0 == 3 || $0 == 20 ? "#" : "." })) }
        let lines = GridLines.lines(Self.mask(rows), minPx: 40)
        #expect(lines.count == 2)
        #expect(abs(lines[0].centre - 2.5) < 0.01 && abs(lines[1].centre - 20) < 0.01)
        #expect(lines[0].segments.count == 2 && lines[1].segments.map { [$0.0, $0.1] } == [[0, 49]])
    }

    @Test func clustersSplitWhereTheGapJumpsAndPitchIsTheMeanUnitGap() {
        let lines: [GridLines.Line] = [10, 20, 30, 40, 200, 210, 220].map { (centre: Double($0), segments: []) }
        let groups = GridLines.clusters(lines)
        #expect(groups.map { $0.count } == [4, 3])
        #expect(GridLines.pitch([0, 11, 22, 34, 45]) == 11.25)  // gaps 11, 11, 12, 11: the mean, not the median
        #expect(GridLines.pitch([0, 12, 24, 48, 60]) == 12)     // the 24 is a lost line, dropped
        #expect(GridLines.pitch([0, 5]) == nil)
    }

    @Test func aLineFitsAGridWhenASegmentCoversHalfOfItOrLiesHalfInside() {
        #expect(GridLines.fits((centre: 0, segments: [(0, 60)]), lo: 0, hi: 100))
        #expect(GridLines.fits((centre: 0, segments: [(90, 110)]), lo: 0, hi: 100))   // half inside
        #expect(GridLines.fits((centre: 0, segments: [(0, 40)]), lo: 0, hi: 100))     // wholly inside, though short
        #expect(!GridLines.fits((centre: 0, segments: [(90, 200)]), lo: 0, hi: 100))  // mostly outside
    }
}
```

Add to `Fixtures.swift`:

```swift
    /// `fixtures/import/grid/<name>.<ext>`: the synthetic chart images and the Python answers.
    static func grid(_ name: String, ext: String) -> URL {
        root.appendingPathComponent("fixtures/import/grid/\(name).\(ext)")
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter GridLinesTests 2>&1 | grep -E "error:|✘|✔ Test run" | head`
Expected: compile errors, `GridImage`, `Mask`, `GridLines` undefined.

- [ ] **Step 3: The image and the mask**

`GridImage.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO

/// An RGB byte image the grid reader works on: what PDFKit rendered a page to, or a fixture PNG.
/// Row-major, three bytes a pixel; `MAX_PIXELS` (`GridReader.maxPixels`) bounds it.
public struct GridImage: Sendable {
    public let width: Int
    public let height: Int
    public let rgb: [UInt8]

    public init(width: Int, height: Int, rgb: [UInt8]) {
        precondition(rgb.count == width * height * 3)
        self.width = width
        self.height = height
        self.rgb = rgb
    }

    /// A PNG (or any image ImageIO reads) as RGB bytes, alpha dropped over white.
    public init?(png data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(cgImage: image)
    }

    public init?(cgImage image: CGImage) {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let drawn = rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: info) else { return false }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // A bitmap context's first row in memory is the top of what was drawn, so the bytes are
        // already top-down like the Python array; the orientation test in GridLinesTests holds this.
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i * 3] = rgba[i * 4]
            rgb[i * 3 + 1] = rgba[i * 4 + 1]
            rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        self.init(width: w, height: h, rgb: rgb)
    }

    public func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 3
        return (rgb[i], rgb[i + 1], rgb[i + 2])
    }

    /// Pillow's "L": `0.299 R + 0.587 G + 0.114 B`, rounded to a byte, as a Float per pixel.
    public func grey() -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        rgb.withUnsafeBufferPointer { p in
            out.withUnsafeMutableBufferPointer { o in
                for i in 0..<(width * height) {
                    let v = 0.299 * Double(p[i * 3]) + 0.587 * Double(p[i * 3 + 1]) + 0.114 * Double(p[i * 3 + 2])
                    o[i] = Float(Int(v + 0.5))
                }
            }
        }
        return out
    }
}

/// A boolean (rows × cols) array, row-major: the Python `mask` of shape (n, m).
struct Mask: Sendable {
    let rows: Int
    let cols: Int
    var bits: [Bool]

    init(rows: Int, cols: Int, bits: [Bool]) {
        precondition(bits.count == rows * cols)
        self.rows = rows
        self.cols = cols
        self.bits = bits
    }

    init(rows: Int, cols: Int) { self.init(rows: rows, cols: cols, bits: [Bool](repeating: false, count: rows * cols)) }

    subscript(y: Int, x: Int) -> Bool {
        get { bits[y * cols + x] }
        set { bits[y * cols + x] = newValue }
    }

    func transposed() -> Mask {
        var out = Mask(rows: cols, cols: rows)
        for y in 0..<rows { for x in 0..<cols where bits[y * cols + x] { out.bits[x * rows + y] = true } }
        return out
    }
}
```

- [ ] **Step 4: The line finder**

`GridLines.swift`:

```swift
import Foundation

/// The line-finding half of `rasterchart.py`: from an edge mask to candidate lines, clusters and a
/// pitch. Axis 0 of a mask is "down the line"; each column of the mask is a candidate position.
enum GridLines {
    static let bridge = 3          // BRIDGE
    static let mergePx = 8         // MERGE_PX
    static let gapTolerance = 0.25 // GAP_TOLERANCE

    typealias Line = (centre: Double, segments: [(Int, Int)])

    /// Binary closing down axis 0 with radius `bridge`: gaps up to twice it inside a run vanish
    /// (`_close`). Dilate by `bridge`, erode by `bridge` (a shift past the edge counts as set, as
    /// the Python's `~_shift(ones)` term does), and keep only what the dilation or the mask had.
    static func close(_ mask: Mask, bridge: Int) -> Mask {
        guard bridge > 0 else { return mask }
        let n = mask.rows, m = mask.cols
        var d = mask
        mask.bits.withUnsafeBufferPointer { src in
            d.bits.withUnsafeMutableBufferPointer { dst in
                for y in 0..<n { for x in 0..<m where !src[y * m + x] {
                    for s in 1...bridge where (y - s >= 0 && src[(y - s) * m + x]) || (y + s < n && src[(y + s) * m + x]) { dst[y * m + x] = true; break }
                } }
            }
        }
        var e = d
        d.bits.withUnsafeBufferPointer { dd in
            e.bits.withUnsafeMutableBufferPointer { ee in
                for y in 0..<n { for x in 0..<m where dd[y * m + x] {
                    for s in 1...bridge where (y - s >= 0 && !dd[(y - s) * m + x]) || (y + s < n && !dd[(y + s) * m + x]) { ee[y * m + x] = false; break }
                } }
                // `e & (d | mask)`: e is a subset of d already, so nothing more to clear.
            }
        }
        return e
    }

    /// Per column: the longest run of True down it after closing (`_longest_runs`, first value).
    static func longestRuns(_ mask: Mask, bridge: Int) -> [Int] {
        let closed = close(mask, bridge: bridge)
        let n = mask.rows, m = mask.cols
        var best = [Int](repeating: 0, count: m)
        closed.bits.withUnsafeBufferPointer { c in
            for x in 0..<m {
                var run = 0, top = 0
                for y in 0..<n {
                    if c[y * m + x] { run += 1; if run > top { top = run } } else { run = 0 }
                }
                best[x] = top
            }
        }
        return best
    }

    /// Per column: the longest run (short gaps bridged) and every run at least `minPx` long, as
    /// (start, end) inclusive (`_runs`).
    static func runs(_ mask: Mask, minPx: Int) -> (best: [Int], segments: [[(Int, Int)]]) {
        let closed = close(mask, bridge: bridge)
        let n = mask.rows, m = mask.cols
        var best = [Int](repeating: 0, count: m)
        var segments = [[(Int, Int)]](repeating: [], count: m)
        closed.bits.withUnsafeBufferPointer { c in
            for x in 0..<m {
                var start = -1
                for y in 0...n {
                    let on = y < n && c[y * m + x]
                    if on, start < 0 { start = y }
                    if !on, start >= 0 {
                        let length = y - start
                        if length > best[x] { best[x] = length }
                        if length >= minPx { segments[x].append((start, y - 1)) }
                        start = -1
                    }
                }
            }
        }
        return (best, segments)
    }

    /// Candidate columns (long edge runs) merged within `mergePx` of each other (`_lines`).
    static func lines(_ mask: Mask, minPx: Int) -> [Line] {
        let (best, segments) = runs(mask, minPx: minPx)
        guard let top = best.max(), top >= minPx else { return [] }
        let floor = max(Double(minPx), Double(top) * 0.25)
        let keep = (0..<mask.cols).filter { Double(best[$0]) >= floor }
        guard let first = keep.first else { return [] }
        var out: [Line] = []
        var group = [first]
        for x in keep.dropFirst() {
            if x - group[group.count - 1] <= mergePx { group.append(x) } else { out.append(merge(group, best, segments)); group = [x] }
        }
        out.append(merge(group, best, segments))
        return out
    }

    static func merge(_ group: [Int], _ best: [Int], _ segments: [[(Int, Int)]]) -> Line {
        let weight = group.reduce(0.0) { $0 + Double(best[$1]) }
        let centre = group.reduce(0.0) { $0 + Double($1) * Double(best[$1]) } / weight
        return (centre, group.flatMap { segments[$0] })
    }

    /// Split a sorted line list where the gap jumps past three times the median gap (`_clusters`).
    static func clusters(_ lines: [Line]) -> [[Line]] {
        guard lines.count >= 2 else { return lines.isEmpty ? [] : [lines] }
        let gaps = zip(lines.dropFirst(), lines).map { $0.centre - $1.centre }
        let limit = 3 * median(gaps)
        var groups: [[Line]] = []
        var current = [lines[0]]
        for (line, gap) in zip(lines.dropFirst(), gaps) {
            if gap > limit { groups.append(current); current = [line] } else { current.append(line) }
        }
        groups.append(current)
        return groups
    }

    /// The cell pitch of a line cluster: the mean of the gaps within 0.6–1.4 of the median gap, so
    /// a lost line (a double gap) or a bold line's two edges (a tiny gap) drop out (`_pitch`).
    static func pitch(_ positions: [Double]) -> Double? {
        guard positions.count >= 3 else { return nil }
        let gaps = zip(positions.dropFirst(), positions).map { $0 - $1 }
        let p = median(gaps)
        guard p > 0 else { return nil }
        let unit = gaps.filter { $0 > 0.6 * p && $0 < 1.4 * p }
        return unit.isEmpty ? p : unit.reduce(0, +) / Double(unit.count)
    }

    /// numpy's median: the middle value, or the mean of the two middle values.
    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// A line belongs to a grid spanning lo..hi on the other axis when one of its segments covers
    /// at least half of that span, or lies at least half inside it (`_fits`).
    static func fits(_ line: Line, lo: Double, hi: Double) -> Bool {
        for (s, e) in line.segments {
            let overlap = min(Double(e), hi) - max(Double(s), lo)
            if overlap >= 0.5 * (hi - lo) || overlap >= 0.5 * Double(e - s) { return true }
        }
        return false
    }
}
```

Note on `close`: the Python erosion `e &= _shift(d, s) | ~_shift(ones, s)` treats a neighbour past the array edge as set; the Swift `y - s >= 0 && !d[...]` does the same (out of range never clears). Check the closing test's column 1 (a three-pixel gap survives at radius 1) before moving on: it is the case the dilation-then-erosion gets wrong when the edge rule is off.

- [ ] **Step 5: Run the tests**

Run: `cd ios/Packages/GraphghanCore && swift test --filter GridLinesTests 2>&1 | grep -E "error:|✘|✔ Test run" | head`
Expected: `✔ Test run with 6 tests`.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GridImage and the grid reader's line finder, ported from rasterchart.py (#112 PR 3)"
```

---

### Task 3: `GridReader` — regions on an image (`_refine_axis`, `_band_noise`, `find_regions`, `read_region`, `cell_noise`)

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridReader.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/GridReaderTests.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/PageRender.swift` (test helper: a PDF page to `GridImage` through PDFKit on macOS)

**Interfaces:**
- Consumes: `GridImage`, `Mask`, `GridLines` (Task 2).
- Produces: `public struct Region: Sendable, Equatable { public let xs: [Double]; public let ys: [Double]; public var noise: Double; public var warnings: [String]; cols, rows, cells, bbox: (Int, Int, Int, Int), pitch: (Double, Double), describe() }`.
- Produces: `public enum GridReader` with `static let maxPixels = 40_000_000`, `static let maxNoise = 12.0`, `public static func findRegions(_ img: GridImage) throws -> [Region]` (throws `GridReaderError.tooLarge(width:height:)`), `public static func readRegion(_ img: GridImage, _ region: Region) -> [[(UInt8, UInt8, UInt8)]]` (rows × cols median RGB), `public static func cellNoise(_ img: GridImage, _ region: Region) -> Double`.
- The Python answers: `regions[i].cols/rows` equal, `pitch` within 0.05, `bbox` within 1, `noise` within 0.05.

- [ ] **Step 1: Write the failing tests**

`GridReaderTests.swift`:

```swift
import Foundation
import PDFKit
import Testing
@testable import GraphghanCore

/// `find_regions` on the images Python drew, held to the answers it recorded
/// (`fixtures/import/grid/<name>.json`), and on our own PDF's chart page rendered by PDFKit.
@Suite struct GridReaderTests {
    struct Answer: Decodable {
        struct R: Decodable { let cols: Int; let rows: Int; let pitch: [Double]; let bbox: [Int]; let noise: Double }
        struct Cluster: Decodable { let hexes: [String]; let warnings: [String]; let cells: [[Int]] }
        let regions: [R]
        let palette: [String]?
        let cells: [[Int]]?
        let cluster: Cluster?
    }

    static func fixture(_ name: String) throws -> (GridImage, Answer) {
        let img = try #require(GridImage(png: try Data(contentsOf: Fixtures.grid(name, ext: "png"))))
        let answer = try JSONDecoder().decode(Answer.self, from: try Data(contentsOf: Fixtures.grid(name, ext: "json")))
        return (img, answer)
    }

    static func expectSame(_ got: [Region], _ want: [Answer.R], _ name: String) {
        #expect(got.count == want.count, "\(name): \(got.map { $0.describe() })")
        for (g, w) in zip(got, want) {
            #expect(g.cols == w.cols && g.rows == w.rows, "\(name): \(g.describe())")
            #expect(abs(g.pitch.0 - w.pitch[0]) < 0.05 && abs(g.pitch.1 - w.pitch[1]) < 0.05, "\(name): pitch \(g.pitch) vs \(w.pitch)")
            let b = g.bbox
            #expect(abs(b.0 - w.bbox[0]) <= 1 && abs(b.1 - w.bbox[1]) <= 1 && abs(b.2 - w.bbox[2]) <= 1 && abs(b.3 - w.bbox[3]) <= 1, "\(name): bbox \(b) vs \(w.bbox)")
            #expect(abs(g.noise - w.noise) < 0.05, "\(name): noise \(g.noise) vs \(w.noise)")
        }
    }

    @Test(arguments: ["one-grid", "two-grids", "symbols", "text-page"])
    func regionsMatchThePythonAnswer(name: String) throws {
        let (img, answer) = try Self.fixture(name)
        let started = Date()
        let regions = try GridReader.findRegions(img)
        print("GridReader.findRegions \(name) \(img.width)x\(img.height): \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        Self.expectSame(regions, answer.regions, name)
    }

    /// Python's test_a_photo_is_not_a_chart: noise under a fence of lines every 30 px. The noise is
    /// this test's own (numpy's generator is not reproduced), so only "no grid" is asserted.
    @Test func aPhotoUnderAFenceOfLinesIsNotAChart() throws {
        var rgb = [UInt8](repeating: 0, count: 600 * 600 * 3)
        var seed: UInt32 = 1
        for i in rgb.indices { seed = seed &* 1_664_525 &+ 1_013_904_223; rgb[i] = UInt8(truncatingIfNeeded: seed >> 24) }
        for y in 0..<600 { for x in 0..<600 where x % 30 < 2 || y % 30 < 2 { let i = (y * 600 + x) * 3; rgb[i] = 0; rgb[i + 1] = 0; rgb[i + 2] = 0 } }
        #expect(try GridReader.findRegions(GridImage(width: 600, height: 600, rgb: rgb)).isEmpty)
    }

    @Test func anOversizedImageIsRefused() {
        let img = GridImage(width: 8000, height: 6000, rgb: [UInt8](repeating: 255, count: 8000 * 6000 * 3))
        #expect(throws: GridReaderError.tooLarge(width: 8000, height: 6000)) { try GridReader.findRegions(img) }
    }

    /// Our own PDF's first chart page says which columns and rows it holds; the grid reader must
    /// find exactly that many cells on PDFKit's render (the Python does the same on pdfium's).
    @Test func theOwnPDFsChartPageReadsToItsHeader() throws {
        let doc = try #require(PDFDocument(url: Fixtures.importPDF("craigh-na-dun-final-sc")))
        let (page, header) = try #require(PageRender.firstChartPage(doc))
        let img = try #require(PageRender.image(page, scale: 4))
        let started = Date()
        let regions = try GridReader.findRegions(img)
        print("GridReader.findRegions craigh page \(img.width)x\(img.height): \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        let r = try #require(regions.first)
        #expect(r.cols == header.cols && r.rows == header.rows, "\(r.describe())")
        #expect(r.noise < GridReader.maxNoise)
    }
}
```

`PageRender.swift` (test target):

```swift
import CoreGraphics
import Foundation
import PDFKit
@testable import GraphghanCore

/// PDFKit on macOS rendering a page for the tests, the way the app's `PageRenderer` will on iOS.
enum PageRender {
    struct Header { let cols: Int; let rows: Int; let colFrom: Int; let colTo: Int; let rowFrom: Int; let rowTo: Int }

    static let headerRe = try! NSRegularExpression(pattern: #"^Chart (\d+) of (\d+): columns (\d+)-(\d+) of (\d+), rows (\d+)-(\d+) of (\d+)"#)

    /// The first page whose text starts with the own-PDF chart header, and the cells it declares.
    static func firstChartPage(_ doc: PDFDocument) -> (PDFPage, Header)? {
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let text = page.string else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let m = headerRe.firstMatch(in: text, range: range) else { continue }
            func n(_ k: Int) -> Int { Int(text[Range(m.range(at: k), in: text)!])! }
            return (page, Header(cols: n(4) - n(3) + 1, rows: n(7) - n(6) + 1, colFrom: n(3), colTo: n(4), rowFrom: n(6), rowTo: n(7)))
        }
        return nil
    }

    static func image(_ page: PDFPage, scale: CGFloat) -> GridImage? {
        let box = page.bounds(for: .mediaBox)
        let w = Int(box.width * scale), h = Int(box.height * scale)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else { return nil }
        return GridImage(cgImage: image)
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter GridReaderTests 2>&1 | grep -E "error:|✘|✔ Test run" | head`
Expected: compile errors, `Region`, `GridReader` undefined.

- [ ] **Step 3: The port**

`GridReader.swift`. Every `round` below is Python's (`.toNearestOrEven`); every `Int(x)` of a non-negative Double is Python's `int()`.

```swift
import Foundation

/// One grid found on an image (`rasterchart.Region`). `xs`/`ys` are the fitted line positions in
/// pixels; `noise` is the mean colour spread inside the sampled cell centres.
public struct Region: Sendable, Equatable {
    public let xs: [Double]
    public let ys: [Double]
    public var noise: Double
    public var warnings: [String]

    public init(xs: [Double], ys: [Double], noise: Double = 0, warnings: [String] = []) {
        self.xs = xs
        self.ys = ys
        self.noise = noise
        self.warnings = warnings
    }

    public var cols: Int { xs.count - 1 }
    public var rows: Int { ys.count - 1 }
    public var cells: Int { cols * rows }
    public var bbox: (Int, Int, Int, Int) { (Int(xs[0]), Int(ys[0]), Int(xs[xs.count - 1]), Int(ys[ys.count - 1])) }
    public var pitch: (Double, Double) { ((xs[xs.count - 1] - xs[0]) / Double(cols), (ys[ys.count - 1] - ys[0]) / Double(rows)) }

    public func describe() -> String {
        let b = bbox
        let p = pitch
        return "\(cols)x\(rows) cells at (\(b.0), \(b.1))-(\(b.2), \(b.3)), pitch \(String(format: "%.1f", p.0))x\(String(format: "%.1f", p.1)) px, noise \(String(format: "%.1f", noise))"
    }
}

public enum GridReaderError: Error, Equatable {
    case tooLarge(width: Int, height: Int)
}

/// The grid reader (`rasterchart.py` `find_regions` and its helpers): lines by their edges over
/// long straight runs, a lattice fitted from the pitch, cells sampled at their centres.
public enum GridReader {
    public static let edgeThreshold = 16   // EDGE_THRESHOLD
    public static let minLinePx = 40       // MIN_LINE_PX
    public static let minLines = 5         // MIN_LINES
    public static let centreFraction = 0.4 // CENTRE_FRACTION
    public static let maxNoise = 12.0      // MAX_NOISE
    public static let maxSilent = 40       // MAX_SILENT
    public static let maxPixels = 40_000_000 // MAX_PIXELS

    static func pyRound(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }

    // MARK: edges

    /// Vertical edges: (h, w-1), True where a channel steps by more than the threshold between
    /// x and x+1 (`ex`); horizontal edges transposed: (w, h-1) (`ey.T`), so both masks run down
    /// axis 0 along the line and index the candidate position on axis 1.
    static func edges(_ img: GridImage) -> (ex: Mask, eyT: Mask) {
        let w = img.width, h = img.height, t = edgeThreshold
        var ex = Mask(rows: h, cols: w - 1)
        var eyT = Mask(rows: w, cols: h - 1)
        img.rgb.withUnsafeBufferPointer { p in
            ex.bits.withUnsafeMutableBufferPointer { exb in
                for y in 0..<h {
                    let row = y * w * 3
                    for x in 0..<(w - 1) {
                        let i = row + x * 3
                        let d = max(abs(Int(p[i]) - Int(p[i + 3])), abs(Int(p[i + 1]) - Int(p[i + 4])), abs(Int(p[i + 2]) - Int(p[i + 5])))
                        if d > t { exb[y * (w - 1) + x] = true }
                    }
                }
            }
            eyT.bits.withUnsafeMutableBufferPointer { eyb in
                for y in 0..<(h - 1) {
                    let row = y * w * 3, next = (y + 1) * w * 3
                    for x in 0..<w {
                        let i = row + x * 3, j = next + x * 3
                        let d = max(abs(Int(p[i]) - Int(p[j])), abs(Int(p[i + 1]) - Int(p[j + 1])), abs(Int(p[i + 2]) - Int(p[j + 2])))
                        if d > t { eyb[x * (h - 1) + y] = true }
                    }
                }
            }
        }
        return (ex, eyT)
    }

    /// Rows `range` of a mask, every column (`edges[a:b, :]`).
    static func rows(_ m: Mask, _ range: Range<Int>) -> Mask {
        let lo = max(0, range.lowerBound), hi = min(m.rows, range.upperBound)
        return Mask(rows: max(0, hi - lo), cols: m.cols, bits: Array(m.bits[(lo * m.cols)..<(hi * m.cols)]))
    }

    /// True where any pixel within r columns is True (`_window_max`, along axis 1).
    static func windowMax(_ m: Mask, _ r: Int) -> Mask {
        var out = m
        let rows = m.rows, cols = m.cols
        m.bits.withUnsafeBufferPointer { src in
            out.bits.withUnsafeMutableBufferPointer { dst in
                for y in 0..<rows {
                    let row = y * cols
                    for x in 0..<cols where !src[row + x] {
                        for s in 1...r where (x - s >= 0 && src[row + x - s]) || (x + s < cols && src[row + x + s]) { dst[row + x] = true; break }
                    }
                }
            }
        }
        return out
    }

    // MARK: lattice fitting

    /// Fit the line positions along axis 1 of `edges` (`_refine_axis`): snap each seed to the
    /// nearest edge-density peak, keep the lattice most seeds agree on, walk outward one pitch at a
    /// time while a thin line is there and the cells it adds are flat colour, then lay every
    /// interior line on the fitted pitch. `bandNoise(a, b)` is the (mean, median) colour spread of
    /// the strip a..b on this axis.
    static func refineAxis(_ edges: Mask, seeds: [Double], pitch: Double, bandNoise: (Double, Double) -> (Double, Double)) -> [Double]? {
        let span = edges.rows, n = edges.cols
        guard span > 0, n > 0 else { return nil }
        let wide = windowMax(edges, 2)
        var density = [Double](repeating: 0, count: n)
        var raw = [Double](repeating: 0, count: n)
        wide.bits.withUnsafeBufferPointer { wb in
            edges.bits.withUnsafeBufferPointer { eb in
                for y in 0..<span { for x in 0..<n {
                    if wb[y * n + x] { density[x] += 1 }
                    if eb[y * n + x] { raw[x] += 1 }
                } }
            }
        }
        for x in 0..<n { density[x] /= Double(span); raw[x] /= Double(span) }
        let longest = GridLines.longestRuns(wide, bridge: max(1, min(GridLines.bridge, Int(pitch / 12))))
        let rSeed = max(2, Int(pitch / 4))
        let rNext = max(2, Int(pitch / 8))

        /// The centre of the densest plateau within r of `at`.
        func peak(_ at: Double, _ r: Int) -> Int? {
            let lo = Int(max(0, at - Double(r))), hi = Int(min(Double(n), at + Double(r) + 1))
            guard hi > lo else { return nil }
            let top = density[lo..<hi].max()!
            let plateau = (lo..<hi).filter { density[$0] >= top - 1e-9 }
            let mean = Double(plateau.reduce(0, +)) / Double(plateau.count)
            return pyRound(mean)
        }

        /// A grid line is a narrow density peak; text is dense for a whole glyph height.
        func thin(_ x: Int) -> Bool {
            var lo = max(0, x - 2), hi = min(n, x + 3)
            var top = lo
            for i in lo..<hi where raw[i] > raw[top] { top = i }
            let half = 0.5 * raw[top]
            guard half > 0 else { return false }
            lo = top
            while lo > 0, raw[lo - 1] >= half { lo -= 1 }
            hi = top
            while hi < n - 1, raw[hi + 1] >= half { hi += 1 }
            return Double(hi - lo + 1) <= max(6, 0.3 * pitch)
        }

        var found = Set<Int>()
        for s in seeds { if let p = peak(s, rSeed), thin(p) { found.insert(p) } }
        let sortedFound = found.sorted()
        guard sortedFound.count >= 2 else { return nil }

        func onLattice(_ x: Int, _ anchor: Int) -> Bool {
            let k = Double(x - anchor) / pitch
            return abs(k - k.rounded(.toNearestOrEven)) <= 0.25
        }
        var anchor = sortedFound[0], anchorCount = -1
        for a in sortedFound {
            let c = sortedFound.filter { onLattice($0, a) }.count
            if c > anchorCount { anchor = a; anchorCount = c }
        }
        let base = GridLines.median(sortedFound.filter { onLattice($0, anchor) }.map { density[$0] })
        guard base > 0 else { return nil }

        func present(_ x: Int) -> Bool {
            density[x] >= 0.3 * base && Double(longest[x]) >= 1.5 * pitch && thin(x)
        }

        /// From the anchor outward, one lattice step at a time (position, lattice index) pairs.
        func walk(_ direction: Int) -> [(Int, Int)] {
            var committed = [(anchor, 0)]
            var pending: [(Int, Int)] = []
            var last = Double(anchor)
            var k = 0
            var step = pitch
            while true {
                k += direction
                let expected = last + Double(direction) * step
                guard let p = peak(expected, rNext), p > 0, p < n - 1 else { break }
                if present(p) {
                    committed += pending + [(p, k)]
                    pending = []
                    last = Double(p)
                    let (x0, k0) = committed[0], (x1, k1) = committed[committed.count - 1]
                    if abs(k1 - k0) >= 3 { step = abs(Double(x1 - x0) / Double(k1 - k0)) }
                } else {
                    let (lo, hi) = direction > 0 ? (last, Double(p)) : (Double(p), last)
                    if bandNoise(lo, hi).0 > maxNoise { break }
                    pending.append((pyRound(expected), k))
                    last = expected
                    if pending.count > maxSilent { break }
                }
            }
            return committed
        }

        var pairSet = Set<[Int]>()
        for (x, k) in walk(-1) + walk(1) { pairSet.insert([x, k]) }
        let pairs = pairSet.sorted { $0[0] != $1[0] ? $0[0] < $1[0] : $0[1] < $1[1] }
        let xs = pairs.map { Double($0[0]) }
        let ks = pairs.map { Double($0[1] - pairs[0][1]) }
        guard Set(ks).count >= 2 else { return nil }
        // np.polyfit(ks, xs, 1): least squares slope and intercept.
        let m = Double(ks.count)
        let sk = ks.reduce(0, +), sx = xs.reduce(0, +)
        let skk = ks.reduce(0) { $0 + $1 * $1 }, skx = zip(ks, xs).reduce(0) { $0 + $1.0 * $1.1 }
        let slope = (m * skx - sk * sx) / (m * skk - sk * sk)
        let intercept = (sx - slope * sk) / m
        let count = Int(ks[ks.count - 1])
        guard count >= minLines - 1 else { return nil }
        return (0...count).map { intercept + slope * Double($0) }
    }

    /// Grey spread of the cell centres in a one-cell-thick strip, as (mean, median) over the
    /// cells (`_band_noise`). `band(t, i)` reads the strip: `t` across its thickness (0..<thickness),
    /// `i` along its length (0..<length); cells lie along the length at `pitch`.
    static func bandNoise(thickness: Int, length: Int, pitch: Double, band: (Int, Int) -> Float) -> (Double, Double) {
        let c0 = Int(Double(thickness) * (0.5 - centreFraction / 2))
        let c1 = max(Int(Double(thickness) * (0.5 + centreFraction / 2)), Int(Double(thickness) * 0.5) + 1)
        let n = max(1, Int(Double(length) / pitch))
        var spreads: [Double] = []
        for k in 0..<n {
            let a = Int(Double(k) * pitch + pitch * (0.5 - centreFraction / 2))
            let b = max(a + 1, Int(Double(k) * pitch + pitch * (0.5 + centreFraction / 2)))
            var values: [Double] = []
            for t in c0..<min(c1, thickness) { for i in a..<min(b, length) { values.append(Double(band(t, i))) } }
            spreads.append(std(values))
        }
        guard !spreads.isEmpty else { return (0, 0) }
        return (spreads.reduce(0, +) / Double(spreads.count), GridLines.median(spreads))
    }

    /// numpy's std: population standard deviation; 0 for nothing.
    static func std(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let mean = v.reduce(0, +) / Double(v.count)
        return (v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count)).squareRoot()
    }

    static func overlap(_ a: Region, _ b: Region) -> Double {
        let (ax0, ay0, ax1, ay1) = a.bbox, (bx0, by0, bx1, by1) = b.bbox
        let w = max(0, min(ax1, bx1) - max(ax0, bx0)), h = max(0, min(ay1, by1) - max(ay0, by0))
        return Double(w * h) / Double(max(1, min((ax1 - ax0) * (ay1 - ay0), (bx1 - bx0) * (by1 - by0))))
    }

    // MARK: regions

    /// Every grid on the image, largest first (`find_regions`).
    public static func findRegions(_ img: GridImage) throws -> [Region] {
        guard img.width * img.height <= maxPixels else { throw GridReaderError.tooLarge(width: img.width, height: img.height) }
        guard img.width >= 2, img.height >= 2 else { return [] }
        let grey = img.grey()
        let w = img.width, h = img.height
        let (ex, eyT) = edges(img)
        let minPx = max(minLinePx, min(h, w) / 40)
        let colLines = GridLines.lines(ex, minPx: minPx)    // centre x, y-segments
        let rowLines = GridLines.lines(eyT, minPx: minPx)   // centre y, x-segments
        var regions: [Region] = []
        for cols in GridLines.clusters(colLines) {
            guard cols.count >= 3 else { continue }
            let x0 = cols[0].centre, x1 = cols[cols.count - 1].centre
            let rowsHere = rowLines.filter { GridLines.fits($0, lo: x0, hi: x1) }
            guard rowsHere.count >= 3 else { continue }
            let y0 = rowsHere[0].centre, y1 = rowsHere[rowsHere.count - 1].centre
            let colsHere = cols.filter { GridLines.fits($0, lo: y0, hi: y1) }
            guard let px = GridLines.pitch(colsHere.map(\.centre)), let py = GridLines.pitch(rowsHere.map(\.centre)) else { continue }
            // gray[y0:y1, a:b].T: thickness b-a across x, length y1-y0 down y.
            func colNoise(_ a: Double, _ b: Double, _ ya: Double, _ yb: Double) -> (Double, Double) {
                let (ia, ib, iy0, iy1) = (Int(a), Int(b), Int(ya), Int(yb))
                return bandNoise(thickness: max(0, ib - ia), length: max(0, iy1 - iy0), pitch: py) { t, i in grey[(iy0 + i) * w + ia + t] }
            }
            guard var xs = refineAxis(rows(ex, Int(y0)..<(Int(y1) + 1)), seeds: colsHere.map(\.centre), pitch: px, bandNoise: { colNoise($0, $1, y0, y1) }) else { continue }
            // gray[a:b, xs0:xs-1]: thickness b-a down y, length along x.
            let xsLo = Int(xs[0]), xsHi = Int(xs[xs.count - 1])
            func rowNoise(_ a: Double, _ b: Double) -> (Double, Double) {
                let (ia, ib) = (Int(a), Int(b))
                return bandNoise(thickness: max(0, ib - ia), length: max(0, xsHi - xsLo), pitch: px) { t, i in grey[(ia + t) * w + xsLo + i] }
            }
            guard let ys = refineAxis(rows(eyT, xsLo..<(xsHi + 1)), seeds: rowsHere.map(\.centre), pitch: py, bandNoise: rowNoise) else { continue }
            let ys0 = ys[0], ys1 = ys[ys.count - 1]
            if let again = refineAxis(rows(ex, Int(ys0)..<(Int(ys1) + 1)), seeds: xs, pitch: px, bandNoise: { colNoise($0, $1, ys0, ys1) }) { xs = again }
            var region = Region(xs: xs, ys: ys)
            region.noise = cellNoise(img, region, grey: grey)
            if region.noise > maxNoise { continue }  // a photo or a textured fabric, not a chart
            if regions.contains(where: { overlap(region, $0) > 0.5 && $0.cells >= region.cells }) { continue }
            regions = regions.filter { overlap(region, $0) <= 0.5 }
            regions.append(region)
        }
        return regions.sorted { $0.cells > $1.cells }
    }

    // MARK: sampling

    /// The pixel rectangle at the centre of each cell: (row j, col i, y0..<y1, x0..<x1) (`_patches`).
    static func patches(_ region: Region) -> [(j: Int, i: Int, y0: Int, y1: Int, x0: Int, x1: Int)] {
        var out: [(Int, Int, Int, Int, Int, Int)] = []
        let f0 = 0.5 - centreFraction / 2, f1 = 0.5 + centreFraction / 2
        for j in 0..<region.rows {
            let cy0 = region.ys[j], cy1 = region.ys[j + 1]
            let my0 = pyRound(cy0 + (cy1 - cy0) * f0)
            let my1 = max(my0 + 1, pyRound(cy0 + (cy1 - cy0) * f1))
            for i in 0..<region.cols {
                let cx0 = region.xs[i], cx1 = region.xs[i + 1]
                let mx0 = pyRound(cx0 + (cx1 - cx0) * f0)
                let mx1 = max(mx0 + 1, pyRound(cx0 + (cx1 - cx0) * f1))
                out.append((j, i, my0, my1, mx0, mx1))
            }
        }
        return out
    }

    /// Median RGB of the centre of every cell, rows × cols (`read_region`; a median of an even
    /// count is the mean of the two middles, then truncated to a byte as numpy's uint8 cast does).
    public static func readRegion(_ img: GridImage, _ region: Region) -> [[(UInt8, UInt8, UInt8)]] {
        var out = [[(UInt8, UInt8, UInt8)]](repeating: [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: region.cols), count: region.rows)
        for p in patches(region) {
            var r: [Double] = [], g: [Double] = [], b: [Double] = []
            for y in max(0, p.y0)..<min(img.height, p.y1) { for x in max(0, p.x0)..<min(img.width, p.x1) {
                let i = (y * img.width + x) * 3
                r.append(Double(img.rgb[i])); g.append(Double(img.rgb[i + 1])); b.append(Double(img.rgb[i + 2]))
            } }
            guard !r.isEmpty else { continue }
            out[p.j][p.i] = (UInt8(Int(GridLines.median(r))), UInt8(Int(GridLines.median(g))), UInt8(Int(GridLines.median(b))))
        }
        return out
    }

    /// Mean median-absolute-deviation of grey inside the cell centres, over up to 400 cells
    /// (`cell_noise`): a symbol's strokes over a flat cell are ignored, a photo deviates everywhere.
    public static func cellNoise(_ img: GridImage, _ region: Region) -> Double {
        cellNoise(img, region, grey: img.grey())
    }

    static func cellNoise(_ img: GridImage, _ region: Region, grey: [Float], sample: Int = 400) -> Double {
        let all = patches(region)
        let step = max(1, all.count / sample)
        var spreads: [Double] = []
        var k = 0
        while k < all.count {
            let p = all[k]
            var values: [Double] = []
            for y in max(0, p.y0)..<min(img.height, p.y1) { for x in max(0, p.x0)..<min(img.width, p.x1) { values.append(Double(grey[y * img.width + x])) } }
            if !values.isEmpty {
                let m = GridLines.median(values)
                spreads.append(GridLines.median(values.map { abs($0 - m) }))
            }
            k += step
        }
        return spreads.isEmpty ? 0 : spreads.reduce(0, +) / Double(spreads.count)
    }
}
```

Two places to read with care against the Python before running: `colNoise` transposes the strip (`gray[y0:y1, a:b].T` has thickness across x and length down y, so `band(t, i)` reads `grey[(y0 + i) * w + a + t]`), and `rowNoise` does not (`gray[a:b, xs0:xs1]`: thickness down y, length along x). In `refineAxis` the pairs set is keyed on `[x, k]` because Swift tuples are not `Hashable`.

- [ ] **Step 4: Optimise the package's debug builds**

At `-Onone` the Craigh page takes forty seconds (every pixel through generic array code); at `-O`
it takes under half a second. The package is pure logic, so `Package.swift` optimises its debug
builds too, which keeps the app's test suite quick:

```swift
        .target(
            name: "GraphghanCore",
            // The grid reader (GridReader.swift) walks every pixel of an 8-megapixel page; at
            // -Onone that is forty seconds a page and half a second at -O. The package is pure
            // logic, so its debug builds are optimised too and the app's tests stay quick.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
```

`unsafeFlags` is allowed for a local package; confirm the app still builds (`xcodegen generate --quiet && xcodebuild build-for-testing …`) before committing.

- [ ] **Step 5: Run the tests**

Run: `cd ios/Packages/GraphghanCore && swift test --filter GridReaderTests 2>&1 | grep -E "error:|✘|✔ Test run|ms$" | head -20`
Expected: `✔ Test run with 7 tests` (four fixtures, the photo, the cap, the own page). If a fixture's region count matches but a pitch or bbox is off by more than the tolerance, the difference is in `peak`'s rounding or `pitch`'s mean; compare against `uv run python -c "from graphghan import rasterchart as rc; from PIL import Image; print([r.describe() for r in rc.find_regions(Image.open('fixtures/import/grid/one-grid.png'))])"`. Note the printed times; the Craigh page (2448×3168 at 4×) reads in about 0.4 s on the mini once the package is optimised.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GridReader finds the grids on a page, held to the Python answers (#112 PR 3)"
```

---

### Task 4: `GridColours` — Lab, `snap_to_palette`, `cluster_palette`, `name_colour`, codes

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridColours.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/GridColoursTests.swift`

**Interfaces:**
- Consumes: `GridReader.readRegion` samples (rows × cols of RGB bytes), `Region` (Task 3).
- Produces: `public enum GridColours` with `static func lab(_ rgb: (Double, Double, Double)) -> (Double, Double, Double)`, `static func hex(_: (UInt8, UInt8, UInt8)) -> String`, `static func rgb(_ hex: String) -> (UInt8, UInt8, UInt8)?`, `public static func snapToPalette(_ samples: [[(UInt8, UInt8, UInt8)]], hexes: [String], maxDelta: Double = 25) throws -> [[UInt8]]` (throws `GridColoursError.foreignColour(column:row:hex:nearest:distance:)`), `public static func clusterPalette(_ samples: [[(UInt8, UInt8, UInt8)]], radius: Double = 6) -> (cells: [[UInt8]], hexes: [String], warnings: [String])`, `public static func nameColour(_ hex: String) -> String`, `public static func code(_ i: Int) -> String` ("A".."Z", "AA"...; `importers._code`).

- [ ] **Step 1: Write the failing tests**

`GridColoursTests.swift`:

```swift
import Foundation
import Testing
@testable import GraphghanCore

/// The colour half of `rasterchart.py`: cells snapped to a known palette, a palette clustered from
/// the cells by frequency, and colour names; held to the Python answers on the fixtures.
@Suite struct GridColoursTests {
    static let palette = ["#f2e8d5", "#2b2f33", "#1e4d3a", "#d9a21b"]

    @Test(arguments: ["one-grid", "two-grids", "symbols"])
    func snappedCellsMatchThePythonAnswer(name: String) throws {
        let (img, answer) = try GridReaderTests.fixture(name)
        let region = try #require(try GridReader.findRegions(img).first)
        let samples = GridReader.readRegion(img, region)
        let cells = try GridColours.snapToPalette(samples, hexes: try #require(answer.palette))
        #expect(cells.map { $0.map(Int.init) } == answer.cells, "\(name)")
    }

    @Test(arguments: ["one-grid", "two-grids", "symbols"])
    func clusteredPaletteMatchesThePythonAnswer(name: String) throws {
        let (img, answer) = try GridReaderTests.fixture(name)
        let region = try #require(try GridReader.findRegions(img).first)
        let (cells, hexes, warnings) = GridColours.clusterPalette(GridReader.readRegion(img, region))
        let want = try #require(answer.cluster)
        #expect(hexes == want.hexes && warnings == want.warnings, "\(name)")
        #expect(cells.map { $0.map(Int.init) } == want.cells, "\(name)")
    }

    @Test func snapRefusesAForeignColourByCell() {
        var samples = [[(UInt8, UInt8, UInt8)]](repeating: [(UInt8, UInt8, UInt8)](repeating: (0xf2, 0xe8, 0xd5), count: 3), count: 2)
        samples[1][2] = (255, 0, 255)
        #expect(throws: GridColoursError.foreignColour(column: 3, row: 2, hex: "#ff00ff", nearest: "#2b2f33", distance: 122)) {
            try GridColours.snapToPalette(samples, hexes: Self.palette)  // the nearest and the distance are the Python's answer
        }
    }

    @Test func clusterOrdersCodesByFrequencyAndFlagsBleed() {
        // Python's test_cluster_orders_codes_by_frequency_and_flags_bleed: 30×30, top ten rows the
        // third colour, one stray cell of the second.
        let rgb = Self.palette.map { GridColours.rgb($0)! }
        var samples = [[(UInt8, UInt8, UInt8)]](repeating: [(UInt8, UInt8, UInt8)](repeating: rgb[0], count: 30), count: 30)
        for y in 0..<10 { for x in 0..<30 { samples[y][x] = rgb[2] } }
        samples[0][0] = rgb[1]
        let (cells, hexes, warnings) = GridColours.clusterPalette(samples)
        #expect(hexes[0] == Self.palette[0] && hexes[1] == Self.palette[2] && hexes[2] == Self.palette[1])
        #expect(cells[15][0] == 0 && cells[5][5] == 1 && cells[0][0] == 2)
        #expect(warnings.first?.contains("1 cell") == true)
    }

    @Test func colourNamesAndCodes() {
        #expect(GridColours.nameColour("#d9a21b") == "gold" && GridColours.nameColour("#ffffff") == "white")
        #expect(GridColours.code(0) == "A" && GridColours.code(25) == "Z" && GridColours.code(26) == "AA" && GridColours.code(27) == "AB")
        #expect(GridColours.hex((0x2b, 0x2f, 0x33)) == "#2b2f33" && GridColours.rgb("#2b2f33")! == (0x2b, 0x2f, 0x33))
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter GridColoursTests 2>&1 | grep -E "error:|✘|✔ Test run" | head`
Expected: compile errors, `GridColours` undefined.

- [ ] **Step 3: The port**

`GridColours.swift`:

```swift
import Foundation

public enum GridColoursError: Error, Equatable {
    /// A cell farther than the allowed distance from every palette colour (`snap_to_palette`);
    /// column and row are 1-based from the top-left, distance rounded.
    case foreignColour(column: Int, row: Int, hex: String, nearest: String, distance: Int)
}

/// The colour half of `rasterchart.py`: Lab distances, snapping, greedy clustering, names.
public enum GridColours {
    typealias RGB = (UInt8, UInt8, UInt8)
    typealias Lab = (Double, Double, Double)

    static let colourNames: [(String, (Double, Double, Double))] = [
        ("white", (255, 255, 255)), ("cream", (245, 235, 210)), ("black", (0, 0, 0)), ("charcoal", (50, 50, 55)),
        ("grey", (140, 140, 140)), ("silver", (200, 200, 200)), ("red", (200, 30, 30)), ("orange", (240, 130, 30)),
        ("yellow", (240, 210, 40)), ("gold", (215, 165, 30)), ("green", (40, 140, 60)), ("dark green", (25, 80, 50)),
        ("teal", (30, 140, 140)), ("blue", (40, 90, 200)), ("navy", (25, 40, 90)), ("purple", (110, 50, 140)),
        ("pink", (240, 170, 200)), ("brown", (120, 80, 50)), ("tan", (200, 170, 130)), ("sage", (120, 160, 140)),
        ("olive", (110, 120, 50)), ("mint", (170, 230, 200)), ("aqua", (160, 220, 225)), ("sky", (140, 190, 240)),
        ("lavender", (190, 170, 220)), ("maroon", (110, 30, 40)), ("beige", (225, 210, 180)),
    ]

    /// sRGB 0..255 to CIE Lab, D65 (`_to_lab`).
    static func lab(_ rgb: (Double, Double, Double)) -> Lab {
        func lin(_ v: Double) -> Double { let c = v / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(rgb.0), g = lin(rgb.1), b = lin(rgb.2)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 1.0
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func lab(_ c: RGB) -> Lab { lab((Double(c.0), Double(c.1), Double(c.2))) }

    static func distance(_ a: Lab, _ b: Lab) -> Double {
        ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
    }

    public static func hex(_ c: (UInt8, UInt8, UInt8)) -> String { String(format: "#%02x%02x%02x", c.0, c.1, c.2) }

    public static func rgb(_ hex: String) -> (UInt8, UInt8, UInt8)? {
        guard hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
    }

    /// Nearest palette entry per cell in Lab; a cell farther than `maxDelta` is refused by name.
    public static func snapToPalette(_ samples: [[(UInt8, UInt8, UInt8)]], hexes: [String], maxDelta: Double = 25) throws -> [[UInt8]] {
        let pal = hexes.map { lab(rgb($0) ?? (0, 0, 0)) }
        var out: [[UInt8]] = []
        var worst = (d: -1.0, x: 0, y: 0, hex: "", nearest: 0)
        for (y, row) in samples.enumerated() {
            var idx: [UInt8] = []
            for (x, c) in row.enumerated() {
                let l = lab(c)
                var best = 0, bestD = Double.infinity
                for (k, p) in pal.enumerated() { let d = distance(l, p); if d < bestD { bestD = d; best = k } }
                idx.append(UInt8(best))
                if bestD > worst.d { worst = (bestD, x, y, hex(c), best) }
            }
            out.append(idx)
        }
        if worst.d > maxDelta {
            throw GridColoursError.foreignColour(column: worst.x + 1, row: worst.y + 1, hex: worst.hex, nearest: hexes[worst.nearest], distance: Int(worst.d.rounded()))
        }
        return out
    }

    /// Greedy clustering in Lab by frequency (`cluster_palette`): codes by cell count, a tiny
    /// cluster near a big one folded in with a warning, a colour on almost no cells warned about.
    public static func clusterPalette(_ samples: [[(UInt8, UInt8, UInt8)]], radius: Double = 6) -> (cells: [[UInt8]], hexes: [String], warnings: [String]) {
        // np.unique(flat, axis=0): distinct colours in lexicographic order, with counts.
        var counts: [UInt32: Int] = [:]
        for row in samples { for c in row { counts[UInt32(c.0) << 16 | UInt32(c.1) << 8 | UInt32(c.2), default: 0] += 1 } }
        let colours = counts.keys.sorted()
        let count = colours.map { counts[$0]! }
        func rgbOf(_ k: UInt32) -> RGB { (UInt8((k >> 16) & 0xff), UInt8((k >> 8) & 0xff), UInt8(k & 0xff)) }
        let labs = colours.map { lab(rgbOf($0)) }
        // np.argsort(-counts): by count descending, ties in index order (a stable sort).
        let order = colours.indices.sorted { count[$0] != count[$1] ? count[$0] > count[$1] : $0 < $1 }
        var centres: [Lab] = []
        var members: [[Int]] = []
        var assign = [Int](repeating: 0, count: colours.count)
        for k in order {
            if !centres.isEmpty {
                var j = 0, best = Double.infinity
                for (i, c) in centres.enumerated() { let d = distance(c, labs[k]); if d < best { best = d; j = i } }
                if best <= radius { assign[k] = j; members[j].append(k); continue }
            }
            centres.append(labs[k])
            members.append([k])
            assign[k] = centres.count - 1
        }
        var warnings: [String] = []
        var totals = members.map { $0.reduce(0) { $0 + count[$1] } }
        let totalCells = samples.reduce(0) { $0 + $1.count }
        let threshold = 0.005 * Double(totalCells)
        for j in members.indices.sorted(by: { totals[$0] < totals[$1] }) {
            if Double(totals[j]) >= threshold || members[j].isEmpty { continue }
            let others = members.indices.filter { $0 != j && !members[$0].isEmpty && Double(totals[$0]) >= threshold }
            guard !others.isEmpty else { continue }
            let ds = others.map { distance(centres[$0], centres[j]) }
            let nearest = ds.indices.min { ds[$0] < ds[$1] }!
            let k = others[nearest]
            if ds[nearest] <= 2 * radius {
                let rep = members[k].max { count[$0] < count[$1] }!
                warnings.append("\(totals[j]) cell(s) of \(hex(rgbOf(colours[members[j][0]]))) folded into \(hex(rgbOf(colours[rep]))) (a watermark or symbol tinted them)")
                members[k] += members[j]
                totals[k] += totals[j]
                members[j] = []
                totals[j] = 0
            }
        }
        let keep = members.indices.filter { !members[$0].isEmpty }
        members = keep.map { members[$0] }
        totals = keep.map { totals[$0] }
        for (newJ, m) in members.enumerated() { for i in m { assign[i] = newJ } }
        let reps = members.map { m in m.max { count[$0] != count[$1] ? count[$0] < count[$1] : $0 > $1 }! }  // first of the most frequent
        let rank = members.indices.sorted { totals[$0] != totals[$1] ? totals[$0] > totals[$1] : $0 < $1 }
        var remap = [Int](repeating: 0, count: members.count)
        for (new, old) in rank.enumerated() { remap[old] = new }
        var lookup: [UInt32: UInt8] = [:]
        for (k, c) in colours.enumerated() { lookup[c] = UInt8(remap[assign[k]]) }
        let cells = samples.map { row in row.map { lookup[UInt32($0.0) << 16 | UInt32($0.1) << 8 | UInt32($0.2)]! } }
        let hexes = rank.map { hex(rgbOf(colours[reps[$0]])) }
        for (new, old) in rank.enumerated() where Double(totals[old]) < max(2, 0.001 * Double(totalCells)) {
            warnings.append("colour \(hexes[new]) covers only \(totals[old]) cell(s); a grid line or symbol may have bled in")
        }
        return (cells, hexes, warnings)
    }

    public static func nameColour(_ hexString: String) -> String {
        let l = lab(rgb(hexString) ?? (0, 0, 0))
        return colourNames.min { distance(lab($0.1), l) < distance(lab($1.1), l) }!.0
    }

    /// A, B, ..., Z, AA, AB, ...: 1-3 letters (`importers._code`).
    public static func code(_ i: Int) -> String {
        var letters = ""
        var n = i + 1
        while n > 0 {
            let r = (n - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + r))) + letters
            n = (n - 1) / 26
        }
        return letters
    }
}
```

`max(by:)` in Swift returns the last of equal elements; Python's `max(m, key=...)` returns the first. The `reps` comparator breaks ties on index so the first most-frequent member wins, as in Python. `min(by:)` for `nearest` returns the first minimum, matching `np.argmin`.

- [ ] **Step 4: Run the tests**

Run: `cd ios/Packages/GraphghanCore && swift test --filter GridColoursTests 2>&1 | grep -E "error:|✘|✔ Test run" | head`
Expected: `✔ Test run with 9 tests`. A cluster mismatch on `symbols` (the circles tint a few cells) is the fold-in path: check the warning text and the `2 * radius` rule before touching the port.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GridColours snaps, clusters and names the grid's colours as the Python does (#112 PR 3)"
```

---

### Task 5: `GridChart` (a region to a `ChartDraft`) and `RowsChart.crossCheck` (`_match_by_rows` + `cross_check`)

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/GridChart.swift`
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/RowsChart.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/GridChartTests.swift`
- Modify: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/RowsChartTests.swift`

**Interfaces:**
- Consumes: `GridReader.readRegion`, `GridColours.clusterPalette/nameColour/code`, `ChartDraft`, `ChartWriter.runString`, `RowsChart.Row`.
- Produces: `public struct ImportRecord: Sendable, Equatable { var grid: Bool; var check: Check; var rowsChecked: Int; var rowsTotal: Int; var rowsDisagree: [Int]; var gaugePrinted: Bool; var problem: String?; enum Check: String { finished, stopped, unavailable, none }; func json() -> JSONValue; init?(json: JSONValue?); var sentence: String? }` — the `ext.graphghan.import` object, read back by the detail screen; `sentence` is the §5.4/§6.3 sentence for it (nil for `none`, and for `finished` with nothing disagreeing).
- Produces: `public enum GridChart { public static func draft(image: GridImage, region: Region, title: String) -> (draft: ChartDraft, cells: [UInt8], warnings: [String]) }`: palette codes A, B, … by frequency, names by `nameColour`, rows top to bottom, gauge the format's default (14 × 16 over 4 in, `sc`), `ext` = `ImportRecord(grid: true, check: .none, ...)`.
- Produces: `public enum CheckOutcome: Sendable, Equatable { case compared(disagree: [Int], warnings: [String]); case incomparable(String) }` and `RowsChart.crossCheck(rows: [Row], codes: [String], grid: [UInt8], width: Int, height: Int, row1: String = "bottom-right") -> CheckOutcome`, where `rows` may be a prefix of the pattern (a stopped check) and `grid` is the chart's cells top row first.

- [ ] **Step 1: Write the failing tests**

`GridChartTests.swift`:

```swift
import Foundation
import PDFKit
import Testing
@testable import GraphghanCore

/// A region on a page becomes the chart the library stores; our own PDF's chart page becomes
/// the slice of the chart the Mac exported, colours clustered rather than read from the key.
@Suite struct GridChartTests {
    @Test func theSyntheticGridBecomesAChartWithCodesByFrequency() throws {
        let (img, answer) = try GridReaderTests.fixture("one-grid")
        let region = try #require(try GridReader.findRegions(img).first)
        let (draft, cells, warnings) = GridChart.draft(image: img, region: region, title: "Synthetic")
        #expect(draft.width == 37 && draft.height == 29 && draft.rows.count == 29 && warnings.isEmpty)
        #expect(draft.palette.map(\.code) == ["A", "B", "C", "D"] && draft.palette.map(\.hex) == answer.cluster!.hexes)
        #expect(draft.palette.map(\.name) == answer.cluster!.hexes.map(GridColours.nameColour))
        #expect(cells.map(Int.init) == answer.cluster!.cells.flatMap { $0 })
        #expect(ImportRecord(json: draft.ext) == ImportRecord(grid: true, check: .none, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: false, problem: nil))
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        #expect(chart.id == id && chart.cells == cells && chart.document.gauge.stitch == "sc")
    }

    @Test func theRecordsSentencesAreTheSpecs() {
        func rec(_ check: ImportRecord.Check, _ checked: Int = 77, _ disagree: [Int] = [], problem: String? = nil) -> ImportRecord {
            ImportRecord(grid: true, check: check, rowsChecked: checked, rowsTotal: 77, rowsDisagree: disagree, gaugePrinted: false, problem: problem)
        }
        #expect(rec(.none).sentence == nil && rec(.finished).sentence == nil)
        #expect(rec(.finished, 77, [12, 40, 41]).sentence == "Rows 12, 40 and 41 disagree with the chart. The chart is as drawn; check those rows against the PDF.")
        #expect(rec(.finished, 77, [12]).sentence == "Row 12 disagrees with the chart. The chart is as drawn; check those rows against the PDF.")
        #expect(rec(.stopped, 34).sentence == "Written rows checked up to row 34; 35–77 not checked.")
        #expect(rec(.unavailable, 0).sentence == "Written rows not checked on this iPhone.")
        #expect(rec(.finished, 77, problem: "written rows give 30x77, the chart reads 29x77").sentence == "Written rows could not be compared with the chart: written rows give 30x77, the chart reads 29x77.")
        let json = rec(.stopped, 34, [3]).json()
        #expect(ImportRecord(json: json) == rec(.stopped, 34, [3]) && json["graphghan"]?["import"]?["rows_total"]?.intValue == 77)
    }

    @Test func theOwnPDFsChartPageIsTheSliceTheMacExported() throws {
        let doc = try #require(PDFDocument(url: Fixtures.importPDF("craigh-na-dun-final-sc")))
        let (page, header) = try #require(PageRender.firstChartPage(doc))
        let img = try #require(PageRender.image(page, scale: 4))
        let region = try #require(try GridReader.findRegions(img).first)
        let (draft, cells, _) = GridChart.draft(image: img, region: region, title: "Craigh")
        #expect(draft.width == header.cols && draft.height == header.rows)
        // The Mac's chart, sliced to this page: columns a-b, rows c-d, row 1 at the bottom right.
        let mac = try Chart.load(try Fixtures.data("craigh-na-dun.chart.json"))  // the final-sc chart, 189×184
        var want: [UInt8] = []
        for y in (mac.height - header.rowTo)..<(mac.height - header.rowFrom + 1) {
            for x in (mac.width - header.colTo)..<(mac.width - header.colFrom + 1) { want.append(mac.cells[y * mac.width + x]) }
        }
        // Clusters are by frequency, the Mac's palette by the pattern: compare through the hexes.
        let macHex = mac.palette.map(\.hex)
        let draftHex = draft.palette.map(\.hex)
        #expect(cells.map { draftHex[Int($0)] } == want.map { macHex[Int($0)] })
    }
}
```

`PageRender.Header` gains `colFrom, colTo, rowFrom, rowTo` (the header's a, b, c, d) alongside `cols`/`rows`; update `firstChartPage` to fill them. `Fixtures.data("craigh-na-dun.chart.json")` reads `fixtures/chart-format/`, where the conformance copy of the final-sc chart lives (same id `sha256:cead3f…`).

Append to `RowsChartTests.swift`:

```swift
    // MARK: the cross-check (phone import spec §4.2, §6.3)

    /// The Craigh chart's own written rows against its own cells: nothing disagrees.
    @Test func theOwnRowsAgreeWithTheOwnCells() throws {
        let reading = try ChartWriterTests.reading("craigh-na-dun-final-sc")
        let chart = try Chart.load(ChartWriter.encode(ChartWriter.draft(from: reading, id: "x")).data)
        let rows = reading.rows.map { Row(row: $0.row, runs: $0.runs.map { ($0.code, $0.count) }, total: $0.total) }
        let outcome = RowsChart.crossCheck(rows: rows, codes: reading.palette.map(\.code), grid: chart.cells, width: chart.width, height: chart.height)
        #expect(outcome == .compared(disagree: [], warnings: []))
    }

    @Test func aWrongRowIsNamedAndAPrefixIsComparedAlone() throws {
        let reading = try ChartWriterTests.reading("craigh-na-dun-final-sc")
        let chart = try Chart.load(ChartWriter.encode(ChartWriter.draft(from: reading, id: "x")).data)
        var rows = reading.rows.map { Row(row: $0.row, runs: $0.runs.map { ($0.code, $0.count) }, total: $0.total) }
        // Row 40 with its first two runs swapped in width: same total, different cells.
        let i = rows.firstIndex { $0.row == 40 }!
        var runs = rows[i].runs
        runs[0] = (runs[0].code, runs[0].count - 1)
        runs[1] = (runs[1].code, runs[1].count + 1)
        rows[i] = Row(row: 40, runs: runs, total: rows[i].total)
        #expect(RowsChart.crossCheck(rows: rows, codes: reading.palette.map(\.code), grid: chart.cells, width: chart.width, height: chart.height)
                == .compared(disagree: [40], warnings: []))
        // The first 50 rows alone (a stopped check): still row 40, no "missing rows" problem.
        let prefix = rows.filter { $0.row <= 50 }
        #expect(RowsChart.crossCheck(rows: prefix, codes: reading.palette.map(\.code), grid: chart.cells, width: chart.width, height: chart.height)
                == .compared(disagree: [40], warnings: []))
    }

    @Test func tooManyDisagreementsMeanTheOrientationIsWrong() {
        // Two colours, 4 × 20, rows alternating AAAB / BBBA. Three wrong rows are more than a tenth
        // and refused; two are named. (A whole-chart flip cannot be tested here: the majority
        // vote that pairs chart colours with codes absorbs it on a two-colour chart, as the
        // Python's does.)
        var grid: [UInt8] = []
        for y in 0..<20 { grid += y % 2 == 0 ? [0, 0, 0, 1] : [1, 1, 1, 0] }
        func rows(wrong: [Int]) -> [Row] {
            (1...20).map { r in
                let y = 20 - r
                var runs: [(code: String, count: Int)] = y % 2 == 0 ? [("A", 3), ("B", 1)] : [("B", 3), ("A", 1)]
                if wrong.contains(r) { runs = y % 2 == 0 ? [("A", 1), ("B", 1), ("A", 1), ("B", 1)] : [("B", 1), ("A", 1), ("B", 1), ("A", 1)] }
                if r % 2 == 1 { runs.reverse() }  // RS rows are written right to left
                return Row(row: r, runs: runs, total: nil)
            }
        }
        #expect(RowsChart.crossCheck(rows: rows(wrong: [5, 9, 13]), codes: ["A", "B"], grid: grid, width: 4, height: 20)
                == .incomparable("3 of 20 rows disagree with the chart; the row-1 position or direction is probably wrong, not the rows."))
        #expect(RowsChart.crossCheck(rows: rows(wrong: [5, 9]), codes: ["A", "B"], grid: grid, width: 4, height: 20)
                == .compared(disagree: [5, 9], warnings: []))
    }

    @Test func rowsThatDoNotAssembleOrPairAreIncomparable() {
        let grid: [UInt8] = [0, 1, 0, 1]
        #expect(RowsChart.crossCheck(rows: [Row(row: 1, runs: [("A", 1)], total: nil)], codes: ["A", "B"], grid: grid, width: 2, height: 2)
                == .incomparable("row 1: runs sum to 1, chart width is 2"))
        // Both chart colours read as A in the rows: the picture has more colours than the key.
        #expect(RowsChart.crossCheck(rows: [Row(row: 1, runs: [("A", 2)], total: nil), Row(row: 2, runs: [("A", 2)], total: nil)], codes: ["A", "B"], grid: grid, width: 2, height: 2)
                == .incomparable("two chart colours both read as [\"A\"] in the written rows; the picture has more colours than the key, or a row is wrong"))
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter "GridChartTests|RowsChartTests" 2>&1 | grep -E "error:|✘|✔ Test run" | head`
Expected: compile errors, `GridChart`, `ImportRecord`, `crossCheck` undefined.

- [ ] **Step 3: `ImportRecord` and `GridChart`**

`GridChart.swift`:

```swift
import Foundation

/// `ext.graphghan.import` (phone import spec §6.3): where the chart came from and how far the
/// written rows were checked against it. The chart id ignores it; the detail screen reads it.
public struct ImportRecord: Sendable, Equatable {
    public enum Check: String, Sendable { case finished, stopped, unavailable, none }
    public var grid: Bool
    public var check: Check
    /// The highest row number compared, and how many written rows the pages hold.
    public var rowsChecked: Int
    public var rowsTotal: Int
    public var rowsDisagree: [Int]
    public var gaugePrinted: Bool
    /// Why the rows could not be compared at all (`CheckOutcome.incomparable`), when they could not.
    public var problem: String?

    public init(grid: Bool, check: Check, rowsChecked: Int, rowsTotal: Int, rowsDisagree: [Int], gaugePrinted: Bool, problem: String?) {
        self.grid = grid
        self.check = check
        self.rowsChecked = rowsChecked
        self.rowsTotal = rowsTotal
        self.rowsDisagree = rowsDisagree
        self.gaugePrinted = gaugePrinted
        self.problem = problem
    }

    public func json() -> JSONValue {
        var o: [String: JSONValue] = [
            "source": .string("pdf"), "grid": .bool(grid), "check": .string(check.rawValue),
            "rows_checked": .int(rowsChecked), "rows_total": .int(rowsTotal),
            "rows_disagree": .array(rowsDisagree.map(JSONValue.int)), "gauge_printed": .bool(gaugePrinted),
        ]
        if let problem { o["problem"] = .string(problem) }
        return .object(["graphghan": .object(["import": .object(o)])])
    }

    /// The record inside a chart document's `ext`, or nil when it has none.
    public init?(json ext: JSONValue?) {
        guard let o = ext?["graphghan"]?["import"], let check = Check(rawValue: o["check"]?.stringValue ?? "") else { return nil }
        self.init(grid: o["grid"]?.boolValue ?? false, check: check, rowsChecked: o["rows_checked"]?.intValue ?? 0,
                  rowsTotal: o["rows_total"]?.intValue ?? 0,
                  rowsDisagree: (o["rows_disagree"]?.arrayValue ?? []).compactMap(\.intValue), gaugePrinted: o["gauge_printed"]?.boolValue ?? false,
                  problem: o["problem"]?.stringValue)
    }

    /// The sentence the sheet and the detail screen show for this record (spec §5.4, §6.3); nil
    /// when there is nothing to say.
    public var sentence: String? {
        if let problem { return "Written rows could not be compared with the chart: \(problem)." }
        switch check {
        case .none: return nil
        case .unavailable: return "Written rows not checked on this iPhone."
        case .stopped:
            let disagree = rowsDisagree.isEmpty ? "" : " " + Self.disagreeSentence(rowsDisagree)
            return "Written rows checked up to row \(rowsChecked); \(rowsChecked + 1)–\(rowsTotal) not checked." + disagree
        case .finished: return rowsDisagree.isEmpty ? nil : Self.disagreeSentence(rowsDisagree)
        }
    }

    /// "Rows 12, 40 and 41 disagree with the chart. The chart is as drawn; check those rows against the PDF."
    static func disagreeSentence(_ rows: [Int]) -> String {
        let list: String
        switch rows.count {
        case 1: list = "Row \(rows[0]) disagrees"
        case 2: list = "Rows \(rows[0]) and \(rows[1]) disagree"
        default: list = "Rows " + rows.dropLast().map(String.init).joined(separator: ", ") + " and \(rows[rows.count - 1]) disagree"
        }
        return "\(list) with the chart. The chart is as drawn; check those rows against the PDF."
    }
}

/// A grid region on a page as the chart the library stores (phone import spec §4.2): colours
/// clustered by frequency and coded A, B, …, named by the nearest named colour, the format's
/// default gauge since a picture prints none.
public enum GridChart {
    public static func draft(image: GridImage, region: Region, title: String) -> (draft: ChartDraft, cells: [UInt8], warnings: [String]) {
        let samples = GridReader.readRegion(image, region)
        let (grid, hexes, warnings) = GridColours.clusterPalette(samples)
        let palette = hexes.enumerated().map { ChartDraft.Palette(code: GridColours.code($0.offset), name: GridColours.nameColour($0.element), hex: $0.element) }
        let codes = palette.map(\.code)
        let rows = grid.map { row -> String in
            var runs: [(code: String, count: Int)] = []
            for c in row {
                if let last = runs.last, last.code == codes[Int(c)] { runs[runs.count - 1].count += 1 } else { runs.append((codes[Int(c)], 1)) }
            }
            return ChartWriter.runString(runs)
        }
        var gauge = ChartDraft.Gauge()
        gauge.stitch = "sc"
        let record = ImportRecord(grid: true, check: .none, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: false, problem: nil)
        let draft = ChartDraft(pattern: .init(id: "", title: title, version: "0.1.0"), palette: palette, rows: rows,
                               width: region.cols, height: region.rows, gauge: gauge, ext: record.json())
        return (draft, grid.flatMap { $0 }, region.warnings + warnings)
    }
}
```

- [ ] **Step 4: `crossCheck` in `RowsChart`**

Append inside `RowsChart`:

```swift
    public static let mismatchLimit = 0.10  // MISMATCH_LIMIT: more rows than this disagreeing means the orientation is wrong

    /// The written grid as palette indexes in display order, nil in the rows not given (`written_to_grid`
    /// over a prefix): a stopped check compares only what was read. Problems are the Python's,
    /// except that missing rows are not a problem here.
    static func writtenGrid(rows: [Row], codes: [String], width: Int, height: Int, row1: String) -> Result<[UInt8?], Problems> {
        var problems = totalProblems(rows, width: width)
        var counts: [Int: Int] = [:]
        for r in rows { counts[r.row, default: 0] += 1 }
        let dup = counts.filter { $0.value > 1 }.keys.sorted()
        if !dup.isEmpty { problems.append("row " + dup.map(String.init).joined(separator: ", ") + " printed twice") }
        let beyond = counts.keys.filter { $0 > height || $0 < 1 }.sorted()
        if !beyond.isEmpty { problems.append("rows \(ranges(beyond)) are beyond the chart height \(height)") }
        let index = Dictionary(uniqueKeysWithValues: codes.enumerated().map { ($0.element, UInt8($0.offset)) })
        for r in rows {
            if let bad = r.runs.first(where: { index[$0.code] == nil }) {
                problems.append("row \(r.row) uses code '\(bad.code)', not in the palette [\(codes.map { "\"\($0)\"" }.joined(separator: ", "))]")
            }
        }
        if !problems.isEmpty { return .failure(Problems(sentences: problems)) }
        var grid = [UInt8?](repeating: nil, count: width * height)
        for r in rows {
            var cells: [UInt8] = []
            for run in r.runs { cells += [UInt8](repeating: index[run.code]!, count: run.count) }
            if readsRightToLeft(row: r.row, row1: row1) { cells.reverse() }
            let y = gridRow(row: r.row, height: height, row1: row1)
            for (x, c) in cells.enumerated() { grid[y * width + x] = c }
        }
        return .success(grid)
    }

    /// The written rows against the grid read off the chart (`_match_by_rows` then
    /// `cross_check`): the chart's colour clusters are paired with the key's codes by a majority
    /// vote over the cells the rows put in them, then each written row is compared with its grid
    /// row. Disagreements are row numbers; a pairing that fails, or more than a tenth of the rows
    /// disagreeing, means the rows cannot be compared and says why.
    public static func crossCheck(rows: [Row], codes: [String], grid: [UInt8], width: Int, height: Int, row1: String = "bottom-right") -> CheckOutcome {
        let written: [UInt8?]
        switch writtenGrid(rows: rows, codes: codes, width: width, height: height, row1: row1) {
        case .success(let g): written = g
        case .failure(let p): return .incomparable(p.sentences.joined(separator: "; "))
        }
        guard grid.count == width * height else { return .incomparable("the chart has \(grid.count) cells, not \(width) × \(height)") }
        // Majority vote: which key code each chart colour is, over the cells the rows cover.
        var warnings: [String] = []
        let clusterCount = Int(grid.max() ?? 0) + 1
        var mapping: [Int: Int] = [:]
        for g in 0..<clusterCount {
            var counts = [Int](repeating: 0, count: codes.count)
            var total = 0
            for i in 0..<grid.count where Int(grid[i]) == g { if let w = written[i] { counts[Int(w)] += 1; total += 1 } }
            guard total > 0 else { continue }
            let k = counts.indices.max { counts[$0] != counts[$1] ? counts[$0] < counts[$1] : $0 > $1 }!  // first of the most frequent
            let share = Double(counts[k]) / Double(total)
            if share < 0.9 {
                warnings.append("chart colour \(g) is '\(codes[k])' in \(Int((share * 100).rounded()))% of its cells and other codes elsewhere; the rows and the picture disagree there")
            }
            mapping[g] = k
        }
        let claimed = mapping.values.sorted()
        if Set(claimed).count != claimed.count {
            let dup = Set(claimed.filter { k in claimed.filter { $0 == k }.count > 1 }).map { codes[$0] }.sorted()
            return .incomparable("two chart colours both read as [\(dup.map { "\"\($0)\"" }.joined(separator: ", "))] in the written rows; the picture has more colours than the key, or a row is wrong")
        }
        let coveredRows = (0..<height).filter { y in written[y * width] != nil }
        let unmatched = (0..<clusterCount).filter { g in mapping[g] == nil && coveredRows.contains { y in (0..<width).contains { Int(grid[y * width + $0]) == g } } }
        if !unmatched.isEmpty {
            return .incomparable("chart colours \(unmatched) fall on no written row; the picture and the rows do not line up")
        }
        // Compare, row by row, the rows that were written.
        var mismatches: [Int] = []
        var flippedTB = true, flippedLR = true, rotated = true
        for y in coveredRows {
            let row = row1.hasPrefix("bottom") ? height - y : y + 1
            var differ = false
            for x in 0..<width {
                let g = mapping[Int(grid[y * width + x])]
                if let w = written[y * width + x], Int(w) != g { differ = true }
                let tb = mapping[Int(grid[(height - 1 - y) * width + x])], lr = mapping[Int(grid[y * width + (width - 1 - x)])]
                let rt = mapping[Int(grid[(height - 1 - y) * width + (width - 1 - x)])]
                if let w = written[y * width + x] {
                    if Int(w) != tb { flippedTB = false }
                    if Int(w) != lr { flippedLR = false }
                    if Int(w) != rt { rotated = false }
                }
            }
            if differ { mismatches.append(row) }
        }
        mismatches.sort()
        if mismatches.count > max(1, Int((mismatchLimit * Double(coveredRows.count)).rounded(.up))) {
            var hint = ""
            if flippedTB { hint = " The grid matches when flipped top to bottom: chart.row1 probably starts at the other edge." }
            else if flippedLR { hint = " The grid matches when flipped left to right: chart.row1 probably starts at the other corner." }
            else if rotated { hint = " The grid matches when rotated: chart.row1 is probably the opposite corner." }
            return .incomparable("\(mismatches.count) of \(coveredRows.count) rows disagree with the chart; the row-1 position or direction is probably wrong, not the rows.\(hint)")
        }
        return .compared(disagree: mismatches, warnings: warnings)
    }
```

and, at file scope:

```swift
/// What a row check found (phone import spec §4.2): the rows that disagree, or why no comparison
/// could be made.
public enum CheckOutcome: Sendable, Equatable {
    case compared(disagree: [Int], warnings: [String])
    case incomparable(String)
}
```

Two notes. The Python's `cross_check` error counts against `height`; here it counts against the rows actually compared so a 10-row prefix with two wrong rows is refused the same way a whole chart would be. The flip hints test the written rows against the flipped grid over the covered rows only, which for a prefix can be a coincidence; that is the Python's rule too, over the whole chart. Keep the exact Python sentences: the app shows `incomparable`'s text on the detail screen after "Written rows could not be compared with the chart: ".

- [ ] **Step 5: Run the tests**

Run: `cd ios/Packages/GraphghanCore && swift test 2>&1 | grep -E "error:|✘|✔ Test run" | head`
Expected: the whole core suite green, `GridChartTests` 3 and the four new `RowsChartTests` among them. The own-PDF slice test is the one that can surprise: PDFKit's antialiasing on the 0.3 pt grid lines can shift a cluster's representative hex by one step from the Mac's (`#f2e8d5` read as `#f2e8d4`). If so, compare through `GridColours.rgb` with a per-channel tolerance of 2 and say so in the test's comment; do not loosen anything else.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GridChart turns a region into a chart draft, and RowsChart checks written rows against it (#112 PR 3)"
```

---

### Task 6: `PageRenderer` and the importer's grid path, the check, and saving with the record

**Files:**
- Create: `ios/Graphghan/Services/PageRenderer.swift`
- Modify: `ios/Graphghan/Services/PDFImporter.swift`
- Modify: `ios/Tests/PDFImportTests.swift`

**Interfaces:**
- Consumes: `GridReader.findRegions/maxPixels/maxNoise`, `GridChart.draft`, `ImportRecord`, `RowsChart.crossCheck`, `CheckOutcome`, `RowText.rowCount`, `RowReading`.
- Produces: `enum PageRenderer { static let renderScale: CGFloat = 4; static func scale(for box: CGRect) -> CGFloat?; static func image(_ page: PDFPage) -> GridImage? }`.
- Produces: `PDFImportSource` gains `.grid(page: Int, rowsToCheck: Int)` (1-based page; 0 rows means no check). `PDFImportReading` gains `draft: ChartDraft` (id already the slug), `fileName`, `version`, `pageTexts: [String]`, `warnings: [String]`.
- Produces: `PDFImporter.check(_ reading: PDFImportReading, progress: (@Sendable (PDFImportProgress) -> Void)?) async -> ImportRecord` and `save(_ reading: PDFImportReading, record: ImportRecord?) async throws -> PatternManifest` (nil keeps the draft's ext as read). `PDFImportProgress` gains `.checking(done: Int, of: Int)`.

- [ ] **Step 1: Write the failing tests**

Append to `PDFImportTests.swift` (inside the suite), plus a chart-drawing helper on `PDFTestDocuments`:

```swift
    // MARK: a chart in the PDF (PR 3)

    /// The synthetic chart the tests draw: 20 × 15, four colours, the first three columns one
    /// colour (where lines hide) and the last two rows another, as the Python fixtures do.
    static let chartWidth = 20, chartHeight = 15
    static let chartHexes = ["#f2e8d5", "#2b2f33", "#1e4d3a", "#d9a21b"]
    static func chartCell(x: Int, y: Int) -> Int {  // y from the top
        if x < 3 { return 1 }
        if y >= chartHeight - 2 { return 3 }
        return (x * 7 + y * 3) % 4
    }

    /// The written rows for that chart, numbered from the bottom, odd rows written right to left.
    static func chartDocument(wrongRow: Int? = nil) -> ProseDocument {
        var doc = ProseDocument()
        doc.pattern = ["title": "Drawn Chart"]
        doc.palette = chartHexes.enumerated().map { .init(code: ["A", "B", "C", "D"][$0.offset], name: "", hex: $0.element) }
        doc.chart = .init(width: chartWidth, height: chartHeight)
        var rows: [ProseDocument.Row] = []
        for r in 1...chartHeight {
            let y = chartHeight - r
            var cells = (0..<chartWidth).map { chartCell(x: $0, y: y) }
            if r == wrongRow { cells[5] = (cells[5] + 1) % 4 }
            if r % 2 == 1 { cells.reverse() }
            var runs: [[ProseDocument.RunValue]] = []
            for c in cells {
                let code = ["A", "B", "C", "D"][c]
                if let last = runs.last, case .code(let lc) = last[0], lc == code, case .count(let n) = last[1] { runs[runs.count - 1] = [.code(code), .count(n + 1)] }
                else { runs.append([.code(code), .count(1)]) }
            }
            rows.append(.init(row: r, page: 2, text: "Row \(r)", runs: runs))
        }
        doc.written_rows = rows
        return doc
    }

    @Test func aChartPageBecomesTheChartBeforeAnyRowIsRead() async throws {
        let base = try await make()
        let importer = base.importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.chart(rows: true))
        let reading = try await importer.read(pdf, fileName: "drawn.pdf")
        #expect(reading.width == Self.chartWidth && reading.height == Self.chartHeight && reading.colours == 4)
        #expect(reading.source == .grid(page: 1, rowsToCheck: Self.chartHeight))
        #expect(reading.bundle.manifest.id == "drawn" && reading.bundle.manifest.title == "drawn")  // no key page read yet: the file's stem
        let chart = reading.bundle.charts[0].chart
        let hexes = chart.palette.map(\.hex)
        for y in 0..<Self.chartHeight { for x in 0..<Self.chartWidth {
            #expect(hexes[Int(chart.cells[y * Self.chartWidth + x])] == Self.chartHexes[Self.chartCell(x: x, y: y)], "cell \(x),\(y)")
        } }
        #expect(ImportRecord(json: chart.document.ext)?.check == .none && ImportRecord(json: chart.document.ext)?.grid == true)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: base.chartsDir.path)) ?? []).isEmpty)
    }

    @Test func theCheckFinishesCleanOrNamesTheRow() async throws {
        let pdf = try #require(PDFTestDocuments.chart(rows: true))
        let clean = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .zero))
        let reading = try await clean.read(pdf, fileName: "drawn.pdf")
        let seen = Progress()
        let record = await clean.check(reading) { p in Task { await seen.add(p) } }
        #expect(record == ImportRecord(grid: true, check: .finished, rowsChecked: 15, rowsTotal: 15, rowsDisagree: [], gaugePrinted: false, problem: nil))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await seen.items.contains(.checking(done: 15, of: 15)))
        let wrong = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(wrongRow: 5), delayPerRow: .zero))
        let record2 = await wrong.check(try await wrong.read(pdf, fileName: "drawn.pdf"), progress: nil)
        #expect(record2.check == .finished && record2.rowsDisagree == [5] && record2.problem == nil)
    }

    @Test func withoutAModelTheCheckIsUnavailableAndWithoutRowsThereIsNone() async throws {
        let none = try await make().importer(rowReader: nil, modelUnavailable: "needs iOS 26")
        let reading = try await none.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        #expect(reading.source == .grid(page: 1, rowsToCheck: Self.chartHeight))
        #expect(await none.check(reading, progress: nil).check == .unavailable)
        let noRows = try await none.read(try #require(PDFTestDocuments.chart(rows: false)), fileName: "drawn.pdf")
        #expect(noRows.source == .grid(page: 1, rowsToCheck: 0))
        #expect(await none.check(noRows, progress: nil).check == .none)
    }

    @Test func aCancelledCheckIsStoppedAtTheRowsRead() async throws {
        let importer = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .milliseconds(200)))
        let reading = try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let task = Task { await importer.check(reading, progress: nil) }
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        let record = await task.value
        #expect(record.check == .stopped && record.rowsTotal == 15 && record.rowsChecked < 15 && record.problem == nil)
    }

    @Test func savingWithARecordWritesItIntoTheChart() async throws {
        let base = try await make()
        let importer = base.importer()
        let reading = try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let record = ImportRecord(grid: true, check: .stopped, rowsChecked: 4, rowsTotal: 15, rowsDisagree: [2], gaugePrinted: false, problem: nil)
        let manifest = try await importer.save(reading, record: record)
        let stored = try await base.charts.chart(id: manifest.charts[0].id)
        #expect(ImportRecord(json: stored.document.ext) == record && stored.id == reading.bundle.charts[0].chart.id)
    }

    @Test func theRenderScaleFitsTheBudget() {
        #expect(PageRenderer.scale(for: CGRect(x: 0, y: 0, width: 612, height: 792)) == 4)
        #expect(PageRenderer.scale(for: CGRect(x: 0, y: 0, width: 3000, height: 3000)) == 2)
        #expect(PageRenderer.scale(for: CGRect(x: 0, y: 0, width: 7000, height: 7000)) == nil)
    }
```

`ChartLibrary` is an actor with `chart(id:)`; `ManifestChart.id` is the chart id.

In `PDFTestDocuments`:

```swift
    /// A page with the synthetic chart drawn at 12 pt cells (48 px at 4×), grid lines 0.5 pt with
    /// every fifth bold, numbers above and beside; with `rows`, a second page of written rows.
    static func chart(rows: Bool) -> Data? {
        let cell: CGFloat = 12, ox: CGFloat = 60, oy: CGFloat = 80
        let w = PDFImportTests.chartWidth, h = PDFImportTests.chartHeight
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            for y in 0..<h { for x in 0..<w {
                let rgb = GridColours.rgb(PDFImportTests.chartHexes[PDFImportTests.chartCell(x: x, y: y)])!
                cg.setFillColor(CGColor(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1))
                cg.fill(CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: cell, height: cell))
            } }
            for x in 0...w {
                let bold = (w - x) % 5 == 0
                cg.setStrokeColor(bold ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 0.55, alpha: 1))
                cg.setLineWidth(bold ? 1 : 0.5)
                cg.move(to: CGPoint(x: ox + CGFloat(x) * cell, y: oy)); cg.addLine(to: CGPoint(x: ox + CGFloat(x) * cell, y: oy + CGFloat(h) * cell)); cg.strokePath()
            }
            for y in 0...h {
                let bold = (h - y) % 5 == 0
                cg.setStrokeColor(bold ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 0.55, alpha: 1))
                cg.setLineWidth(bold ? 1 : 0.5)
                cg.move(to: CGPoint(x: ox, y: oy + CGFloat(y) * cell)); cg.addLine(to: CGPoint(x: ox + CGFloat(w) * cell, y: oy + CGFloat(y) * cell)); cg.strokePath()
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 6)]
            for x in 0..<w { ("\(w - x)" as NSString).draw(at: CGPoint(x: ox + CGFloat(x) * cell + 2, y: oy - 9), withAttributes: attrs) }
            for y in 0..<h { ("\(h - y)" as NSString).draw(at: CGPoint(x: ox - 14, y: oy + CGFloat(y) * cell + 3), withAttributes: attrs) }
            if rows {
                ctx.beginPage()
                let text = (1...h).map { "Row \($0): sc across in the colours shown" }.joined(separator: "\n")
                (text as NSString).draw(in: bounds.insetBy(dx: 36, dy: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
    }
```

The row page's text only has to hold row heads (`RowText.rowCount` counts them); the stub reader supplies the runs.

- [ ] **Step 2: Run to see them fail**

Run the app suite filtered to `PDFImportTests` (Global Constraints). Expected: compile errors, `PageRenderer`, `.grid`, `check`, `.checking` undefined.

- [ ] **Step 3: `PageRenderer`**

`PageRenderer.swift`:

```swift
import CoreGraphics
import Foundation
import GraphghanCore
import PDFKit

/// A PDF page as the grid reader's image, under the render budget (phone import spec §5.1): the
/// importer's 4× (288 dpi, a 10 pt cell is 40 px), halved until the bitmap is at most
/// `GridReader.maxPixels`; a page over the budget at 1× is not rendered.
enum PageRenderer {
    static let renderScale: CGFloat = 4  // RENDER_SCALE

    static func scale(for box: CGRect) -> CGFloat? {
        var s = renderScale
        while s >= 1 {
            if Double(box.width * s) * Double(box.height * s) <= Double(GridReader.maxPixels) { return s }
            s /= 2
        }
        return nil
    }

    static func image(_ page: PDFPage) -> GridImage? {
        let box = page.bounds(for: .mediaBox)
        guard let scale = scale(for: box) else { return nil }
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 0, h > 0 else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else { return nil }
        return GridImage(cgImage: image)
    }
}
```

- [ ] **Step 4: The importer**

In `PDFImporter.swift`:

`PDFImportProgress` gains `case checking(done: Int, of: Int)`. `PDFImportSource` gains `case grid(page: Int, rowsToCheck: Int)`. `PDFImportReading` becomes:

```swift
struct PDFImportReading: Sendable {
    let bundle: PatternBundle
    let preview: Data
    let width: Int
    let height: Int
    let colours: Int
    let source: PDFImportSource
    /// What was assembled, so "Add to library" can write the check's record into it (§6.3).
    let draft: ChartDraft
    let title: String
    let version: String
    let fileName: String
    let pageTexts: [String]
    let warnings: [String]
}
```

`read` gains the grid step between the own-PDF branch and the rows guard:

```swift
        if let grid = try await readGrid(document, texts: texts, title: title, fileName: fileName, progress: progress) { return grid }
```

and the new methods:

```swift
    // MARK: a chart on a page (spec §4.2, §5.1 step 2)

    /// The smallest grid that counts as a chart (spec §5.1).
    static let minimumGridSide = 8

    func readGrid(_ document: PDFDocument, texts: [String], title: String, fileName: String,
                  progress: (@Sendable (PDFImportProgress) -> Void)?) async throws(PDFImportError) -> PDFImportReading? {
        var best: (page: Int, region: Region)?
        var warnings: [String] = []
        for i in 0..<document.pageCount {
            if Task.isCancelled { throw .cancelled }
            guard let page = document.page(at: i) else { continue }
            guard let image = PageRenderer.image(page) else { warnings.append("page \(i + 1) is too large to read"); continue }
            let regions = (try? GridReader.findRegions(image)) ?? []  // tooLarge cannot happen under the budget
            for r in regions where r.cols >= Self.minimumGridSide && r.rows >= Self.minimumGridSide {
                if best == nil || r.cells > best!.region.cells { best = (i, r) }
            }
            progress?(.pages(done: i + 1, of: document.pageCount))
        }
        guard let best, let page = document.page(at: best.page), let image = PageRenderer.image(page) else { return nil }
        let patternTitle = title.isEmpty ? Self.stem(fileName) : title
        let (draft, _, gridWarnings) = GridChart.draft(image: image, region: best.region, title: patternTitle)
        return try await assemble(draft: draft, title: patternTitle, version: "0.1.0", fileName: fileName, texts: texts,
                                  source: .grid(page: best.page + 1, rowsToCheck: RowText.rowCount(in: texts)), warnings: warnings + gridWarnings)
    }

    /// The written rows read and compared with the chart (spec §4.2): the outcome as the record
    /// the chart carries. Cancelling stops the reader between rows; what was read is compared.
    func check(_ reading: PDFImportReading, progress: (@Sendable (PDFImportProgress) -> Void)?) async -> ImportRecord {
        var record = ImportRecord(json: reading.draft.ext) ?? ImportRecord(grid: true, check: .none, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: false, problem: nil)
        guard case .grid(_, let total) = reading.source, total > 0 else { record.check = .none; return record }
        record.rowsTotal = total
        guard let rowReader else { record.check = .unavailable; return record }
        progress?(.checking(done: 0, of: total))
        let doc = await rowReader.read(pages: reading.pageTexts) { p in progress?(.checking(done: p.rowsSoFar, of: p.rowsTotal)) }
        let stopped = Task.isCancelled
        let all = (doc.written_rows ?? []).filter { $0.error == nil && !$0.runs.isEmpty }
        let rows = all.map { RowsChart.Row(row: $0.row, runs: $0.runs.map(Self.run), total: $0.total) }
        var codes = (doc.palette ?? []).map(\.code)
        if codes.isEmpty { for r in rows { for run in r.runs where !codes.contains(run.code) { codes.append(run.code) } } }
        record.check = stopped ? .stopped : .finished
        record.rowsChecked = rows.map(\.row).max() ?? 0
        let chart = reading.bundle.charts[0].chart
        if let w = doc.chart?.width, let h = doc.chart?.height, w > 0, h > 0, (w, h) != (chart.width, chart.height) {
            record.problem = "written rows give \(w)x\(h), the chart reads \(chart.width)x\(chart.height)"
            return record
        }
        guard !rows.isEmpty else { record.problem = "no written rows could be read"; return record }
        switch RowsChart.crossCheck(rows: rows, codes: codes, grid: chart.cells, width: chart.width, height: chart.height, row1: doc.chart?.row1 ?? "bottom-right") {
        case .compared(let disagree, _): record.rowsDisagree = disagree
        case .incomparable(let why): record.problem = why
        }
        return record
    }
```

`assemble` gains `texts: [String]` and `warnings: [String]` parameters (the own and rows paths pass `texts` and `[]`), stores them and the draft, title, version and file name in the reading; its encode-preview-manifest-bundle body moves into `bundle(for draft: ChartDraft, title: String, version: String, fileName: String) throws(PDFImportError) -> (PatternBundle, Data, Chart)` so `save` can rebuild it:

```swift
    func save(_ reading: PDFImportReading, record: ImportRecord? = nil) async throws -> PatternManifest {
        var bundle = reading.bundle
        if let record {
            var draft = reading.draft
            draft.ext = record.json()
            bundle = try Self.bundle(for: draft, title: reading.title, version: reading.version, fileName: reading.fileName).0
        }
        for chart in bundle.charts { _ = try await charts.store(chart.data) }
        try await local.save(bundle)
        return bundle.manifest
    }
```

The rows path's own `ext` literal becomes `ImportRecord(grid: false, check: .none, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: gaugePrinted, problem: nil).json()`. The existing `PDFImportSheetTests` and the PR 2 tests keep passing unchanged: `save(_:)` still works with the default nil record.

- [ ] **Step 5: Run the tests**

Run the app suite filtered to `PDFImportTests` and `PDFImportSheetTests`. Expected: all green (16 + 8). If the drawn chart reads fewer than 20 × 15, the 0.5 pt lines rendered at 4× are 2 px grey (0.55) on colour: `EDGE_THRESHOLD` 16 sees them; check `PageRenderer.image` did not flip (the numbers row must be above the grid) before touching the reader.

- [ ] **Step 6: Commit**

```bash
git add ios/Graphghan/Services ios/Tests/PDFImportTests.swift
git commit -m "ios: PDFImporter reads a chart's grid first, checks the written rows against it, and saves the check's record (#112 PR 3)"
```

---

### Task 7: The sheet's check under "Chart found", Skip, Add-before-the-end, and the detail screen's sentence

**Files:**
- Modify: `ios/Graphghan/Patterns/PDFImportSheet.swift`
- Modify: `ios/Graphghan/AppModel.swift`
- Modify: `ios/Graphghan/Patterns/PatternDetailContent.swift`
- Modify: `ios/Tests/PDFImportSheetTests.swift`

**Interfaces:**
- Consumes: `PDFImporter.check(_:progress:)`, `save(_:record:)`, `PDFImportProgress.checking`, `PDFImportSource.grid`, `ImportRecord.sentence`.
- Produces: `PDFImportState.CheckStage { case none; case running(done: Int, of: Int); case done(ImportRecord) }`, `PDFImportState.check: CheckStage`, `PDFImportState.checkTask: Task<Void, Never>?`; `AppModel.skipPDFCheck()`.

- [ ] **Step 1: Write the failing tests**

Append to `PDFImportSheetTests.swift`:

```swift
    // MARK: a chart in the PDF (PR 3)

    @Test func aChartIsFoundThenTheCheckRunsUnderneathAndFinishes() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(wrongRow: 3), delayPerRow: .milliseconds(20)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let state = try #require(model.pdfImport)
        #expect(state.stage == .found && state.reading?.source == .grid(page: 1, rowsToCheck: 15))
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        let done = try #require(await Self.checkState(of: model) { if case .done = $0 { return true }; return false })
        guard case .done(let record) = done else { return }
        #expect(record.check == .finished && record.rowsDisagree == [3])
        #expect(record.sentence == "Row 3 disagrees with the chart. The chart is as drawn; check those rows against the PDF.")
        await model.addImportedPDF()
        #expect(model.pdfImport == nil)
        #expect(model.libraryItems.contains { $0.source == .local && $0.slug == "drawn" })
        let manifest = try await model.manifest(for: "drawn", path: nil)
        let chart = try await model.charts.chart(id: manifest.charts[0].id)
        #expect(ImportRecord(json: chart.document.ext) == record)
    }

    @Test func skipStopsTheCheckAndAddSavesWhatWasChecked() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(300)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        model.skipPDFCheck()
        let done = try #require(await Self.checkState(of: model) { if case .done = $0 { return true }; return false })
        guard case .done(let record) = done else { return }
        #expect(record.check == .stopped && record.rowsTotal == 15 && record.rowsChecked < 15)
        #expect(record.sentence?.hasPrefix("Written rows checked up to row \(record.rowsChecked); \(record.rowsChecked + 1)–15 not checked.") == true)
    }

    @Test func addingBeforeTheCheckEndsSavesItAsStopped() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(300)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        await model.addImportedPDF()
        let manifest = try await model.manifest(for: "drawn", path: nil)
        let chart = try await model.charts.chart(id: manifest.charts[0].id)
        let record = try #require(ImportRecord(json: chart.document.ext))
        #expect(record.check == .stopped && record.rowsTotal == 15)
    }

    @Test func withoutAModelTheChartIsSavedUnchecked() async throws {
        let model = try await make(rowReader: nil, modelUnavailable: "needs iOS 26")
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let done = try #require(await Self.checkState(of: model) { if case .done = $0 { return true }; return false })
        guard case .done(let record) = done else { return }
        #expect(record.check == .unavailable && record.sentence == "Written rows not checked on this iPhone.")
        await model.addImportedPDF()
        #expect(model.libraryItems.contains { $0.slug == "drawn" })
    }

    @Test func cancelDuringTheCheckWritesNothing() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(300)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        model.cancelPDFImport()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.pdfImport == nil && model.libraryItems.isEmpty)
    }

    /// The sheet's check stage once `test` accepts it, or nil after three seconds.
    static func checkState(of model: AppModel, _ test: (PDFImportState.CheckStage) -> Bool) async -> PDFImportState.CheckStage? {
        for _ in 0..<300 {
            if let s = model.pdfImport?.check, test(s) { return s }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
```

`model.manifest(for:path:)` returns the local pattern's manifest once it is loaded; `ChartLibrary` is an actor with `chart(id:)`.

- [ ] **Step 2: Run to see them fail**

Run the app suite filtered to `PDFImportSheetTests`. Expected: compile errors, `CheckStage`, `skipPDFCheck` undefined.

- [ ] **Step 3: The state, the model, the sheet, the detail line**

`PDFImportState`:

```swift
    enum CheckStage: Equatable {
        case none
        case running(done: Int, of: Int)
        case done(ImportRecord)
    }
    /// The row check under "Chart found" (spec §5.2), and its task so Skip and Cancel can stop it.
    var check: CheckStage = .none
    var checkTask: Task<Void, Never>? = nil
```

`AppModel.importPDF`, after `state.stage = .found` in the success branch:

```swift
                if case .grid = reading.source { self?.startPDFCheck(state, importer: importer) }
```

and the new methods:

```swift
    /// The written rows against the chart, after the chart is on screen (spec §4.2). The record
    /// lands in `state.check`; "Add to library" writes it into the chart.
    private func startPDFCheck(_ state: PDFImportState, importer: PDFImporter) {
        guard let reading = state.reading else { return }
        if case .grid(_, let total) = reading.source, total > 0, rowReader != nil { state.check = .running(done: 0, of: total) }
        state.checkTask = Task {
            let record = await importer.check(reading) { p in
                Task { @MainActor in
                    if case .checking(let done, let of) = p, case .running = state.check { state.check = .running(done: done, of: of) }
                }
            }
            state.check = .done(record)
        }
    }

    /// "Skip the check": the reader stops between rows; what it read is compared and recorded.
    func skipPDFCheck() {
        pdfImport?.checkTask?.cancel()
    }
```

`addImportedPDF` becomes:

```swift
    func addImportedPDF() async {
        guard let state = pdfImport, let reading = state.reading, state.stage == .found || state.stage == .saving else { return }
        state.stage = .saving
        // Adding before the check ends stops it; its record (stopped at the row it reached) is saved.
        if let task = state.checkTask { task.cancel(); await task.value }
        var record: ImportRecord?
        if case .done(let r) = state.check { record = r }
        let importer = pdfImporter
        do {
            let manifest = try await importer.save(reading, record: record)
            ...unchanged...
```

`cancelPDFImport` cancels `state.checkTask` as well as `state.task`.

`PDFImportSheet`, in the `.found` case under the size line and above the button:

```swift
                        switch state.check {
                        case .none:
                            EmptyView()
                        case .running(let done, let of):
                            VStack(spacing: 6) {
                                Text("Checking written row \(done) of \(of)…").font(Font.Heather.caption).foregroundStyle(Color.ink2).monospacedDigit()
                                ProgressView(value: Double(done), total: Double(max(of, 1))).tint(Color.ink)
                                Button("Skip the check") { model.skipPDFCheck() }.font(Font.Heather.caption)
                            }
                        case .done(let record):
                            Text(record.sentence ?? "Written rows agree with the chart.")
                                .font(Font.Heather.caption).foregroundStyle(Color.ink2).multilineTextAlignment(.center)
                        }
```

("Written rows agree with the chart." is the sheet's own line for a clean finish; the detail screen shows nothing then, as §6.3 says.)

`PatternDetailContent`, in `specs` after the gauge line:

```swift
                if let chart, let sentence = ImportRecord(json: chart.document.ext)?.sentence {
                    Text(sentence).font(Font.Heather.caption).foregroundStyle(Color.ink2).frame(maxWidth: .infinity, alignment: .leading)
                }
```

The gauge line's condition becomes `ImportRecord(json: chart.document.ext)?.gaugePrinted == false` in place of the raw `ext` lookup.

- [ ] **Step 4: Run the tests**

Run the whole app suite (`DesignRulesTests` included). Expected: green. The check runs in its own task, so `importPDF` returns with `.found` while the check is `.running`; the tests poll for it.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: the import sheet checks the written rows under the chart it found, with Skip, and the detail screen shows the outcome (#112 PR 3)"
```

---

### Task 8: The real-fixture gate on the mini, docs, and the PR

**Files:**
- Create: `ios/Tests/PDFImportRealTests.swift`
- Modify: `ios/README.md` (the PDF section)
- Modify: `docs/superpowers/specs/2026-09-20-phone-pdf-import-design.md` (§6.3 amendment, §11 results)
- Modify: this plan (tick every box)

**Interfaces:**
- Consumes: `PDFImporter.read`, `fixtures/import/real/manifest.toml` (read by the test as text: `id`, `file`, `width`, `height`, `rows_sha256`).

- [ ] **Step 1: The skip-if-absent test**

The Python `tests/test_import_real.py` pins `sha256("\n".join(rows))` over the grid's run strings with cluster codes A, B, … by frequency: the same strings `GridChart.draft` writes, so the phone is held to the same hashes. `PDFImportRealTests.swift`:

```swift
import CryptoKit
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

/// The real pattern PDFs (`fixtures/import/real/`, gitignored, on the mini only) through the
/// phone's grid path, to the hashes `manifest.toml` pins (phone import spec §8 item 3, §11). A
/// file that is absent skips and says so, as the Python test does.
@MainActor
@Suite struct PDFImportRealTests {
    struct Entry { let id: String; let file: String; let width: Int; let height: Int; let hash: String }

    /// The fixtures with a pinned hash and a page-wide chart: cactus, Santa, and Orca's two.
    static func entries() throws -> [Entry] {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/manifest.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Entry] = []
        var fields: [String: String] = [:]
        func flush() {
            if let id = fields["id"], let file = fields["file"], let w = fields["width"].flatMap(Int.init), let h = fields["height"].flatMap(Int.init),
               let hash = fields["rows_sha256"], !hash.isEmpty, fields["prose"] == nil { out.append(Entry(id: id, file: file, width: w, height: h, hash: hash)) }
            fields = [:]
        }
        for line in text.split(separator: "\n") {
            if line.hasPrefix("[[fixture]]") { flush(); continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            fields[key] = value
        }
        flush()
        return out
    }

    @Test(arguments: try entries())
    func aRealPDFReadsToThePinnedHash(entry: Entry) async throws {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/\(entry.file)")
        guard let data = try? Data(contentsOf: url) else {
            print("SKIP real fixture \(entry.file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = PDFImporter(charts: ChartLibrary(directory: try temporaryDirectory()), local: LocalPatternStore(directory: try temporaryDirectory()),
                                   rowReader: nil, modelUnavailable: nil)
        let started = Date()
        let reading = try await importer.read(data, fileName: entry.file)
        let seconds = Date().timeIntervalSince(started)
        print("real \(entry.id): \(reading.width)x\(reading.height) in \(String(format: "%.1f", seconds)) s, \(reading.source)")
        #expect(reading.width == entry.width && reading.height == entry.height, entry.id)
        let hash = SHA256.hash(data: Data(reading.draft.rows.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        // Orca's page holds the front and the back at the same size; the phone takes the first
        // largest region, so either of the two pinned hashes is right.
        let sibling = try Self.entries().filter { $0.file == entry.file && $0.width == entry.width && $0.height == entry.height }.map(\.hash)
        #expect(sibling.contains(hash), "\(entry.id): \(hash)")
    }
}
```

`@Test(arguments: try entries())` needs `entries()` to be usable at argument time; if Swift Testing rejects the `try`, make `entries()` non-throwing (return `[]` on any error). The Orca manifest entries carry `kwargs = { page = 9, region = 1 }`; the phone has no such knobs, so the test accepts either Orca hash for either entry.

- [ ] **Step 2: Run it on the mini**

The real PDFs live in `~/repos/graphghan/fixtures/import/real/` (gitignored; copy them into this worktree's `fixtures/import/real/` first, never `git add` them: `git status` must not list them). Run the app suite filtered to `PDFImportRealTests` and note each printed line: size, seconds, and pass/fail. Expected: cactus 28×28, Santa 56×56, Orca 29×77 twice, all to their hashes, each in a few seconds on the simulator. A hash mismatch with the right size is a cluster-order or a cell-colour difference between PDFKit's and pdfium's rendering: compare `reading.draft.palette` hexes with the Python's (`uv run graphghan import <pdf> --dry-run` or the staged report) before deciding whether the port or the renderer is at fault, and record the finding in §11 either way.

- [ ] **Step 3: Docs**

`ios/README.md`, replace "one with neither chart nor rows gets "No chart or written rows were found in this PDF" until the grid reader lands (spec §8);" with:

"A PDF with a picture of the chart goes through `GridReader` in GraphghanCore, a port of the Python `rasterchart.py` held to its answers on the images under `fixtures/import/grid/` (`GridReaderTests`, `GridColoursTests`): each page is rendered by `PageRenderer` under the 40-megapixel budget (spec §5.1), the largest grid of at least 8×8 cells becomes the chart at once (`GridChart`), and the written rows, when the pages have them and the iPhone has the model, are then read as the check underneath the chart on the sheet, with Skip; "Add to library" before the check ends saves it as stopped. The outcome is `ext.graphghan.import` on the chart (spec §6.3: `check`, `rows_checked`, `rows_total`, `rows_disagree`, `problem`) and the detail screen's sentence (`ImportRecord.sentence`). The real pattern PDFs (`fixtures/import/real/`, on the mini only) read to the Python's pinned hashes in `PDFImportRealTests`, which skips a file that is absent. One with neither chart nor rows gets "No chart or written rows were found in this PDF";"

Spec §6.3: add after the table: "PR 3 (2026-09-20) added two fields: `rows_total`, the written rows the pages hold, so the stopped sentence can say "N+1–M not checked"; and `problem`, present only when the rows could not be compared at all (they do not assemble, the key pairs two chart colours with one code, or more than a tenth of the rows disagree so the orientation is wrong), holding the Python importer's sentence; the detail screen then says "Written rows could not be compared with the chart: <problem>"."

Spec §11: under the cactus bullet, record the mini's numbers from Step 2 (size, seconds, hash matched) for cactus, Santa and Orca, dated; under the Orca bullet, note the grid half is measured and the rows half still waits for a device.

- [ ] **Step 4: Check, Blink, push, PR**

Run in order, all green before the push: `mise run check`; `cd ios/Packages/GraphghanCore && swift test`; `cd ios/Packages/ProseReader && swift test`; the whole app suite. `git status` must show no file under `fixtures/import/real/`. Then `PATH="$HOME/.local/share/mise/shims:$PATH" blink review` (this branch's diff holds the five fixture PNGs, which Blink refuses as binary: if it does, cut a scratch branch from `main`, `git diff main...HEAD -- . ':(exclude)*.png' | git apply`, `git add -A -- . ':(exclude)fixtures/import/real' ':(exclude)build'`, commit there and review that; delete the scratch branch after). Take every finding or answer it in the PR. Push `tylervick/phone-import-3` and open the PR against `main`: "Closes #112" in the body; the eight tasks; the deviation from §6.2 (loops, not vImage) with the measured page times; the amendments to §6.3; the real-fixture results from §11; what stays out (#151's box rows, #166's key names). Address CI and CodeRabbit until green; CodeRabbit's re-review is rate limited to one an hour, so a stale "changes requested" is dismissed once its findings are confirmed addressed.

---

## Self-review

- **§4.2:** grid first (Task 6), rows as the check (Task 6 `check`, Task 7), disagreement reported by row number and never applied (Task 5 `crossCheck`, `ImportRecord.sentence`), check can be skipped or stopped and the chart saved either way (Task 7).
- **§5.1 step 2:** render budget and the skipped page (Task 6 `PageRenderer`, `readGrid`), 8×8 minimum, largest region (Task 6).
- **§5.2 "Chart found":** progress line, Skip, Cancel, Add enabled at once (Task 7).
- **§5.4:** the disagreement sentence (Task 5); the others unchanged from PR 1 and 2.
- **§6.2:** the port function for function with the constants (Tasks 2–4); the vImage deviation is stated in Global Constraints; the "same images" requirement is Task 1's fixtures plus the own-PDF page through PDFKit (Tasks 3, 5).
- **§6.3:** the record with the two amendments (Task 5, Task 8).
- **§7:** `unavailable` without the model (Task 6, Task 7).
- **§9:** `GridReaderTests` over synthetic grids and the own-PDF page (Tasks 3–5), `RowsChartTests` cross-check over Craigh's rows and a wrong row (Task 5), app tests for the path, states and sentences (Tasks 6–7), the real fixtures by hand on the mini (Task 8).
- **Types:** `Region` (Task 3) is what `GridChart.draft` (Task 5) and `readGrid` (Task 6) take; `ImportRecord` (Task 5) is what `check`/`save` (Task 6) and `CheckStage.done` (Task 7) carry; `CheckOutcome` (Task 5) is consumed only inside `check` (Task 6); `PDFImportProgress.checking` (Task 6) drives `CheckStage.running` (Task 7).
