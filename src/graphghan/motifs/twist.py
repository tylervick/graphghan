from __future__ import annotations

import numpy as np

from .. import grid as gr
from ..grid import curve_mask_in, weave


def twist_strip_in(
    length, thick, horizontal=True, period_in=4.0, amp_in=1.0, radius_in=0.3, bg=0, fg=1, fit=True
):
    """Two sine strands inside a strip, all geometry in inches so top/bottom and side strips are
    physically identical. Local frame: strands run along x over `length` cells, strip is `thick`
    cells across; transposed at the end for vertical strips. If fit, the period is nudged so a
    crossing lands exactly at both ends (clean entry into the corner blocks)."""
    along_in, across_in = (gr.SW, gr.SH) if horizontal else (gr.SH, gr.SW)
    length_in = length * along_in  # full strip, corner edge to corner edge
    u0 = -0.5  # the corner edge, in cell units
    if fit:
        k = max(1, int(round(length_in / (period_in / 2.0))))  # number of half periods
        if k % 2 == 0:  # odd count: the over/under sequence mirrors end to end
            k += 1 if (k + 1) * period_in / 2.0 - length_in < length_in - (k - 1) * period_in / 2.0 else -1
        period_in = 2.0 * length_in / k
    mid = (thick - 1) / 2.0
    amp = max(2, int(round(amp_in / across_in)))  # whole cells: extremes land between two cells on every side
    u = np.arange(-1.0, length + 1.0, 0.05)
    phase = 2 * np.pi * ((u - u0) * along_in) / period_in
    va = mid + amp * np.sin(phase)
    vb = mid - amp * np.sin(phase)
    a = curve_mask_in(length, thick, list(zip(u, va, strict=True)), radius_in, along_in, across_in)
    b = curve_mask_in(length, thick, list(zip(u, vb, strict=True)), radius_in, along_in, across_in)
    _, xs = np.mgrid[0:thick, 0:length]
    windows = []
    half = period_in / 2.0 / along_in  # cells between crossings
    n = int(np.floor(length / half)) + 1
    for k in range(-1, n + 2):
        u_k = u0 + k * half
        win = np.abs(xs - u_k) < half / 2.0
        windows.append((win, k % 2 == 0))
    a, b, found = weave(a, b, windows)
    arr = np.full((thick, length), bg, dtype=np.uint8)
    arr[a | b] = fg
    if not horizontal:
        arr = arr.T.copy()
    return arr, period_in
