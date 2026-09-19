"""Read a colour grid off a picture of a chart: find the grid lines, sample the cells, cluster the
colours (spec §5.2 of docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md).

Pure numpy and Pillow; knows nothing about PDFs. A line is found by its *edges* over a long
straight run, never by its darkness, because a chart full of black cells drowns any dark-pixel
projection (spec §2.3). Every periodic region on the image is returned; the caller chooses.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from PIL import Image

EDGE_THRESHOLD = 24  # grey-level step that counts as an edge
BRIDGE = 3  # closing radius: gaps up to twice this (a bold crossing line) inside an edge run vanish
MERGE_PX = 4  # candidate columns this close are one line (both edges of a bold line)
MIN_LINE_PX = 40  # a line shorter than this is text, not a grid
MIN_LINES = 5  # lines per axis for a region (four cells)
GAP_TOLERANCE = 0.25  # consecutive line gaps within this fraction of the median are one grid
CENTRE_FRACTION = 0.4  # the part of each cell that is sampled
MAX_NOISE = 12.0  # mean grey-level spread inside cell centres above which a region is a photo
MAX_SILENT = 40  # lines that may hide inside same-coloured cells before the grid is taken to end
MAX_PIXELS = 40_000_000  # the reader holds several int16 copies of the image; a PDF page at 4x is 8 MP
COLOR_NAMES = {
    "white": (255, 255, 255),
    "cream": (245, 235, 210),
    "black": (0, 0, 0),
    "charcoal": (50, 50, 55),
    "grey": (140, 140, 140),
    "silver": (200, 200, 200),
    "red": (200, 30, 30),
    "orange": (240, 130, 30),
    "yellow": (240, 210, 40),
    "gold": (215, 165, 30),
    "green": (40, 140, 60),
    "dark green": (25, 80, 50),
    "teal": (30, 140, 140),
    "blue": (40, 90, 200),
    "navy": (25, 40, 90),
    "purple": (110, 50, 140),
    "pink": (240, 170, 200),
    "brown": (120, 80, 50),
    "tan": (200, 170, 130),
    "sage": (120, 160, 140),
    "olive": (110, 120, 50),
    "mint": (170, 230, 200),
    "aqua": (160, 220, 225),
    "sky": (140, 190, 240),
    "lavender": (190, 170, 220),
    "maroon": (110, 30, 40),
    "beige": (225, 210, 180),
}


@dataclass
class Region:
    """One grid found on an image. `xs`/`ys` are the fitted line positions in pixels; `noise` is
    the mean colour spread inside the sampled cell centres (a chart's cells are flat, a photo's
    are not)."""

    xs: list[float]
    ys: list[float]
    noise: float = 0.0
    warnings: list[str] = field(default_factory=list)

    @property
    def cols(self) -> int:
        return len(self.xs) - 1

    @property
    def rows(self) -> int:
        return len(self.ys) - 1

    @property
    def bbox(self) -> tuple[int, int, int, int]:
        return int(self.xs[0]), int(self.ys[0]), int(self.xs[-1]), int(self.ys[-1])

    @property
    def pitch(self) -> tuple[float, float]:
        return (self.xs[-1] - self.xs[0]) / self.cols, (self.ys[-1] - self.ys[0]) / self.rows

    @property
    def cells(self) -> int:
        return self.cols * self.rows

    def describe(self) -> str:
        x0, y0, x1, y1 = self.bbox
        px, py = self.pitch
        return (
            f"{self.cols}x{self.rows} cells at ({x0}, {y0})-({x1}, {y1}), "
            f"pitch {px:.1f}x{py:.1f} px, noise {self.noise:.1f}"
        )


# ---------- line finding ----------


def _shift(a: np.ndarray, s: int) -> np.ndarray:
    out = np.zeros_like(a)
    if s > 0:
        out[s:] = a[:-s]
    else:
        out[:s] = a[-s:]
    return out


def _close(mask: np.ndarray, bridge: int = BRIDGE) -> np.ndarray:
    """Binary closing down axis 0 with radius `bridge`: gaps up to twice it inside a run vanish."""
    d = mask.copy()
    for s in range(1, bridge + 1):
        d |= _shift(mask, s) | _shift(mask, -s)
    e = d.copy()
    for s in range(1, bridge + 1):
        e &= _shift(d, s) | ~_shift(np.ones_like(d), s)
        e &= _shift(d, -s) | ~_shift(np.ones_like(d), -s)
    return e & (d | mask)


def _longest_runs(mask: np.ndarray, bridge: int = BRIDGE) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Per column of a boolean (n, m) mask: the longest run of True down that column (short gaps
    bridged), and where it starts and ends."""
    closed = _close(mask, bridge)
    n, m = closed.shape
    padded = np.zeros((n + 2, m), dtype=np.int8)
    padded[1:-1] = closed
    d = np.diff(padded, axis=0)
    best = np.zeros(m, dtype=int)
    start = np.zeros(m, dtype=int)
    end = np.zeros(m, dtype=int)
    for x in range(m):
        starts = np.flatnonzero(d[:, x] == 1)
        if len(starts) == 0:
            continue
        ends = np.flatnonzero(d[:, x] == -1)
        lengths = ends - starts
        k = int(lengths.argmax())
        best[x], start[x], end[x] = lengths[k], starts[k], ends[k] - 1
    return best, start, end


