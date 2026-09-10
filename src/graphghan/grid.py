"""Stitch grid plus mask helpers. Cells are (row, col); shapes are defined in inches."""

import numpy as np

# gauge: stitches per inch, rows per inch (worsted + 5 mm defaults)
GAUGES: dict[str, tuple[float, float]] = {"sc": (3.5, 4.0), "hdc": (3.25, 2.5), "dc": (3.0, 1.625)}
ST_PER_IN = 3.5
ROWS_PER_IN = 4.0
SW = 1.0 / ST_PER_IN  # inches per column
SH = 1.0 / ROWS_PER_IN  # inches per row


def register_gauge(name: str, st_per_in: float, rows_per_in: float) -> None:
    GAUGES[name] = (float(st_per_in), float(rows_per_in))


def set_gauge(gauge) -> None:
    """Switch the working gauge by name or (st_per_in, rows_per_in). Every cols()/rows()/mask call reads it."""
    global ST_PER_IN, ROWS_PER_IN, SW, SH
    ST_PER_IN, ROWS_PER_IN = GAUGES[gauge] if isinstance(gauge, str) else (float(gauge[0]), float(gauge[1]))
    SW, SH = 1.0 / ST_PER_IN, 1.0 / ROWS_PER_IN


def current_gauge() -> tuple[float, float]:
    return ST_PER_IN, ROWS_PER_IN


def cols(inches):
    return int(round(inches * ST_PER_IN))


def rows(inches):
    return int(round(inches * ROWS_PER_IN))


class Grid:
    def __init__(self, w, h, fill=0):
        self.w, self.h = w, h
        self.a = np.full((h, w), fill, dtype=np.uint8)

    def rect(self, x0, y0, x1, y1, c):
        """Half-open [x0,x1) x [y0,y1)."""
        self.a[y0:y1, x0:x1] = c

    def blit(self, arr, x0, y0, transparent=None):
        h, w = arr.shape
        sub = self.a[y0 : y0 + h, x0 : x0 + w]
        src = arr[: sub.shape[0], : sub.shape[1]]
        if transparent is None:
            sub[:] = src
        else:
            m = src != transparent
            sub[m] = src[m]


# ---------- masks in inch space (local arrays) ----------


def inch_coords(w, h, cx, cy):
    """(dx, dy) in inches from center (cx, cy) [cell units] for every cell of a w x h array."""
    ys, xs = np.mgrid[0:h, 0:w]
    return (xs - cx) * SW, (ys - cy) * SH


def ellipse_ring(w, h, cx, cy, a_in, b_in, a_out, b_out):
    """Ring between two concentric ellipses with semi-axes (a,b) in inches."""
    dx, dy = inch_coords(w, h, cx, cy)
    d_out = (dx / a_out) ** 2 + (dy / b_out) ** 2
    d_in = (dx / a_in) ** 2 + (dy / b_in) ** 2
    return (d_out <= 1.0) & (d_in > 1.0)


def circle_ring(w, h, cx, cy, r_in, r_out):
    return ellipse_ring(w, h, cx, cy, r_in, r_in, r_out, r_out)


def square_ring(w, h, cx, cy, r_in, r_out):
    dx, dy = inch_coords(w, h, cx, cy)
    d = np.maximum(np.abs(dx), np.abs(dy))
    return (d >= r_in) & (d < r_out)


def diamond_ring(w, h, cx, cy, r_in, r_out):
    dx, dy = inch_coords(w, h, cx, cy)
    d = np.abs(dx) + np.abs(dy)
    return (d >= r_in) & (d < r_out)


# ---------- morphology ----------


def dilate(m):
    h, w = m.shape
    p = np.pad(m, 1)
    out = np.zeros_like(m)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            out |= p[dy : dy + h, dx : dx + w]
    return out


