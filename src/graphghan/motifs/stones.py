from __future__ import annotations

import numpy as np

from .. import grid as gr
from ..grid import ellipse_fill


def standing_stones(w, h, bg, hill, stone, moon):
    """Ring of standing stones on a hill under a full moon. Local array w x h."""
    arr = np.full((h, w), bg, dtype=np.uint8)
    cx = (w - 1) / 2.0
    hill_top = h - 1 - gr.rows(3.4)
    # moon: to the right of the stone ring, as high as the scene allows (never behind a stone)
    r = 1.9
    moon_cy = max(r / gr.SH + gr.rows(0.3), hill_top - 4.0 / gr.SH)
    arr[ellipse_fill(w, h, cx + 9.6 / gr.SW, moon_cy, r, r)] = moon
    # hill: wide ellipse arc; fill everything under it
    hm = ellipse_fill(w, h, cx, h - 1 + gr.rows(6.0), w * gr.SW * 0.62, 9.4)
    ys = np.arange(h)[:, None] * np.ones((1, w), dtype=int)
    arr[hm & (ys >= hill_top - gr.rows(1.0))] = hill
    # stones: (x offset in, width in, height in, lean) standing on the hill line
    stones = [
        (-6.6, 1.1, 3.6, 0),
        (-3.9, 1.3, 4.6, 0),
        (-1.2, 1.0, 3.2, 0),
        (1.5, 1.4, 5.0, 0),
        (4.4, 1.1, 3.9, 0),
        (6.9, 1.0, 3.0, 0),
    ]
    for ox, sw_in, sh_in, _ in stones:
        x0 = int(round(cx + ox / gr.SW - sw_in / gr.SW / 2))
        x1 = x0 + max(3, gr.cols(sw_in))
        # ground level follows the hill: find first hill row in this column band
        col = hm[:, (x0 + x1) // 2] & (ys[:, 0] >= hill_top - gr.rows(1.0))
        ground = int(np.argmax(col)) if col.any() else hill_top
        y1 = ground + gr.rows(0.5)
        y0 = y1 - gr.rows(sh_in)
        arr[y0:y1, x0:x1] = stone
        # chamfer one top corner so they read as rough megaliths
        if ox > 0:
            arr[y0, x1 - 1] = bg
        else:
            arr[y0, x0] = bg
    return arr
