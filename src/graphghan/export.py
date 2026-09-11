"""Exports: run-length rows, PNGs, stats, written rows, chart.json (schema 1)."""

from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from . import grid as gr

SCHEMA = 1
_RUN = re.compile(r"(\d+)([A-Za-z]{1,3})")


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
        for n, c in _RUN.findall(s):
            row += [idx[c]] * int(n)
        rows.append(row)
    return np.array(rows, dtype=np.uint8)


def chart_png(a, rgb, path):
    img = Image.new("P", (a.shape[1], a.shape[0]))
    pal = [v for c in rgb for v in c] + [0, 0, 0] * (256 - len(rgb))
    img.putpalette(pal)
    img.putdata(a.astype(np.uint8).ravel().tolist())
    img.convert("RGB").save(path)


def preview_png(a, rgb, path, cw=8, ch=None, grid=False, bold_every=10):
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
    img.save(path)


def stats(a, codes):
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
    return {
        "stitches": int(w * h),
        "size_in": [round(w * gr.SW, 1), round(h * gr.SH, 1)],
        "counts": counts,
        "single_stitch_runs": singles,
        "color_changes_per_row": {
            "mean": round(sum(per_row) / len(per_row), 1),
            "max": max(per_row),
            "per_row": per_row,
        },
        "yards_est": {k: int(round(v)) for k, v in yards.items()},
        "skeins_364yd": {k: round(v / 364, 1) for k, v in yards.items()},
    }


def written_rows(a, codes):
    runs = rle_rows(a)
    h = len(runs)
    lines = []
    for i in range(h):
        row_no = i + 1
        row = runs[h - 1 - i]
        if row_no % 2 == 1:
            row = row[::-1]
        side = "RS" if row_no % 2 == 1 else "WS"
        lines.append(
            f"Row {row_no} ({side}): "
            + ", ".join(f"{n} {codes[c]}" for c, n in row)
            + f"  ({sum(n for _, n in row)} sts)"
        )
    return lines


def chart_json(a, meta, gauge_key, report, variant="final"):
    st, rows = meta.gauges.get(gauge_key, gr.GAUGES[gauge_key])
    if gr.current_gauge() != (st, rows):
        raise ValueError(
            f"active gauge {gr.current_gauge()} does not match gauge_key {gauge_key!r} {(st, rows)}; "
            "call gr.set_gauge first"
        )
    codes = meta.palette.codes
    return {
        "schema": SCHEMA,
        "slug": meta.slug,
        "title": meta.title,
        "dedication": meta.dedication,
        "quote": meta.quote,
        "version": meta.version,
        "variant": variant,
        "stitch": gauge_key,
        "gauge": {"st_per_in": st, "rows_per_in": rows},
        "cell_aspect": round(st / rows, 4),
        "hook": meta.hook,
        "yarn_weight": meta.yarn_weight,
        "first_row_color": meta.first_row_color,
        "width": int(a.shape[1]),
        "height": int(a.shape[0]),
        "size_in": [round(a.shape[1] / st, 1), round(a.shape[0] / rows, 1)],
        "palette": [
            {"code": c.code, "name": c.name, "hex": c.hex, "yarn": c.yarn, "use": c.use}
            for c in meta.palette.colors
        ],
        "rows": rows_to_strings(a, codes),
        "stats": stats(a, codes),
        "notes": meta.notes,
        "report": {k: (list(v) if isinstance(v, tuple) else v) for k, v in report.items()},
    }


def write_dist(a, meta, gauge_key, report, out_dir, variant="final"):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    doc = chart_json(a, meta, gauge_key, report, variant)
    (out / "chart.json").write_text(json.dumps(doc, separators=(",", ":")) + "\n")
    chart_png(a, meta.palette.rgb, out / "chart.png")
    preview_png(a, meta.palette.rgb, out / "preview.png")
    preview_png(a, meta.palette.rgb, out / "preview-grid.png", grid=True)
    (out / "written-rows.txt").write_text("\n".join(written_rows(a, meta.palette.codes)) + "\n")
    return doc
