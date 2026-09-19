"""The prose half of an import: `prose.json`, what a reader of a pattern's text hands to
`graphghan import` (spec §6.2 of docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md),
and what the importer does with it: map the written rows onto the grid, check every row's total,
cross-check against the grid read off the chart, and carry the metadata into pattern.toml.

Written rows are the primary source when present; the grid is the cross-check (spec §6.3). A row
that fails is reported with its number, page and text, never corrected.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

import numpy as np

from .chartdoc import CODE_RE, HEX_RE

SCHEMA_ID = "graphghan-import/1"
ROW1_POSITIONS = ("bottom-right", "bottom-left", "top-left", "top-right")
MISMATCH_LIMIT = 0.10  # more rows than this disagreeing with the grid means the orientation is wrong
STITCH_KEYS = {
    "single crochet": "sc",
    "half double crochet": "hdc",
    "double crochet": "dc",
    "treble crochet": "tr",
    "herringbone double crochet": "hbdc",
}


# ---------- loading and checking ----------


def load_prose(path: str | Path) -> dict:
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    problems = check_prose(doc)
    if problems:
        raise ValueError(f"{path}: " + "; ".join(problems))
    return doc


def check_prose(doc) -> list[str]:
    """The structural checks the schema cannot phrase, in the words the reader needs."""
    problems: list[str] = []
    if not isinstance(doc, dict):
        return ["prose.json is not an object"]
    if doc.get("schema") != SCHEMA_ID:
        problems.append(f"schema must be {SCHEMA_ID!r}, not {doc.get('schema')!r}")
    palette = doc.get("palette", [])
    if not isinstance(palette, list):
        problems.append("palette is not a list")
        palette = []
    seen: set[str] = set()
    for i, p in enumerate(palette):
        if not isinstance(p, dict):
            problems.append(f"palette[{i}] is not an object")
            continue
        code = p.get("code", "")
        if not isinstance(code, str) or not CODE_RE.match(code):
            problems.append(f"palette[{i}].code {code!r} is not 1-3 letters")
        elif code in seen:
            problems.append(f"palette[{i}].code {code!r} is a duplicate")
        seen.add(code)
        if "hex" in p and not HEX_RE.match(str(p["hex"])):
            problems.append(f"palette[{i}].hex {p['hex']!r} is not #RRGGBB")
    chart = doc.get("chart", {})
    if not isinstance(chart, dict):
        problems.append("chart is not an object")
        chart = {}
    if "row1" in chart and chart["row1"] not in ROW1_POSITIONS:
        problems.append(f"chart.row1 {chart['row1']!r} is not one of {ROW1_POSITIONS}")
    for key in ("width", "height"):
        v = chart.get(key)
        if v is not None and (isinstance(v, bool) or not isinstance(v, int) or v < 1):
            problems.append(f"chart.{key} {v!r} is not a positive integer")
    rows = doc.get("written_rows", [])
    if not isinstance(rows, list):
        problems.append("written_rows is not a list")
        rows = []
    for i, r in enumerate(rows):
        if not isinstance(r, dict):
            problems.append(f"written_rows[{i}] is not an object")
            continue
        n = r.get("row")
        if isinstance(n, bool) or not isinstance(n, int) or n < 1:
            problems.append(f"written_rows[{i}].row {n!r} is not a positive integer")
        runs = r.get("runs")
        if not isinstance(runs, list) or not runs:
            problems.append(f"written_rows[{i}] (row {n}) has no runs")
            continue
        for j, run in enumerate(runs):
            ok = (
                isinstance(run, (list, tuple))
                and len(run) == 2
                and isinstance(run[0], str)
                and CODE_RE.match(run[0])
                and isinstance(run[1], int)
                and not isinstance(run[1], bool)
                and run[1] >= 1
            )
            if not ok:
                problems.append(f"written_rows[{i}] (row {n}) runs[{j}] {run!r} is not [code, count]")
    gauge = doc.get("gauge", {})
    if isinstance(gauge, dict) and "over" in gauge:
        over = gauge["over"]
        if not isinstance(over, dict) or over.get("unit") not in ("in", "cm") or not over.get("value"):
            problems.append("gauge.over must be {value, unit in|cm}")
    size = doc.get("finished_size")
    if size is not None and (
        not isinstance(size, dict)
        or size.get("unit") not in ("in", "cm")
        or not size.get("width")
        or not size.get("height")
    ):
        problems.append("finished_size must be {width, height, unit in|cm}")
    return problems


# ---------- written rows onto the grid ----------


def _describe(entry: dict) -> str:
    where = f"page {entry['page']}: " if entry.get("page") else ""
    text = entry.get("text")
    return f' ({where}"{text}")' if text else (f" ({where.rstrip(': ')})" if where else "")


def row_total_problems(rows: list[dict], width: int) -> list[str]:
    """Every written row whose runs do not sum to the chart width, or to its own printed total."""
    out = []
    for r in rows:
        total = sum(n for _, n in r["runs"])
        printed = r.get("total")
        if printed is not None and printed != total:
            out.append(
                f"row {r['row']}: runs sum to {total} but the pattern prints {printed} sts{_describe(r)}"
            )
        elif total != width:
            out.append(f"row {r['row']}: runs sum to {total}, chart width is {width}{_describe(r)}")
    return out


def row_number_problems(rows: list[dict], height: int) -> list[str]:
    numbers = [r["row"] for r in rows]
    out = []
    counts: dict[int, int] = {}
    for n in numbers:
        counts[n] = counts.get(n, 0) + 1
    dup = sorted(n for n, c in counts.items() if c > 1)
    if dup:
        out.append("row " + ", ".join(str(n) for n in dup) + " printed twice")
    missing = sorted(set(range(1, height + 1)) - set(numbers))
    if missing:
        out.append(f"missing rows {_ranges(missing)} of {height}")
    beyond = sorted(n for n in set(numbers) if n > height)
    if beyond:
        out.append(f"rows {_ranges(beyond)} are beyond the chart height {height}")
    return out


def _ranges(nums: list[int]) -> str:
    parts, start, prev = [], nums[0], nums[0]
    for n in nums[1:] + [None]:
        if n is not None and n == prev + 1:
            prev = n
            continue
        parts.append(str(start) if start == prev else f"{start}-{prev}")
        if n is not None:
            start = prev = n
    return ", ".join(parts)


def reads_right_to_left(row: int, row1: str) -> bool:
    """Working direction of a written row: row 1 starts at the printed corner; rows alternate."""
    starts_right = row1.endswith("right")
    return starts_right if row % 2 == 1 else not starts_right


def grid_row(row: int, height: int, row1: str) -> int:
    return height - row if row1.startswith("bottom") else row - 1


def written_to_grid(
    rows: list[dict], codes: list[str], width: int, height: int, row1: str = "bottom-right"
) -> tuple[np.ndarray | None, list[str]]:
    """The grid the written rows describe, in display order, or None with every problem found."""
    problems = row_total_problems(rows, width) + row_number_problems(rows, height)
    index = {c: i for i, c in enumerate(codes)}
    for r in rows:
        for code, _ in r["runs"]:
            if code not in index:
                problems.append(
                    f"row {r['row']} uses code {code!r}, not in the palette {codes}{_describe(r)}"
                )
                break
    if problems:
        return None, problems
    grid = np.zeros((height, width), dtype=np.uint8)
    for r in rows:
        cells = [index[c] for c, n in r["runs"] for _ in range(n)]
        if reads_right_to_left(r["row"], row1):
            cells.reverse()
        grid[grid_row(r["row"], height, row1)] = cells
    return grid, []


def cross_check(
    from_rows: np.ndarray, from_grid: np.ndarray, row1: str = "bottom-right"
) -> tuple[list[str], str | None]:
    """Rows that disagree with the grid read off the chart: warnings, plus an error when so many
    disagree that the orientation, not the reading, must be wrong."""
    if from_rows.shape != from_grid.shape:
        return (
            [],
            f"written rows give {from_rows.shape[1]}x{from_rows.shape[0]}, the chart reads {from_grid.shape[1]}x{from_grid.shape[0]}",
        )
    height, width = from_rows.shape
    mismatches = []
    for y in range(height):
        diff = np.flatnonzero(from_rows[y] != from_grid[y])
        if len(diff):
            row = height - y if row1.startswith("bottom") else y + 1
            x = int(diff[0])
            col = width - x if row1.endswith("right") else x + 1
            mismatches.append(f"row {row}: {len(diff)} cell(s) differ from the chart, first at column {col}")
    error = None
    if len(mismatches) > max(1, math.ceil(MISMATCH_LIMIT * height)):
        hint = ""
        if np.array_equal(from_rows[::-1], from_grid):
            hint = (
                " The grid matches when flipped top to bottom: chart.row1 probably starts at the other edge."
            )
        elif np.array_equal(from_rows[:, ::-1], from_grid):
            hint = " The grid matches when flipped left to right: chart.row1 probably starts at the other corner."
        elif np.array_equal(from_rows[::-1, ::-1], from_grid):
            hint = " The grid matches when rotated: chart.row1 is probably the opposite corner."
        error = (
            f"{len(mismatches)} of {height} rows disagree with the chart; the row-1 position or "
            f"direction is probably wrong, not the rows.{hint}"
        )
    return mismatches, error


# ---------- metadata ----------


def gauge_per_inch(gauge: dict) -> tuple[float, float] | None:
    st, rows, over = gauge.get("stitches"), gauge.get("rows"), gauge.get("over")
    if not st or not rows or not isinstance(over, dict):
        return None
    length = float(over["value"]) / (2.54 if over.get("unit") == "cm" else 1.0)
    return round(float(st) / length, 4), round(float(rows) / length, 4)


def gauge_key(gauge: dict) -> str:
    key = gauge.get("stitch")
    if key:
        return key
    name = (gauge.get("stitch_name") or "").strip().lower()
    if name in STITCH_KEYS:
        return STITCH_KEYS[name]
    return re.sub(r"[^a-z0-9]+", "-", name).strip("-") or "sc"


def size_inches(size: dict | None) -> tuple[float, float] | None:
    if not isinstance(size, dict):
        return None
    f = 1 / 2.54 if size.get("unit") == "cm" else 1.0
    return round(float(size["width"]) * f, 1), round(float(size["height"]) * f, 1)


def palette_entries(doc: dict) -> list[dict]:
    """Chart-format palette entries from the prose palette (hex may be absent until matched)."""
    out = []
    for p in doc.get("palette", []):
        entry = {
            "code": p["code"],
            "name": p.get("name") or p.get("key_label") or p["code"],
            "hex": p.get("hex"),
            "yarn": dict(p.get("yarn") or {}),
            "use": p.get("use", ""),
        }
        out.append(entry)
    return out


def meta_from_prose(doc: dict) -> dict:
    """What pattern_toml reads: everything but the palette and the rows."""
    p = doc.get("pattern") or {}
    g = doc.get("gauge") or {}
    meta = {
        k: p[k]
        for k in (
            "title",
            "author",
            "dedication",
            "quote",
            "license",
            "version",
            "craft",
            "terms",
            "language",
        )
        if p.get(k)
    }
    per_inch = gauge_per_inch(g)
    if per_inch:
        meta["gauge"] = per_inch
        meta["stitch"] = gauge_key(g)
    for k in ("hook", "yarn_weight", "stitch_name", "boundary", "unit"):
        if g.get(k):
            meta[k] = g[k]
    size = size_inches(doc.get("finished_size"))
    if size:
        meta["size_in"] = size
    notes = doc.get("notes") or {}
    if notes.get("setup") or notes.get("colors"):
        meta["notes"] = {k: list(notes.get(k, [])) for k in ("setup", "colors")}
    if doc.get("instructions"):
        meta["instructions"] = [dict(s) for s in doc["instructions"]]
    if doc.get("chart", {}).get("cell"):
        meta["cell"] = dict(doc["chart"]["cell"])
    if doc.get("uncertain"):
        meta["uncertain"] = list(doc["uncertain"])
    return meta
