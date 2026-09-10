from __future__ import annotations

import numpy as np

from .. import grid as gr

SETT_DEFAULT = [("G", 1.5), ("B", 0.75), ("Y", 0.5), ("B", 0.75), ("G", 1.5), ("R", 1.0)]


def sett_cells(sett, density, min_cells=2):
    return [(code, max(min_cells, int(round(inches * density)))) for code, inches in sett]


def stripe_lookup(length, density, phase, sett, colors):
    seq = []
    for code, n in sett_cells(sett, density):
        seq += [colors[code]] * n
    seq = np.array(seq, dtype=np.uint8)
    idx = np.arange(length)
    mirrored = np.minimum(idx, length - 1 - idx)
    return seq[(mirrored + phase) % len(seq)]


def plaid(w, h, phase_x, phase_y, colors, sett=SETT_DEFAULT, priority=("Y", "R", "B", "G")):
    """Crochet-friendly plaid: mirrored setts on both axes; each cell takes the higher-priority
    of its column stripe and row stripe. No stripe is narrower than 2 cells."""
    rank = {colors[code]: len(priority) - i for i, code in enumerate(priority)}
    sx = stripe_lookup(w, gr.ST_PER_IN, phase_x, sett, colors)[None, :]
    sy = stripe_lookup(h, gr.ROWS_PER_IN, phase_y, sett, colors)[:, None]
    px = np.vectorize(rank.get)(sx)
    py = np.vectorize(rank.get)(sy)
    return np.where(px >= py, sx, sy).astype(np.uint8)
