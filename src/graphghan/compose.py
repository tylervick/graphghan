"""Composition helpers shared by pattern designs."""
from __future__ import annotations

from .text import text_line


def text_block(g, lines, x_center, y_top, size, pitch, font_path, color, bg, bold=0.035, threshold=0.42):
    """Blit `lines` centred on x_center, one every `pitch` rows, each `size` rows tall.
    Returns one (x0, y0, x1, y1) box per line."""
    boxes = []
    for i, t in enumerate(lines):
        arr, _asc, _desc = text_line(t, size, color, bg, font_path, threshold=threshold, bold=bold)
        h, w = arr.shape
        x0 = int(round(x_center - w / 2.0))
        y0 = y_top + i * pitch
        g.blit(arr, x0, y0, transparent=bg)
        boxes.append((x0, y0, x0 + w, y0 + h))
    return boxes
