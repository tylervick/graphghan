from __future__ import annotations

import numpy as np


def stripe_band(length, thick, seq, horizontal=True):
    """Stripes across a band; `seq` is [(color, cells), ...] repeated to fill `thick`."""
    across = []
    for c, n in seq:
        across += [c] * n
    across = (across * (thick // len(across) + 1))[:thick]
    col = np.array(across, dtype=np.uint8)
    arr = np.repeat(col[:, None], length, axis=1)
    return arr if horizontal else arr.T.copy()
