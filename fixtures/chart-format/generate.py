"""Generate the chart-format conformance fixtures into this directory.

    uv run python fixtures/chart-format/generate.py

Expected sequences for the small fixtures are written out by hand below rather than produced by
graphghan.chartdoc.sequence, so the conformance test checks the sequencer against an independent
expectation. The Craigh na Dun fixture is a copy of the committed dist chart and its sequence is
pinned by hash (a regression pin, not an independent expectation).
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

from graphghan.chartdoc import chart_id, sequence

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

ROWS_T = {"type": "rows", "start": "bottom", "first_side": "RS", "rs_direction": "rtl", "turn": True}
ROUNDS_T = {"type": "rounds", "start": "bottom", "first_side": "RS", "rs_direction": "rtl"}
GAUGE = {"stitches": 14.0, "rows": 16.0, "over": {"value": 4, "unit": "in"}, "stitch": "sc"}


def chart(pid, title, palette, rows, technique, passes=None, layers=None):
    codes = [c for c, _ in palette]
    width = sum(int(n) for n, _ in re.findall(r"(\d+)([A-Za-z]{1,3})", rows[0]))
    doc = {
        "schema": 2,
        "pattern": {
            "id": pid,
            "title": title,
            "version": "1.0.0",
            "author": "graphghan fixtures",
            "license": "MIT",
        },
        "chart": {
            "id": chart_id(codes, rows, technique, passes),
            "variant": "final",
            "gauge_key": "sc",
            "width": width,
            "height": len(rows),
        },
        "generator": {"name": "graphghan-fixtures", "version": "1"},
        "palette": [{"code": c, "name": f"Color {c}", "hex": h} for c, h in palette],
        "rows": rows,
        "gauge": dict(GAUGE),
        "technique": technique,
        "instructions": [],
    }
    if layers is not None:
        doc["layers"] = layers
    if passes is not None:
        doc["passes"] = passes
    return doc


def run(code, count, x0):
    return {"code": code, "count": count, "x0": x0}


def p(label, side, direction, grid_row, runs):
    return {"label": label, "side": side, "direction": direction, "grid_row": grid_row, "runs": runs}


MINIMAL_PALETTE = [("A", "#112233"), ("B", "#ffffff")]
MINIMAL_ROWS = ["14A"] * 2 + ["2A10B2A"] * 8 + ["14A"] * 2  # the tests/fixtures/minimal pattern at sc
FULL = [run("A", 14, 0)]
LTR = [run("A", 2, 0), run("B", 10, 2), run("A", 2, 12)]
RTL = [run("A", 2, 12), run("B", 10, 2), run("A", 2, 0)]
MINIMAL_ROWS_SEQ = [
    p("Row 1", "RS", "rtl", 11, FULL),
    p("Row 2", "WS", "ltr", 10, FULL),
    p("Row 3", "RS", "rtl", 9, RTL),
    p("Row 4", "WS", "ltr", 8, LTR),
    p("Row 5", "RS", "rtl", 7, RTL),
    p("Row 6", "WS", "ltr", 6, LTR),
    p("Row 7", "RS", "rtl", 5, RTL),
    p("Row 8", "WS", "ltr", 4, LTR),
    p("Row 9", "RS", "rtl", 3, RTL),
    p("Row 10", "WS", "ltr", 2, LTR),
    p("Row 11", "RS", "rtl", 1, FULL),
    p("Row 12", "WS", "ltr", 0, FULL),
]
MINIMAL_ROUNDS_SEQ = [
    p(f"Round {k}", "RS", "rtl", 12 - k, FULL if k in (1, 2, 11, 12) else RTL) for k in range(1, 13)
]

TWO_LETTER_PALETTE = [("G", "#1E4D3A"), ("Gd", "#D9A21B"), ("Kb", "#2B2F33"), ("Y", "#F2E8D5")]
TWO_LETTER_ROWS = ["7Gd2G3Y", "2G7Gd3Kb"]
TWO_LETTER_SEQ = [
    p("Row 1", "RS", "rtl", 1, [run("Kb", 3, 9), run("Gd", 7, 2), run("G", 2, 0)]),
    p("Row 2", "WS", "ltr", 0, [run("Gd", 7, 0), run("G", 2, 7), run("Y", 3, 9)]),
]

STITCH_LAYER = {"stitch": {"legend": {"k": "knit", "p": "purl"}, "rows": ["12k", "6k6p"]}}
# Hand-written, and deliberately the same pass list as two-letter-codes: a layer is a parallel grid
# a reader may not understand, and it must not change the colour sequence in any way.
LAYERS_STITCH_SEQ = [
    p("Row 1", "RS", "rtl", 1, [run("Kb", 3, 9), run("Gd", 7, 2), run("G", 2, 0)]),
    p("Row 2", "WS", "ltr", 0, [run("Gd", 7, 0), run("G", 2, 7), run("Y", 3, 9)]),
]

EXPLICIT_PASSES = [
    p("Row 1", "RS", "ltr", 0, [run("A", 2, 0), run("B", 2, 2)]),
    p("Row 2", "RS", "ltr", 1, [run("A", 4, 0)]),
]


def ev(t, row, run, kind="advance"):
    return {"t": t, "row": row, "run": run, "kind": kind}


PROGRESS_BASIC_EVENTS = [
    ev("2026-09-12T18:00:00Z", 2, 0),
    ev("2026-09-12T18:05:00Z", 3, 0),
    ev("2026-09-12T18:10:00Z", 3, 1),
    ev("2026-09-12T19:00:00Z", 3, 2),
    ev("2026-09-12T19:02:00Z", 3, 1, "back"),
    ev("2026-09-12T19:04:00Z", 3, 2),
    ev("2026-09-13T10:00:00Z", 5, 0, "jump"),
    ev("2026-09-13T10:15:00Z", 5, 1),
]
PROGRESS_BASIC_EXPECTED = {
    "percent": 34.5,
    "cells_done": 58,
    "total_cells": 168,
    "stitches_done": 58,
    "total_stitches": 168,
    "sessions": [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:10:00Z", "cells": 30, "stitches": 30},
        {"start": "2026-09-12T19:00:00Z", "end": "2026-09-12T19:04:00Z", "cells": 10, "stitches": 10},
        {"start": "2026-09-13T10:00:00Z", "end": "2026-09-13T10:15:00Z", "cells": 18, "stitches": 18},
    ],
    "active_seconds": 1740,
    "stitches_per_hour": 120.0,
}


def progress_fixtures(charts: dict) -> dict[str, tuple[dict, dict]]:
    """name -> (progress doc, expected summary). Each names the chart fixture it runs against."""
    minimal = charts["minimal-rows"][0]
    doc = {
        "schema": 1,
        "pattern_id": "minimal",
        "chart_id": minimal["chart"]["id"],
        "pattern_version": "1.0.0",
        "cursor": {"row": 5, "run": 1},
        "started": "2026-09-12T18:00:00Z",
        "finished": None,
        "events": PROGRESS_BASIC_EVENTS,
        "ext": {"fixture": {"chart": "minimal-rows"}},
    }
    return {"progress-basic": (doc, PROGRESS_BASIC_EXPECTED)}


def canonical_passes(passes) -> bytes:
    return json.dumps(passes, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def fixtures() -> dict[str, tuple[dict, dict | None]]:
    """name -> (chart doc, expected sequence file content or None)."""
    craigh = json.loads(
        (ROOT / "patterns" / "craigh-na-dun" / "dist" / "chart.json").read_text(encoding="utf-8")
    )
    return {
        "minimal-rows": (
            chart("minimal", "Minimal", MINIMAL_PALETTE, MINIMAL_ROWS, ROWS_T),
            {"passes": MINIMAL_ROWS_SEQ},
        ),
        "minimal-rounds": (
            chart("minimal", "Minimal", MINIMAL_PALETTE, MINIMAL_ROWS, ROUNDS_T),
            {"passes": MINIMAL_ROUNDS_SEQ},
        ),
        "two-letter-codes": (
            chart("two-letter-codes", "Two-letter codes", TWO_LETTER_PALETTE, TWO_LETTER_ROWS, ROWS_T),
            {"passes": TWO_LETTER_SEQ},
        ),
        "layers-stitch": (
            chart(
                "layers-stitch",
                "Layers (stitch)",
                TWO_LETTER_PALETTE,
                TWO_LETTER_ROWS,
                ROWS_T,
                layers=STITCH_LAYER,
            ),
            {"passes": LAYERS_STITCH_SEQ},
        ),
        "explicit-passes": (
            chart(
                "explicit-passes",
                "Explicit passes",
                [("A", "#000000"), ("B", "#ffffff")],
                ["2A2B", "4A"],
                {"type": "none"},
                EXPLICIT_PASSES,
            ),
            {"passes": EXPLICIT_PASSES},
        ),
        "unknown-technique": (
            chart(
                "unknown-technique",
                "Unknown technique",
                [("A", "#000000")],
                ["3A", "3A"],
                {"type": "tunisian"},
            ),
            None,
        ),
        "craigh-na-dun": (craigh, {"sha256": hashlib.sha256(canonical_passes(sequence(craigh))).hexdigest()}),
    }


def dump(obj) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def main(out_dir: Path) -> None:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    charts = fixtures()
    for name, (doc, seq) in charts.items():
        (out_dir / f"{name}.chart.json").write_text(dump(doc), encoding="utf-8")
        if seq is not None:
            (out_dir / f"{name}.sequence.json").write_text(dump(seq), encoding="utf-8")
    for name, (doc, expected) in progress_fixtures(charts).items():
        (out_dir / f"{name}.progress.json").write_text(dump(doc), encoding="utf-8")
        (out_dir / f"{name}.progress.expected.json").write_text(dump(expected), encoding="utf-8")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else HERE)
    print(f"wrote fixtures to {HERE}")