def _runs(mask: np.ndarray, min_px: int) -> tuple[np.ndarray, list[list[tuple[int, int]]]]:
    """Per column of a boolean (n, m) mask: the longest run of True (short gaps bridged) and every
    run at least `min_px` long, so a line shared by two grids keeps both of its segments."""
    closed = _close(mask)
    n, m = closed.shape
    padded = np.zeros((n + 2, m), dtype=np.int8)
    padded[1:-1] = closed
    d = np.diff(padded, axis=0)
    best = np.zeros(m, dtype=int)
    segments: list[list[tuple[int, int]]] = [[] for _ in range(m)]
    for x in range(m):
        starts = np.flatnonzero(d[:, x] == 1)
        if len(starts) == 0:
            continue
        ends = np.flatnonzero(d[:, x] == -1)
        lengths = ends - starts
        best[x] = int(lengths.max())
        segments[x] = [
            (int(s), int(e) - 1) for s, e, ln in zip(starts, ends, lengths, strict=True) if ln >= min_px
        ]
    return best, segments


Line = tuple[float, list[tuple[int, int]]]  # centre position, segments on the other axis


def _lines(mask: np.ndarray, min_px: int) -> list[Line]:
    """Candidate columns (long edge runs) merged within MERGE_PX of each other into lines."""
    best, segments = _runs(mask, min_px)
    if best.max() < min_px:
        return []
    keep = np.flatnonzero(best >= max(min_px, best.max() * 0.25))
    out: list[Line] = []
    group = [int(keep[0])]
    for x in keep[1:]:
        if x - group[-1] <= MERGE_PX:
            group.append(int(x))
        else:
            out.append(_merge(group, best, segments))
            group = [int(x)]
    out.append(_merge(group, best, segments))
    return out


def _merge(group: list[int], best, segments) -> Line:
    weights = best[group].astype(float)
    centre = float(np.average(np.array(group, dtype=float), weights=weights))
    return centre, [seg for x in group for seg in segments[x]]


def _clusters(lines: list[Line]) -> list[list[Line]]:
    """Split a sorted line list where the gap jumps: separate grids, or a grid and a page rule."""
    if len(lines) < 2:
        return [lines] if lines else []
    gaps = np.diff([c for c, _ in lines])
    limit = 3 * float(np.median(gaps))
    groups, current = [], [lines[0]]
    for line, gap in zip(lines[1:], gaps, strict=True):
        if gap > limit:
            groups.append(current)
            current = [line]
        else:
            current.append(line)
    groups.append(current)
    return groups


def _pitch(positions: list[float]) -> float | None:
    """The cell pitch of a line cluster: the median gap, after dropping gaps that are multiples of
    it (a thin line lost between two bold ones) or fractions (both edges of one thick line)."""
    if len(positions) < 3:
        return None
    gaps = np.diff(positions)
    pitch = float(np.median(gaps))
    if pitch <= 0:
        return None
    unit = gaps[(gaps > 0.6 * pitch) & (gaps < 1.4 * pitch)]
    # The mean, not the median: lines land on whole pixels, so an 11.3 px pitch reads as gaps of
    # 11, 11, 12 and the median would drift a third of a pixel per line.
    return float(np.mean(unit)) if len(unit) else pitch


