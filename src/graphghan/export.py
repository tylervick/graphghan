"""Exports: run-length rows, PNGs, stats, written rows, chart.json (schema 2)."""

from __future__ import annotations

import json
from importlib.metadata import PackageNotFoundError
from importlib.metadata import version as pkg_version
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from . import grid as gr
from .chartdoc import RUN_RE, TECHNIQUE_ROWS, cell_kind, chart_id, size_derives, validate_document

SCHEMA = 2
SITE_URL = "https://graphghan.milo.cat/"


def generator_version() -> str:
    try:
        return pkg_version("graphghan")
    except PackageNotFoundError:
        return "0"


def palette_entries(palette) -> list[dict]:
    out = []
    for c in palette.colors:
        entry = {"code": c.code, "name": c.name, "hex": c.hex, "yarn": dict(c.yarn), "use": c.use}
        if c.thread:
            entry["thread"] = dict(c.thread)
        if c.symbol:
            entry["symbol"] = c.symbol
        out.append(entry)
    return out


def rle_rows(a):
    out = []
    for row in a:
        runs, prev, n = [], int(row[0]), 0
        for v in row:
            v = int(v)
            if v == prev:
                n += 1
            else:
                runs.append((prev, n))
                prev, n = v, 1
        runs.append((prev, n))
        out.append(runs)
    return out


def rows_to_strings(a, codes):
    return ["".join(f"{n}{codes[c]}" for c, n in row) for row in rle_rows(a)]


def decode_rows(strings, codes):
    idx = {c: i for i, c in enumerate(codes)}
    rows = []
    for s in strings:
        row = []
        for n, c in RUN_RE.findall(s):
            row += [idx[c]] * int(n)
        rows.append(row)
    return np.array(rows, dtype=np.uint8)


def chart_png(a, rgb, path):
    img = Image.new("P", (a.shape[1], a.shape[0]))
    pal = [v for c in rgb for v in c] + [0, 0, 0] * (256 - len(rgb))
    img.putpalette(pal)
    img.putdata(a.astype(np.uint8).ravel().tolist())
    img.convert("RGB").save(path)


def preview_image(a, rgb, cw=8, ch=None, grid=False, bold_every=10) -> Image.Image:
    """The preview as a PIL image: `cw` px per column and, by default, the fabric proportion per row."""
    h, w = a.shape
    if ch is None:
        ch = max(1, int(round(cw * gr.SH / gr.SW)))
    img = Image.fromarray(np.array(rgb, dtype=np.uint8)[a]).resize((w * cw, h * ch), Image.NEAREST)
    if grid:
        d = ImageDraw.Draw(img)
        for x in range(w + 1):
            d.line(
                [(x * cw, 0), (x * cw, h * ch)], fill=(0, 0, 0) if x % bold_every == 0 else (120, 120, 120)
            )
        for y in range(h + 1):
            d.line(
                [(0, y * ch), (w * cw, y * ch)], fill=(0, 0, 0) if y % bold_every == 0 else (120, 120, 120)
            )
    return img


def preview_png(a, rgb, path, cw=8, ch=None, grid=False, bold_every=10):
    preview_image(a, rgb, cw, ch, grid, bold_every).save(path)


def stats(a, codes, kind="stitch", sized=True):
    h, w = a.shape
    counts = {codes[i]: int((a == i).sum()) for i in range(len(codes))}
    runs = rle_rows(a)
    singles = {c: 0 for c in codes}
    per_row = []
    for row in runs:
        per_row.append(len(row) - 1)
        for c, n in row:
            if n == 1:
                singles[codes[c]] += 1
    cell_sqin = gr.SW * gr.SH
    yards = {
        code: n * cell_sqin * 1.1 * 1.2 for code, n in counts.items()
    }  # 1.1 yd/sq in worsted sc, +20% tails
    out = {
        "cells": int(w * h),
        # gr.SW/gr.SH are per-STITCH dimensions, so this conversion is only meaningful when the
        # gauge and the grid count the same thing (#48). The caller resolves that pairing. Kept
        # in this original key position (rather than appended) so a sized chart's stats are
        # byte-identical to before `sized` existed.
        **({"size_in": [round(w * gr.SW, 1), round(h * gr.SH, 1)]} if sized else {}),
        "counts": counts,
        "single_stitch_runs": singles,
        "color_changes_per_row": {
            "mean": round(sum(per_row) / len(per_row), 1),
            "max": max(per_row),
            "per_row": per_row,
        },
    }
    if kind == "stitch":
        # Every number below counts stitches. A cell is only a stitch when the chart says so, and
        # a missing key cannot be misread the way a wrong number can (#44).
        out["stitches"] = int(w * h)
        out["yards_est"] = {k: int(round(v)) for k, v in yards.items()}
        out["skeins_364yd"] = {k: round(v / 364, 1) for k, v in yards.items()}
    return out


