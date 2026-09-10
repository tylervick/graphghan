from __future__ import annotations

import numpy as np

from .. import grid as gr
from ..grid import ellipse_fill, stadium_ring


def dragonfly(w, h, bg, body, wing_fill, wing_line, span=7.0, cx=None, cy=None):
    """Dragonfly facing up, wingspan ~`span` inches. Wings are outlined ellipses with a fill.
    Returns a local array over a w x h canvas pre-filled with bg."""
    cx = (w - 1) / 2.0 if cx is None else cx
    cy = (h - 1) / 2.0 if cy is None else cy
    s = span / 7.0
    arr = np.full((h, w), bg, dtype=np.uint8)
    # wings: (offset x, offset y, a, b, angle)
    wings = [
        (1.95, -0.55, 2.55, 0.80, -28),
        (-1.95, -0.55, 2.55, 0.80, 28),
        (1.65, 0.70, 2.15, 0.70, 22),
        (-1.65, 0.70, 2.15, 0.70, -22),
    ]
    line = 0.42 * s
    for ox, oy, a, b, ang in wings:
        wx = cx + ox * s / gr.SW
        wy = cy + oy * s / gr.SH
        outer = ellipse_fill(w, h, wx, wy, a * s, b * s, ang)
        inner = ellipse_fill(w, h, wx, wy, a * s - line, b * s - line, ang)
        arr[outer] = wing_line
        arr[inner] = wing_fill
    # body: vertical stadium, head circle, tail with segment gaps
    body_m = stadium_ring(w, h, cx, cy + 0.9 * s / gr.SH, 2.3 * s, 0.0, 0.30 * s, vertical=True)
    arr[body_m] = body
    head = ellipse_fill(w, h, cx, cy - 1.75 * s / gr.SH, 0.5 * s, 0.45 * s)
    arr[head] = body
    ys = np.arange(h)[:, None] * np.ones((1, w))
    tail_top = cy + 0.55 * s / gr.SH
    seg = ((ys - tail_top) >= 0) & (((ys - tail_top) % 4) == 3)
    arr[body_m & seg] = bg
    return arr


def amber_drop(w, h, bg, fill, line, a=4.3, b=4.9, edge=0.42):
    """Egg-shaped amber blob with an outline, centered in a w x h canvas."""
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    arr = np.full((h, w), bg, dtype=np.uint8)
    arr[ellipse_fill(w, h, cx, cy, a, b)] = line
    arr[ellipse_fill(w, h, cx, cy, a - edge, b - edge)] = fill
    return arr