def _window_max(mask: np.ndarray, r: int) -> np.ndarray:
    """Along axis 1: True where any pixel within r columns is True."""
    out = mask.copy()
    for s in range(1, r + 1):
        out[:, s:] |= mask[:, :-s]
        out[:, :-s] |= mask[:, s:]
    return out


def _refine_axis(edges: np.ndarray, seeds: list[float], pitch: float, band_noise) -> list[float] | None:
    """Fit the line positions along axis 1 of `edges` (a (span, n) edge mask limited to the other
    axis's extent): snap each seed to the nearest edge-density peak, keep the lattice most seeds
    agree on, walk outward one pitch at a time while a thin line is there and the cells it adds
    are flat colour (`band_noise(a, b)` is the (mean, median) colour spread of the strip a..b), then lay every
    interior line on the fitted pitch."""
    span, n = edges.shape
    wide = _window_max(edges, 2)
    density = wide.mean(axis=0)
    raw = edges.mean(axis=0)  # unwidened: how wide a line really is
    # A run may bridge a crossing line (about a tenth of a cell) but not the gap between two
    # stacked digits, which at a tiny pitch is about as long: bridge less when cells are small.
    longest = _longest_runs(wide, bridge=max(1, min(BRIDGE, int(pitch / 12))))[0]
    r_seed = max(2, int(pitch / 4))
    r_next = max(2, int(pitch / 8))

    def peak(at: float, r: int) -> int | None:
        """The centre of the densest plateau within r of `at` (argmax alone leans to its left edge)."""
        lo, hi = int(max(0, at - r)), int(min(n, at + r + 1))
        if hi <= lo:
            return None
        window = density[lo:hi]
        top = np.flatnonzero(window >= window.max() - 1e-9)
        return lo + int(round(float(top.mean())))

    def thin(x: int) -> bool:
        """A grid line is a narrow density peak; text is dense for a whole glyph height."""
        lo, hi = max(0, x - 2), min(n, x + 3)
        top = lo + int(raw[lo:hi].argmax())
        half = 0.5 * raw[top]
        if half <= 0:
            return False
        lo = top
        while lo > 0 and raw[lo - 1] >= half:
            lo -= 1
        hi = top
        while hi < n - 1 and raw[hi + 1] >= half:
            hi += 1
        return hi - lo + 1 <= max(6, 0.3 * pitch)

    found = sorted({p for p in (peak(x, r_seed) for x in seeds) if p is not None and thin(p)})
    if len(found) < 2:
        return None

    def on_lattice(x: int, anchor: int) -> bool:
        k = (x - anchor) / pitch
        return abs(k - round(k)) <= 0.25

    anchor = max(found, key=lambda a: sum(on_lattice(x, a) for x in found))
    base = float(np.median(density[[x for x in found if on_lattice(x, anchor)]]))
    if base <= 0:
        return None

    def present(x: int) -> bool:
        return density[x] >= 0.3 * base and longest[x] >= 1.5 * pitch and thin(x)

    def walk(direction: int) -> list[tuple[int, int]]:
        """From the anchor outward, one lattice step at a time: a position joins when a line is
        there; positions with no line but flat cells (a run of same-coloured cells hides the line)
        are carried until a line reappears; text, numbers or a photo in the cells ends the grid.
        Returns (position, lattice index) pairs; the pitch is re-estimated from what is committed,
        so a long grid does not drift off a first estimate that was a third of a pixel out."""
        committed, pending, last, k, step = [(anchor, 0)], [], float(anchor), 0, pitch
        while True:
            k += direction
            expected = last + direction * step
            p = peak(expected, r_next)
            if p is None or p <= 0 or p >= n - 1:
                break
            if present(p):  # a visible line: the cells may carry a watermark or symbols
                committed += pending + [(p, k)]
                pending, last = [], float(p)
                (x0, k0), (x1, k1) = committed[0], committed[-1]
                if abs(k1 - k0) >= 3:
                    step = abs((x1 - x0) / (k1 - k0))
            else:  # no line: only flat cells (the line hidden in one colour) may carry on
                lo, hi = (last, p) if direction > 0 else (p, last)
                if band_noise(lo, hi)[0] > MAX_NOISE:
                    break
                pending.append((int(round(expected)), k))
                last = expected
                if len(pending) > MAX_SILENT:
                    break
        return committed

    pairs = sorted(set(walk(-1) + walk(1)))
    found = [x for x, _ in pairs]
    ks = np.array([k for _, k in pairs]) - pairs[0][1]
    if len(set(ks.tolist())) < 2:
        return None
    slope, intercept = np.polyfit(ks, np.array(found, dtype=float), 1)
    count = int(ks[-1])
    if count < MIN_LINES - 1:
        return None
    return [float(intercept + slope * k) for k in range(count + 1)]


