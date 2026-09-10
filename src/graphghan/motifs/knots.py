from __future__ import annotations

import numpy as np

from .. import grid as gr
from ..grid import sector_windows, segment_band, stadium_ring, weave


def solomon_knot(w, h, bg, fg, half=2.4, r_out=1.05, stroke=0.6):
    """Two interlaced stadium (oval) rings, one horizontal, one vertical: a Solomon's knot."""
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    hz = stadium_ring(w, h, cx, cy, half - r_out, r_out - stroke, r_out)
    vt = stadium_ring(w, h, cx, cy, half - r_out, r_out - stroke, r_out, vertical=True)
    windows = sector_windows(w, h, cx, cy, 4, start_deg=0.0, a_first=True)
    hz, vt, found = weave(hz, vt, windows)
    arr = np.full((h, w), bg, dtype=np.uint8)
    arr[hz | vt] = fg
    return arr, found


def corner_block(w, h, bg, fg, outline=2):
    arr = np.full((h, w), fg, dtype=np.uint8)
    inner, n = solomon_knot(w - 2 * outline, h - 2 * outline, bg, fg)
    arr[outline:h - outline, outline:w - outline] = inner
    return arr, n


def woven_x_block(w, h, bg, fg, outline=2, bar_in=0.6):
    """Corner block: fg outline, bg field, a fg X (saltire) with a woven centre."""
    arr = np.full((h, w), fg, dtype=np.uint8)
    iw, ih = w - 2 * outline, h - 2 * outline
    inner = np.full((ih, iw), bg, dtype=np.uint8)
    pad = 0.35 / gr.SW, 0.35 / gr.SH
    d1 = segment_band(iw, ih, (pad[0], pad[1]), (iw - 1 - pad[0], ih - 1 - pad[1]), bar_in / 2)
    d2 = segment_band(iw, ih, (iw - 1 - pad[0], pad[1]), (pad[0], ih - 1 - pad[1]), bar_in / 2)
    d1, d2, _ = weave(d1, d2, [(np.ones_like(d1), True)])
    inner[d1 | d2] = fg
    arr[outline:h - outline, outline:w - outline] = inner
    return arr