def weave(mask_a, mask_b, windows):
    """Weave two strand masks. `windows` is a list of (window_mask, a_over). Inside each window
    the under strand loses every cell touching (8-neighborhood) the over strand, which draws the
    classic over/under gap. Returns (a, b, crossings_found)."""
    a = mask_a.copy()
    b = mask_b.copy()
    found = 0
    for win, a_over in windows:
        over_src, under = (mask_a, b) if a_over else (mask_b, a)
        if (mask_a & mask_b & win).any():
            found += 1
        halo = dilate(over_src & win) & ~over_src & win
        under[halo] = False
    return a, b, found


def sector_windows(w, h, cx, cy, n, start_deg=0.0, a_first=True):
    """n equal angular sectors around (cx, cy), alternating which strand is over."""
    ys, xs = np.mgrid[0:h, 0:w]
    ang = (np.degrees(np.arctan2(ys - cy, xs - cx)) - start_deg) % 360.0
    step = 360.0 / n
    return [((ang >= k * step) & (ang < (k + 1) * step), (k % 2 == 0) == a_first) for k in range(n)]


def curve_mask(w, h, pts, radius):
    """Cells whose center lies within `radius` (cell units) of the polyline `pts` [(x,y),...]."""
    ys, xs = np.mgrid[0:h, 0:w]
    cx = xs.ravel().astype(float)
    cy = ys.ravel().astype(float)
    best = np.full(cx.shape, np.inf)
    pts = np.asarray(pts, dtype=float)
    for i in range(0, len(pts), 256):
        chunk = pts[i : i + 256]
        d = np.hypot(cx[:, None] - chunk[None, :, 0], cy[:, None] - chunk[None, :, 1])
        best = np.minimum(best, d.min(axis=1))
    return (best <= radius).reshape(h, w)


def stadium_ring(w, h, cx, cy, half_len, r_in, r_out, vertical=False):
    """Ring around a line segment of half-length `half_len` (inches) centered at (cx,cy) [cells]."""
    dx, dy = inch_coords(w, h, cx, cy)
    if vertical:
        dx, dy = dy, dx
    t = np.clip(dx, -half_len, half_len)
    d = np.hypot(dx - t, dy)
    return (d >= r_in) & (d < r_out)


def ellipse_fill(w, h, cx, cy, a, b, theta_deg=0.0):
    """Filled ellipse (semi-axes a,b in inches) rotated theta about center (cx,cy) [cells]."""
    dx, dy = inch_coords(w, h, cx, cy)
    t = np.radians(theta_deg)
    u = dx * np.cos(t) + dy * np.sin(t)
    v = -dx * np.sin(t) + dy * np.cos(t)
    return (u / a) ** 2 + (v / b) ** 2 <= 1.0


def curve_mask_in(w, h, pts, radius_in, sx, sy):
    """Cells whose center lies within `radius_in` INCHES of the polyline `pts` [(x,y) in cells],
    with sx / sy inches per cell along x / y. Physically round strands at any gauge."""
    ys, xs = np.mgrid[0:h, 0:w]
    cx = xs.ravel().astype(float) * sx
    cy = ys.ravel().astype(float) * sy
    pts = np.asarray(pts, dtype=float) * np.array([sx, sy])
    best = np.full(cx.shape, np.inf)
    for i in range(0, len(pts), 256):
        chunk = pts[i : i + 256]
        d = np.hypot(cx[:, None] - chunk[None, :, 0], cy[:, None] - chunk[None, :, 1])
        best = np.minimum(best, d.min(axis=1))
    return (best <= radius_in).reshape(h, w)


def segment_band(w, h, p0, p1, half_width_in):
    """Cells within half_width_in inches of the segment p0-p1 (given in cell coordinates)."""
    ys, xs = np.mgrid[0:h, 0:w]
    px, py = xs * SW, ys * SH
    x0, y0 = p0[0] * SW, p0[1] * SH
    x1, y1 = p1[0] * SW, p1[1] * SH
    vx, vy = x1 - x0, y1 - y0
    t = np.clip(((px - x0) * vx + (py - y0) * vy) / (vx * vx + vy * vy), 0, 1)
    return np.hypot(px - (x0 + t * vx), py - (y0 + t * vy)) <= half_width_in
