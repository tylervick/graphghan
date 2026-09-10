"""Generic chart invariants and reports. Pattern-specific checks live in each pattern's tests."""

from __future__ import annotations

import numpy as np

from .export import rle_rows


def bad_rows(a, width):
    return [i for i, row in enumerate(a) if len(row) != width]


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
    """Returns [(name, ok, detail)] for the checks every pattern must pass."""
    h, w = a.shape
    used = used_indices(a)
    first = meta.palette[meta.first_row_color] if meta.first_row_color in meta.palette else None
    ch = changes_per_row(a)
    results = [
        ("row totals", bad_rows(a, w) == [], f"{h} rows of {w}"),
        ("palette closure", used <= set(range(len(meta.palette))), f"indices used: {sorted(used)}"),
        (
            "solid edge",
            first is not None and solid_edge(a, first, 1, 1),
            f"edge color {meta.first_row_color}",
        ),
        ("first row solid", first is not None and bool((a[-1] == first).all()), "row 1 is a single color"),
        ("mirror left/right (outer 2 cols)", mirror_lr(a, 2), ""),
        ("mirror top/bottom (outer 2 rows)", mirror_tb(a, 2), ""),
        ("changes per row", True, f"mean {sum(ch) / len(ch):.1f}, max {max(ch)}"),
        ("min run", True, f"{min_run(a)} stitch(es)"),
    ]
    return results
