from __future__ import annotations

import numpy as np

from .. import grid as gr
from ..grid import circle_ring, weave


def rings(bg, fg, r_in=1.1, r_out=1.75, gap_in=1.9):
    w = gr.cols(2 * r_out + gap_in) + 3
    h = gr.rows(2 * r_out) + 2
    cy = (h - 1) / 2.0
    c1 = (w - 1) / 2.0 - gr.cols(gap_in) / 2.0
    c2 = (w - 1) / 2.0 + gr.cols(gap_in) / 2.0
    ra = circle_ring(w, h, c1, cy, r_in, r_out)
    rb = circle_ring(w, h, c2, cy, r_in, r_out)
    ys, _ = np.mgrid[0:h, 0:w]
    windows = [(ys < cy, True), (ys >= cy, False)]   # left ring over at top, right ring over at bottom
    ra, rb, found = weave(ra, rb, windows)
    arr = np.full((h, w), bg, dtype=np.uint8)
    arr[ra | rb] = fg
    return arr, found
