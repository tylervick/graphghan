"""Lettering: render a TTF line so that its full line height spans N rows, with glyph widths
corrected for the cell aspect, at any gauge and any font."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import grid as gr
from .pattern import find_repo_root

FONT_METAMORPHOUS = find_repo_root(Path(__file__)) / "fonts" / "Metamorphous-Regular.ttf"


def text_line(text: str, size_rows: int, color: int, bg: int, font_path: str | Path,
              threshold: float = 0.5, bold: float = 0.0):
    """Returns (array, ascent_rows, descent_rows). Rendered at 8x and box-filtered down;
    `bold` is a stroke width as a fraction of the row size; `threshold` is the ink cutoff (0..1)."""
    big = ImageFont.truetype(str(font_path), size_rows * 8)
    asc_px, desc_px = big.getmetrics()
    line_px = asc_px + desc_px
    ascent = int(round(asc_px * size_rows / line_px))
    img = Image.new("L", (size_rows * 8 * max(1, len(text)) * 2 + 40, line_px), 0)
    ImageDraw.Draw(img).text((20, 0), text, font=big, fill=255,
                             stroke_width=int(round(bold * size_rows * 8)), stroke_fill=255)
    a = np.array(img)
    xs = np.where(a.max(axis=0) > 0)[0]
    if xs.size == 0:
        return np.full((size_rows, 1), bg, dtype=np.uint8), ascent, size_rows - ascent
    img = img.crop((int(xs.min()), 0, int(xs.max()) + 1, line_px))
    scale = size_rows * gr.SH / line_px                   # inches per source pixel
    cols_out = max(1, int(round(img.width * scale / gr.SW)))
    small = img.resize((cols_out, size_rows), Image.BOX)
    m = np.array(small) >= int(255 * threshold)
    arr = np.full(m.shape, bg, dtype=np.uint8)
    arr[m] = color
    return arr, ascent, size_rows - ascent
