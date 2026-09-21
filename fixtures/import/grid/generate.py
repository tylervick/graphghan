"""Draw the synthetic charts tests/test_rasterchart.py draws and record what the Python grid
reader answers, so the Swift port (GraphghanCore GridReader) is held to the same answers. The
photo case (noise under a fence of lines) is not here: random noise does not compress, so the Swift
test draws its own.

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
            d.rectangle(
                [ox + x * cell, oy + y * cell, ox + (x + 1) * cell, oy + (y + 1) * cell], fill=RGB[a[y, x]]
            )
            if symbols and (x + y) % 3 == 0:
                cx, cy = ox + (x + 0.5) * cell, oy + (y + 0.5) * cell
                d.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], outline=(0, 0, 0), width=2)
    for x in range(w + 1):
        bold = (w - x) % bold_every == 0
        d.line(
            [(ox + x * cell, oy), (ox + x * cell, oy + h * cell)],
            fill=(0, 0, 0) if bold else line,
            width=3 if bold else 1,
        )
    for y in range(h + 1):
        bold = (h - y) % bold_every == 0
        d.line(
            [(ox, oy + y * cell), (ox + w * cell, oy + y * cell)],
            fill=(0, 0, 0) if bold else line,
            width=3 if bold else 1,
        )
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
        d.text(
            (40, 20 + i * 19),
            "Row %d: ch 1, turn, 8 A, 14 B, 8 A (30 sts) and more words here" % i,
            fill=(0, 0, 0),
        )
    return img


def answer(img: Image.Image, want_cells: bool) -> dict:
    regions = rc.find_regions(img)
    out = {
        "regions": [
            {
                "cols": r.cols,
                "rows": r.rows,
                "pitch": [round(r.pitch[0], 3), round(r.pitch[1], 3)],
                "bbox": list(r.bbox),
                "noise": round(r.noise, 3),
            }
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
    }


def main() -> None:
    for name, (img, want_cells) in images().items():
        img.save(OUT / f"{name}.png", optimize=True)
        (OUT / f"{name}.json").write_text(
            json.dumps(answer(img, want_cells), indent=1) + "\n", encoding="utf-8"
        )
        print(f"wrote {name}: {img.width}x{img.height}")


if __name__ == "__main__":
    main()
