"""Generic chart invariants and reports. Pattern-specific checks live in each pattern's tests."""

from __future__ import annotations

import numpy as np

from .export import decode_rows, rle_rows, rows_to_strings
from .palette import CODE_RE


def bad_rows(a, width):
    return [i for i, row in enumerate(a) if len(row) != width]


def row_totals_match(a, codes):
    """Round-trip the emitted RLE strings and compare against the source grid (shape and values)."""
    decoded = decode_rows(rows_to_strings(a, codes), codes)
    return decoded.shape == a.shape and bool(np.array_equal(decoded, a))


def palette_codes_valid(codes):
    return all(CODE_RE.match(c) for c in codes)


def used_indices(a):
    return set(int(v) for v in np.unique(a))


def solid_edge(a, color, ex, ey):
    return bool(
        (a[:ey] == color).all()
        and (a[-ey:] == color).all()
        and (a[:, :ex] == color).all()
        and (a[:, -ex:] == color).all()
    )


def mirror_lr(a, n_cols):
    return bool(np.array_equal(a[:, :n_cols], a[:, -n_cols:][:, ::-1]))


def mirror_tb(a, n_rows):
    return bool(np.array_equal(a[:n_rows], a[-n_rows:][::-1]))


def changes_per_row(a):
    return [len(r) - 1 for r in rle_rows(a)]


def min_run(a):
    return min(n for row in rle_rows(a) for _, n in row)


def run_all(a, meta):
    """Returns [(name, ok, detail)]: the checks every chart must pass (row totals, palette codes,
    palette closure), then the shape checks the pattern opted into in its `[checks]` table
    (solid edge, first row solid, mirrored edges), then two lines that only report."""
    h, w = a.shape
    used = used_indices(a)
    first = meta.palette[meta.first_row_color] if meta.first_row_color in meta.palette else None
    ch = changes_per_row(a)
    codes = meta.palette.codes
    checks = getattr(meta, "checks", {}) or {}
    results = [
        ("row totals", row_totals_match(a, codes), f"{h} rows of {w}"),
        ("palette codes", palette_codes_valid(codes), f"codes: {', '.join(codes)}"),
        ("palette closure", used <= set(range(len(meta.palette))), f"indices used: {sorted(used)}"),
    ]
    # A width of 0 (or an absent key) means the check is off; `first_row_solid` is a plain switch.
    if checks.get("solid_edge", 0) > 0:
        n = checks["solid_edge"]
        results.append(
            (
                "solid edge",
                first is not None and solid_edge(a, first, n, n),
                f"outer {n} cell(s) are {meta.first_row_color}",
            )
        )
    if checks.get("first_row_solid", False) is True:
        results.append(
            ("first row solid", first is not None and bool((a[-1] == first).all()), "row 1 is a single color")
        )
    if checks.get("mirror_lr", 0) > 0:
        n = checks["mirror_lr"]
        results.append((f"mirror left/right (outer {n} cols)", mirror_lr(a, n), ""))
    if checks.get("mirror_tb", 0) > 0:
        n = checks["mirror_tb"]
        results.append((f"mirror top/bottom (outer {n} rows)", mirror_tb(a, n), ""))
    results += [
        ("changes per row", True, f"mean {sum(ch) / len(ch):.1f}, max {max(ch)}"),
        ("min run", True, f"{min_run(a)} stitch(es)"),
    ]
    return results