def _band_noise(band: np.ndarray, pitch: float) -> tuple[float, float]:
    """Grey spread of the cell centres in a one-cell-thick strip, as (mean, median) over the cells:
    `band` is (thickness, length) and cells lie along its length at `pitch`."""
    t, length = band.shape
    c0, c1 = int(t * (0.5 - CENTRE_FRACTION / 2)), max(int(t * (0.5 + CENTRE_FRACTION / 2)), int(t * 0.5) + 1)
    core = band[c0:c1]
    n = max(1, int(length / pitch))
    spreads = []
    for k in range(n):
        a = int(k * pitch + pitch * (0.5 - CENTRE_FRACTION / 2))
        b = max(a + 1, int(k * pitch + pitch * (0.5 + CENTRE_FRACTION / 2)))
        spreads.append(core[:, a:b].std())
    if not spreads:
        return 0.0, 0.0
    return float(np.mean(spreads)), float(np.median(spreads))


def _fits(line: Line, lo: float, hi: float) -> bool:
    """A line belongs to a grid spanning lo..hi on the other axis when one of its segments covers
    at least half of that span, or lies at least half inside it. A page-wide rule passes here and
    is dropped later, off the pitch lattice."""
    for s, e in line[1]:
        overlap = min(e, hi) - max(s, lo)
        if overlap >= 0.5 * (hi - lo) or overlap >= 0.5 * (e - s):
            return True
    return False


def _overlap(a: Region, b: Region) -> float:
    ax0, ay0, ax1, ay1 = a.bbox
    bx0, by0, bx1, by1 = b.bbox
    w = max(0, min(ax1, bx1) - max(ax0, bx0))
    h = max(0, min(ay1, by1) - max(ay0, by0))
    return w * h / max(1, min((ax1 - ax0) * (ay1 - ay0), (bx1 - bx0) * (by1 - by0)))