def written_rows(a, codes, boundary=None):
    """One line per pass. From row 2 on, a `turn` boundary prints its chain first — where most
    published patterns and Crochetpop's generator put it. Other boundary kinds print nothing:
    Phase 1 readers implement `turn` only (docs/chart-format.md §Gauge)."""
    runs = rle_rows(a)
    h = len(runs)
    prefix = ""
    if boundary and boundary.get("kind") == "turn":
        chain = int(boundary.get("chain", 0))
        prefix = f"ch {chain}, turn, " if chain > 0 else "turn, "
    lines = []
    for i in range(h):
        row_no = i + 1
        row = runs[h - 1 - i]
        if row_no % 2 == 1:
            row = row[::-1]
        side = "RS" if row_no % 2 == 1 else "WS"
        lines.append(
            f"Row {row_no} ({side}): "
            + (prefix if row_no > 1 else "")
            + ", ".join(f"{n} {codes[c]}" for c, n in row)
            + f"  ({sum(n for _, n in row)} sts)"
        )
    return lines


def _gauge_number(v: float) -> float | int:
    """14.0 -> 14, 6.5 -> 6.5: gauge counts are whole numbers far more often than not."""
    f = float(v)
    return int(f) if f.is_integer() else f


def chart_json(a, meta, gauge_key, report, variant="final"):
    st, rows_per_in = meta.gauges.get(gauge_key, gr.GAUGES[gauge_key])
    if gr.current_gauge() != (st, rows_per_in):
        raise ValueError(
            f"active gauge {gr.current_gauge()} does not match gauge_key {gauge_key!r} {(st, rows_per_in)}; "
            "call gr.set_gauge first"
        )
    codes = meta.palette.codes
    rows = rows_to_strings(a, codes)
    technique = dict(TECHNIQUE_ROWS)
    report_out = {k: (list(v) if isinstance(v, tuple) else v) for k, v in report.items()}
    stitch = meta.stitches.get(gauge_key, {})
    pattern = {
        "id": meta.slug,
        "title": meta.title,
        "version": meta.version,
        "author": meta.author,
        "license": meta.license,
        "dedication": meta.dedication,
        "quote": meta.quote,
        "url": f"{SITE_URL}patterns/{meta.slug}/",
    }
    if meta.craft:
        pattern["craft"] = meta.craft
    if meta.language:
        pattern["language"] = meta.language
    gauge = {
        "stitches": _gauge_number(st * 4),
        "rows": _gauge_number(rows_per_in * 4),
        "over": {"value": 4, "unit": "in"},
        "stitch": gauge_key,
        "hook": meta.hook,
        "yarn_weight": meta.yarn_weight,
    }
    if "unit" in stitch:
        gauge["unit"] = stitch["unit"]
    if "name" in stitch:
        gauge["stitch_name"] = stitch["name"]
    if meta.terms:
        gauge["terms"] = meta.terms
    if meta.terms_also:
        gauge["terms_also"] = meta.terms_also
    if "boundary" in stitch:  # always paired with chain by pattern._stitch_entry
        boundary = {"kind": stitch["boundary"], "chain": stitch["chain"]}
        if "counts_as_stitch" in stitch:
            boundary["counts_as_stitch"] = stitch["counts_as_stitch"]
        if "chain_color" in stitch:
            boundary["color"] = stitch["chain_color"]
        gauge["boundary"] = boundary
    chart_block = {
        "id": chart_id(codes, rows, technique),
        "variant": variant,
        "gauge_key": gauge_key,
        "width": int(a.shape[1]),
        "height": int(a.shape[0]),
    }
    doc = {
        "schema": SCHEMA,
        "pattern": pattern,
        "chart": chart_block,
        "generator": {"name": "graphghan", "version": generator_version()},
        "palette": palette_entries(meta.palette),
        "rows": rows,
        "gauge": gauge,
        "technique": technique,
        "instructions": [dict(s) for s in meta.instructions],
        "stats": {},  # placeholder holds this key's position; replaced below once chart/gauge are on doc
        "ext": {"graphghan": {"report": report_out}},
    }
    # cell_kind/size_derives read chart.cell and gauge.unit off the real document; both are already
    # on `doc` above, so no synthetic proxy is needed. Assigning to the existing "stats" key
    # preserves its position (Python dict semantics), keeping this byte-identical to before.
    doc["stats"] = stats(a, codes, cell_kind(doc), size_derives(doc))
    if "first_stitch_in" in stitch:
        fsi = stitch["first_stitch_in"]
        foundation = {"chain": int(a.shape[1]) + fsi - 1, "first_stitch_in": fsi}
        first = next((c for c in meta.palette.colors if c.code == meta.first_row_color), None)
        if first is not None:
            foundation["note"] = f"in {first.name} ({first.code})"
        doc["foundation"] = foundation
    return doc


def write_dist(a, meta, gauge_key, report, out_dir, variant="final"):
    doc = chart_json(a, meta, gauge_key, report, variant)
    problems = validate_document(doc)
    if problems:  # never write a chart no reader would accept
        raise ValueError("chart failed validation: " + "; ".join(problems))
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "chart.json").write_text(json.dumps(doc, separators=(",", ":")) + "\n")
    chart_png(a, meta.palette.rgb, out / "chart.png")
    preview_png(a, meta.palette.rgb, out / "preview.png")
    preview_png(a, meta.palette.rgb, out / "preview-grid.png", grid=True)
    (out / "written-rows.txt").write_text(
        "\n".join(written_rows(a, meta.palette.codes, boundary=doc["gauge"].get("boundary"))) + "\n"
    )
    return doc