def find_regions(img: Image.Image) -> list[Region]:
    """Every grid on the image, largest first."""
    if img.width * img.height > MAX_PIXELS:
        raise ValueError(
            f"image is {img.width}x{img.height} px, more than the {MAX_PIXELS // 1_000_000} megapixels the "
            "grid reader takes; scale it down first (a chart page needs about 40 px per cell)"
        )
    rgb = np.asarray(img.convert("RGB"), dtype=np.int16)
    gray = np.asarray(img.convert("L"), dtype=float)
    ex = np.abs(np.diff(rgb, axis=1)).max(axis=2) > EDGE_THRESHOLD  # (h, w-1): vertical edges
    ey = np.abs(np.diff(rgb, axis=0)).max(axis=2) > EDGE_THRESHOLD  # (h-1, w): horizontal edges
    h, w = ex.shape[0], ey.shape[1]
    min_px = max(MIN_LINE_PX, min(h, w) // 40)
    col_lines = _lines(ex, min_px)  # centre x, y-segments
    row_lines = _lines(ey.T, min_px)  # centre y, x-segments
    regions: list[Region] = []
    for cols in _clusters(col_lines):
        if len(cols) < 3:
            continue
        x0, x1 = cols[0][0], cols[-1][0]
        # Rows are not split by gap: a run of rows lost inside same-coloured cells is refilled
        # on the lattice by _refine_axis, whereas a split would seed two half-grids.
        rows = [r for r in row_lines if _fits(r, x0, x1)]
        if len(rows) < 3:
            continue
        y0, y1 = rows[0][0], rows[-1][0]
        cols_here = [c for c in cols if _fits(c, y0, y1)]
        px, py = _pitch([c[0] for c in cols_here]), _pitch([r[0] for r in rows])
        if px is None or py is None:
            continue

        def col_noise(a, b, y0=y0, y1=y1, py=py):
            return _band_noise(gray[int(y0) : int(y1), int(a) : int(b)].T, py)

        xs = _refine_axis(ex[int(y0) : int(y1) + 1, :], [c[0] for c in cols_here], px, col_noise)
        if xs is None:
            continue

        def row_noise(a, b, xs=xs, px=px):
            return _band_noise(gray[int(a) : int(b), int(xs[0]) : int(xs[-1])], px)

        ys = _refine_axis(ey[:, int(xs[0]) : int(xs[-1]) + 1].T, [r[0] for r in rows], py, row_noise)
        if ys is None:
            continue

        def col_noise2(a, b, ys=ys, py=py):
            return _band_noise(gray[int(ys[0]) : int(ys[-1]), int(a) : int(b)].T, py)

        xs = _refine_axis(ex[int(ys[0]) : int(ys[-1]) + 1, :], xs, px, col_noise2) or xs
        region = Region(xs, ys)
        region.noise = cell_noise(img, region)
        if region.noise > MAX_NOISE:
            continue  # a photo or a textured fabric, not a chart
        if any(_overlap(region, o) > 0.5 and o.cells >= region.cells for o in regions):
            continue
        regions = [o for o in regions if _overlap(region, o) <= 0.5]
        regions.append(region)
    regions.sort(key=lambda r: -r.cells)
    return regions


# ---------- sampling ----------


def read_region(img: Image.Image, region: Region, cells: tuple[int, int] | None = None) -> np.ndarray:
    """Median RGB of the centre of every cell, as an (rows, cols, 3) uint8 array."""
    xs, ys = region.xs, region.ys
    if cells is not None:
        w, h = cells
        if abs(w - region.cols) > 1 or abs(h - region.rows) > 1:
            raise ValueError(f"--cells {w}x{h} but the grid lines say {region.cols}x{region.rows}")
        xs = np.linspace(xs[0], xs[-1], w + 1).tolist()
        ys = np.linspace(ys[0], ys[-1], h + 1).tolist()
    px = np.asarray(img.convert("RGB"))
    out = np.zeros((len(ys) - 1, len(xs) - 1, 3), dtype=np.uint8)
    for j, i, my0, my1, mx0, mx1 in _patches(Region(list(xs), list(ys))):
        out[j, i] = np.median(px[my0:my1, mx0:mx1].reshape(-1, 3), axis=0)
    return out


def _patches(region: Region):
    xs, ys = region.xs, region.ys
    for j in range(len(ys) - 1):
        cy0, cy1 = ys[j], ys[j + 1]
        my0 = int(round(cy0 + (cy1 - cy0) * (0.5 - CENTRE_FRACTION / 2)))
        my1 = max(my0 + 1, int(round(cy0 + (cy1 - cy0) * (0.5 + CENTRE_FRACTION / 2))))
        for i in range(len(xs) - 1):
            cx0, cx1 = xs[i], xs[i + 1]
            mx0 = int(round(cx0 + (cx1 - cx0) * (0.5 - CENTRE_FRACTION / 2)))
            mx1 = max(mx0 + 1, int(round(cx0 + (cx1 - cx0) * (0.5 + CENTRE_FRACTION / 2))))
            yield j, i, my0, my1, mx0, mx1


def cell_noise(img: Image.Image, region: Region, sample: int = 400) -> float:
    """Mean median-absolute-deviation of grey inside the cell centres, over up to `sample` cells.
    A median deviation ignores a symbol's strokes over a flat cell; a photo deviates everywhere."""
    gray = np.asarray(img.convert("L"), dtype=float)
    patches = list(_patches(region))
    step = max(1, len(patches) // sample)
    spreads = []
    for _, _, my0, my1, mx0, mx1 in patches[::step]:
        patch = gray[my0:my1, mx0:mx1]
        spreads.append(np.median(np.abs(patch - np.median(patch))))
    return float(np.mean(spreads)) if spreads else 0.0


# ---------- colours ----------


def _to_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB (n, 3) in 0..255 to CIE Lab, D65."""
    c = rgb.astype(float) / 255
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    lab = np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], axis=1)
    return lab


def _hex(rgb) -> str:
    return "#%02x%02x%02x" % tuple(int(v) for v in rgb)


def snap_to_palette(samples: np.ndarray, hexes: list[str], max_delta: float = 25.0) -> np.ndarray:
    """Nearest palette entry per cell in Lab; a cell farther than `max_delta` is refused by name."""
    h, w, _ = samples.shape
    flat = samples.reshape(-1, 3)
    pal = np.array([[int(x[i : i + 2], 16) for i in (1, 3, 5)] for x in hexes])
    d = np.linalg.norm(_to_lab(flat)[:, None, :] - _to_lab(pal)[None, :, :], axis=2)
    idx = d.argmin(axis=1)
    worst = d[np.arange(len(flat)), idx]
    bad = int(worst.argmax())
    if worst[bad] > max_delta:
        y, x = divmod(bad, w)
        raise ValueError(
            f"cell (column {x + 1}, row {y + 1} from the top) reads {_hex(flat[bad])}, "
            f"which is no palette colour (nearest {hexes[idx[bad]]}, distance {worst[bad]:.0f})"
        )
    return idx.reshape(h, w).astype(np.uint8)


def cluster_palette(samples: np.ndarray, radius: float = 6.0) -> tuple[np.ndarray, list[str], list[str]]:
    """Greedy clustering in Lab by frequency: (indexes, hexes, warnings). Codes are by frequency."""
    h, w, _ = samples.shape
    flat = samples.reshape(-1, 3)
    colours, counts = np.unique(flat, axis=0, return_counts=True)
    order = np.argsort(-counts)
    centres: list[np.ndarray] = []
    members: list[list[int]] = []
    lab = _to_lab(colours)
    assign = np.zeros(len(colours), dtype=int)
    for k in order:
        if centres:
            d = np.linalg.norm(np.array(centres) - lab[k], axis=1)
            j = int(d.argmin())
            if d[j] <= radius:
                assign[k] = j
                members[j].append(int(k))
                continue
        centres.append(lab[k])
        members.append([int(k)])
        assign[k] = len(centres) - 1
    # A tiny cluster near a big one is a watermark or a symbol tinting a few cells: fold it in
    # and say so. A tiny cluster near nothing (two black eyes) is a colour and stays.
    warnings = []
    totals = [int(sum(counts[i] for i in m)) for m in members]
    total_cells = flat.shape[0]
    for j in sorted(range(len(members)), key=lambda j: totals[j]):
        if totals[j] >= 0.005 * total_cells or len(members[j]) == 0:
            continue
        others = [
            k for k in range(len(members)) if k != j and members[k] and totals[k] >= 0.005 * total_cells
        ]
        if not others:
            continue
        d = [float(np.linalg.norm(centres[k] - centres[j])) for k in others]
        k = others[int(np.argmin(d))]
        if min(d) <= 2 * radius:
            warnings.append(
                f"{totals[j]} cell(s) of {_hex(colours[members[j][0]])} folded into "
                f"{_hex(colours[max(members[k], key=lambda i: counts[i])])} (a watermark or symbol tinted them)"
            )
            members[k] += members[j]
            totals[k] += totals[j]
            members[j], totals[j] = [], 0
    keep = [j for j in range(len(members)) if members[j]]
    members = [members[j] for j in keep]
    totals = [totals[j] for j in keep]
    for new_j, m in enumerate(members):
        for i in m:
            assign[i] = new_j
    # Each cluster's colour is its most frequent member; clusters are ordered by cell count.
    reps = [colours[max(m, key=lambda i: counts[i])] for m in members]
    rank = sorted(range(len(reps)), key=lambda j: -totals[j])
    remap = {old: new for new, old in enumerate(rank)}
    lookup = {tuple(colours[k]): remap[assign[k]] for k in range(len(colours))}
    idx = np.array([lookup[tuple(c)] for c in flat], dtype=np.uint8).reshape(h, w)
    hexes = [_hex(reps[j]) for j in rank]
    for new, old in enumerate(rank):
        if totals[old] < max(2, 0.001 * flat.shape[0]):
            warnings.append(
                f"colour {hexes[new]} covers only {totals[old]} cell(s); a grid line or symbol may have bled in"
            )
    return idx, hexes, warnings


def name_colour(hex_str: str) -> str:
    rgb = np.array([[int(hex_str[i : i + 2], 16) for i in (1, 3, 5)]])
    names = list(COLOR_NAMES)
    table = np.array([COLOR_NAMES[n] for n in names])
    d = np.linalg.norm(_to_lab(table) - _to_lab(rgb), axis=1)
    return names[int(d.argmin())]
