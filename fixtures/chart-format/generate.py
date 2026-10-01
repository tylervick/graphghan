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

from graphghan.chartdoc import chart_id, finished_size, sequence, size_derives
from graphghan.export import decode_rows
from graphghan.export import stats as chart_stats
from graphghan.rowsdoc import rows_id

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

ROWS_T = {"type": "rows", "start": "bottom", "first_side": "RS", "rs_direction": "rtl", "turn": True}
ROUNDS_T = {"type": "rounds", "start": "bottom", "first_side": "RS", "rs_direction": "rtl"}
GAUGE = {"stitches": 14.0, "rows": 16.0, "over": {"value": 4, "unit": "in"}, "stitch": "sc"}


def _palette_entry(code, hex_, no_stitch):
    entry = {"code": code, "name": f"Color {code}", "hex": hex_}
    if code == no_stitch:  # schema 3: the ground of a shaped piece (spec 2026-09-25 §5.1)
        entry["stitch"] = False
        entry["use"] = "no stitch"
    return entry


def chart(
    pid, title, palette, rows, technique, passes=None, layers=None, cell=None, gauge=None, no_stitch=None
):
    codes = [c for c, _ in palette]
    width = sum(int(n) for n, _ in re.findall(r"(\d+)([A-Za-z]{1,3})", rows[0]))
    chart_block = {
        "id": chart_id(codes, rows, technique, passes, cell, no_stitch),
        "variant": "final",
        "gauge_key": "sc",
        "width": width,
        "height": len(rows),
    }
    if cell is not None:
        chart_block["cell"] = cell
    doc = {
        "schema": 3 if no_stitch is not None else 2,
        "pattern": {
            "id": pid,
            "title": title,
            "version": "1.0.0",
            "author": "graphghan fixtures",
            "license": "MIT",
        },
        "chart": chart_block,
        "generator": {"name": "graphghan-fixtures", "version": "1"},
        "palette": [_palette_entry(c, h, no_stitch) for c, h in palette],
        "rows": rows,
        "gauge": dict(gauge) if gauge is not None else dict(GAUGE),
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

# The filet-blocks fixture: chart.cell = {"kind": "block"} (docs/research/genres/filet.md). A cell
# here is a filet block (3 dc filled, or dc/ch/skip/dc open), not a stitch, so this pins that a
# reader still opens, works and sequences the chart while every stitch-derived stat disappears.
# The motif is a plain diamond of filled blocks (2, 4, 6, 6, 4, 2 per row) over an open ground, 12
# blocks wide by 6 rows tall -- sized to draw a recognisable diamond, not noise. filet.md's
# "chain multiples of 12 + 3" counts foundation *stitches*, not blocks, and does not justify this
# width; a 12-block row is a different number from a 12-stitch chain multiple.
FILET_PALETTE = [("F", "#2B2F33"), ("O", "#F2E8D5")]
FILET_ROWS = [
    "5O2F5O",
    "4O4F4O",
    "3O6F3O",
    "3O6F3O",
    "4O4F4O",
    "5O2F5O",
]
FILET_CELL = {"kind": "block"}
# Hand-written expected sequence (not produced by chartdoc.sequence, per this module's design
# rule): same rows/RS-rtl/WS-ltr bookkeeping as minimal-rows, worked out by hand from FILET_ROWS.
FILET_ROW_A = [run("O", 5, 0), run("F", 2, 5), run("O", 5, 7)]
FILET_ROW_A_RTL = [run("O", 5, 7), run("F", 2, 5), run("O", 5, 0)]
FILET_ROW_B = [run("O", 4, 0), run("F", 4, 4), run("O", 4, 8)]
FILET_ROW_B_RTL = [run("O", 4, 8), run("F", 4, 4), run("O", 4, 0)]
FILET_ROW_C = [run("O", 3, 0), run("F", 6, 3), run("O", 3, 9)]
FILET_ROW_C_RTL = [run("O", 3, 9), run("F", 6, 3), run("O", 3, 0)]
FILET_SEQ = [
    p("Row 1", "RS", "rtl", 5, FILET_ROW_A_RTL),
    p("Row 2", "WS", "ltr", 4, FILET_ROW_B),
    p("Row 3", "RS", "rtl", 3, FILET_ROW_C_RTL),
    p("Row 4", "WS", "ltr", 2, FILET_ROW_C),
    p("Row 5", "RS", "rtl", 1, FILET_ROW_B_RTL),
    p("Row 6", "WS", "ltr", 0, FILET_ROW_A),
]


def filet_blocks_chart() -> dict:
    codes = [c for c, _ in FILET_PALETTE]
    doc = chart("filet-blocks", "Filet blocks", FILET_PALETTE, FILET_ROWS, ROWS_T, cell=FILET_CELL)
    a = decode_rows(FILET_ROWS, codes)
    # kind="block" has no chartdoc.UNIT_FOR_KIND entry, so its size never derives (#48): sized must
    # follow size_derives(doc), not the sized=True default, or stats.size_in would be a stitch-grid
    # number smuggled onto a chart whose cells are not stitches.
    st = chart_stats(a, codes, kind="block", sized=size_derives(doc))
    doc["stats"] = st
    return doc


# The tiles-gauge fixture: chart.cell = {"kind": "tile"} and gauge.unit = "tiles", the "5.5 tiles =
# 4 in" figure from docs/research/genres/c2c.md (Make & Do Crew's C2C blanket gauge, quoted there
# against Bernat's stitch gauge for the same genre). A tile here is a C2C block, not a stitch, so a
# finished size derives only because the gauge and the grid agree they are both counting tiles
# (#48); removing chart.cell reverts the cell kind to the "stitch" default and withholds it. No
# `stats` block: this helper does not call export.stats for the small fixtures, and hand-computing
# size_in here would repeat the hand-arithmetic trap #48 already hit once (filet-blocks) -- the
# derivation is pinned directly against chartdoc.finished_size in tests/test_conformance.py. The
# grid is a plain diagonal (bottom-left to top-right), evoking the diagonal C2C works in without
# claiming to encode C2C's real construction (technique.type: "c2c" is reserved, docs/research/
# genres/c2c.md); it sequences as ordinary rows.
TILES_GAUGE = {"stitches": 5.5, "rows": 5.5, "over": {"value": 4, "unit": "in"}, "unit": "tiles"}
TILES_PALETTE = [("A", "#F2E8D5"), ("B", "#1E4D3A")]
TILES_ROWS = [
    "1B5A",
    "1A1B4A",
    "2A1B3A",
    "3A1B2A",
    "4A1B1A",
    "5A1B",
]
TILES_CELL = {"kind": "tile"}
# Hand-written expected sequence (not produced by chartdoc.sequence, per this module's design
# rule): same rows/RS-rtl/WS-ltr bookkeeping as minimal-rows, worked out by hand from TILES_ROWS.
TILES_SEQ = [
    p("Row 1", "RS", "rtl", 5, [run("B", 1, 5), run("A", 5, 0)]),
    p("Row 2", "WS", "ltr", 4, [run("A", 4, 0), run("B", 1, 4), run("A", 1, 5)]),
    p("Row 3", "RS", "rtl", 3, [run("A", 2, 4), run("B", 1, 3), run("A", 3, 0)]),
    p("Row 4", "WS", "ltr", 2, [run("A", 2, 0), run("B", 1, 2), run("A", 3, 3)]),
    p("Row 5", "RS", "rtl", 1, [run("A", 4, 2), run("B", 1, 1), run("A", 1, 0)]),
    p("Row 6", "WS", "ltr", 0, [run("B", 1, 0), run("A", 5, 1)]),
]

# The shaped-basic fixture (chart schema 3, spec 2026-09-25 §5.1, #37): Orca's shape at toy size.
# N is the ground no one stitches. Pass 1 is 3 stitches, grows one at each edge twice, loses one
# at the start of pass 4 (an asymmetric row), and narrows to 3 on pass 5 -- so the shaping file
# pins +, -, 0 and a two-cell change, in both reading directions.
SHAPED_PALETTE = [("A", "#112233"), ("B", "#ffffff"), ("N", "#a4dade")]
SHAPED_ROWS = ["2N3A2N", "1N2A1B3A", "3A1B3A", "1N5A1N", "2N3A2N"]
SHAPED_WRITTEN = [
    "R 1: ch 4, from the second chain from the hook, 3 sc [3]",
    "R 2: ch 1, turn, 1 inc, 1 sc, 1 inc [5]",
    "R 3: ch 1, turn, 1 inc, 1 sc, (B) 1 sc, (A) 1 sc, 1 inc [7]",
    "R 4: ch 1, turn, 1 dec, 1 sc, (B) 1 sc, (A) 3 sc [6]",
    "R 5: sl st across 2, ch 1, 3 sc, leave 1 unworked [3]",
]
# Hand-written expected sequence and shaping, worked out from SHAPED_ROWS as the other fixtures are.
SHAPED_SEQ = [
    p("Row 1", "RS", "rtl", 4, [run("A", 3, 2)]),
    p("Row 2", "WS", "ltr", 3, [run("A", 5, 1)]),
    p("Row 3", "RS", "rtl", 2, [run("A", 3, 4), run("B", 1, 3), run("A", 3, 0)]),
    p("Row 4", "WS", "ltr", 1, [run("A", 2, 1), run("B", 1, 3), run("A", 3, 4)]),
    p("Row 5", "RS", "rtl", 0, [run("A", 3, 2)]),
]
SHAPED_SHAPING = [
    None,
    {"start": 1, "end": 1},
    {"start": 1, "end": 1},
    {"start": -1, "end": 0},
    {"start": -2, "end": -1},
]


def shaped_basic_chart() -> dict:
    codes = [c for c, _ in SHAPED_PALETTE]
    doc = chart("shaped-basic", "Shaped basic", SHAPED_PALETTE, SHAPED_ROWS, ROWS_T, no_stitch="N")
    doc["foundation"] = {"chain": 4, "first_stitch_in": 2}
    doc["written"] = SHAPED_WRITTEN
    a = decode_rows(SHAPED_ROWS, codes)
    doc["stats"] = chart_stats(a, codes, sized=size_derives(doc), no_stitch=codes.index("N"))
    return doc


# The pieces-basic fixture (spec 2026-09-25 §5.2-§5.4, §9): a manifest-2 pattern in Orca's shape
# at toy size. `panel` is the shaped-basic chart; `strip` is written rows with a range and every
# count; `fin` is made twice and one of its entries prints no count; `strap` ends "until desired
# length". The directory is a bundle's tree: fixtures/bundle zips it as it stands.
PIECES_DIR = "pieces-basic"


def rows_doc(title, entries, palette=None, pages=None):
    doc = {"schema": 1, "id": rows_id(entries), "piece": {"title": title}}
    if palette:
        doc["palette"] = palette
    doc["rows"] = entries
    if pages:
        doc["source"] = {"pages": pages}
    return doc


STRIP_ROWS = [
    {
        "label": "R 1",
        "from": 1,
        "to": 1,
        "code": "A",
        "count": 6,
        # A curly apostrophe: the rows id hashes UTF-8, so both readers must agree on non-ASCII.
        "text": "(A) ch 7, from the hook’s second chain, 6 sc [6]",
    },
    {"label": "R 2 - R 4", "from": 2, "to": 4, "count": 6, "text": "ch 1, turn, 6 sc [6]"},
    {"label": "R 5", "from": 5, "to": 5, "code": "B", "count": 6, "text": "(B) ch 1, turn, 6 sc [6]"},
]
FIN_ROWS = [
    {
        "label": "R 1",
        "from": 1,
        "to": 1,
        "count": 2,
        "text": "ch 3, from the second chain from the hook, 2 sc [2]",
    },
    {"label": "R 2 - R 3", "from": 2, "to": 3, "text": "ch 1, turn, 1 inc, 1 sc"},
]
STRAP_ROWS = [
    {
        "label": "1.",
        "from": 1,
        "to": 1,
        "count": 6,
        "text": "ch 7, from the second chain from the hook, 6 sc",
    },
    {
        "label": "2.",
        "from": 2,
        "repeat": "until desired length",
        "count": 6,
        "text": "ch 1, turn, 6 sc; repeat until the strap is as long as you want it",
    },
]
PIECES_PALETTE = [
    {"code": "A", "name": "Color A", "hex": "#112233"},
    {"code": "B", "name": "Color B", "hex": "#ffffff"},
]


def pieces_basic() -> dict[str, dict]:
    """relative path -> JSON document, for everything in the pieces-basic tree but the previews."""
    chart = shaped_basic_chart()
    strip = rows_doc("Strip", STRIP_ROWS, PIECES_PALETTE, [3])
    fin = rows_doc("Fin", FIN_ROWS)
    strap = rows_doc("Strap", STRAP_ROWS)
    w, h, unit = finished_size(chart)
    entry = {
        "id": chart["chart"]["id"],
        "variant": "final",
        "gauge_key": "sc",
        "default": True,
        "path": "charts/final-sc/chart.json",
        "preview": "charts/final-sc/preview.png",
        "width": 7,
        "height": 5,
        "size": {"width": w, "height": h, "unit": unit},
        "stitch": "sc",
        # Stitched cells and yarn colours only (chart schema 3): the ground is neither.
        "colors": 2,
        "stitches": 24,
        "changes_per_row": {
            "mean": chart["stats"]["color_changes_per_row"]["mean"],
            "max": chart["stats"]["color_changes_per_row"]["max"],
        },
        "yards_est": int(sum(chart["stats"]["yards_est"].values())),
    }
    manifest = {
        "schema": 2,
        "id": "pieces-basic",
        "title": "Pieces basic",
        "version": "1.0.0",
        "dedication": "",
        "quote": "",
        "author": "graphghan fixtures",
        "license": "MIT",
        "preview": "preview.png",
        "palette": PIECES_PALETTE,
        "charts": [entry],
        "pieces": [
            {"id": "panel", "title": "Panel", "make": 1, "chart": entry["id"], "pages": [2]},
            {
                "id": "strip",
                "title": "Strip",
                "make": 1,
                "rows": "pieces/strip.rows.json",
                "rows_id": strip["id"],
                "pages": [3],
            },
            {"id": "fin", "title": "Fin", "make": 2, "rows": "pieces/fin.rows.json", "rows_id": fin["id"]},
            {
                "id": "strap",
                "title": "Strap",
                "make": 1,
                "rows": "pieces/strap.rows.json",
                "rows_id": strap["id"],
            },
        ],
        "assembly": [
            {
                "title": "Sew the strip round the panel",
                "text": "Whip stitch the strip to the panel's edge, right sides out.",
                "pages": [3],
            },
            {"title": "Pages 4–5", "pages": [4, 5]},
        ],
        "updated": "1980-01-01T00:00:00Z",
    }
    progress_doc = {
        "schema": 2,
        "pattern_id": "pieces-basic",
        "pattern_version": "1.0.0",
        "pieces": [
            {
                "piece": "panel",
                "copy": 1,
                "doc_id": entry["id"],
                "cursor": {"row": 3, "run": 1},
                "finished": None,
            },
            {
                "piece": "strip",
                "copy": 1,
                "doc_id": strip["id"],
                "cursor": {"row": 5, "run": 0},
                "finished": "2026-09-12T19:30:00Z",
            },
            {
                "piece": "fin",
                "copy": 1,
                "doc_id": fin["id"],
                "cursor": {"row": 2, "run": 0},
                "finished": None,
            },
            {
                "piece": "strap",
                "copy": 1,
                "doc_id": strap["id"],
                "cursor": {"row": 10, "run": 0},
                "finished": None,
            },
        ],
        "current": {"piece": "panel", "copy": 1},
        "assembly_done": [0],
        "started": "2026-09-12T18:00:00Z",
        "finished": None,
        "events": [
            {"t": "2026-09-12T18:00:00Z", "piece": "panel", "copy": 1, "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T18:05:00Z", "piece": "panel", "copy": 1, "row": 3, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T18:10:00Z", "piece": "panel", "copy": 1, "row": 3, "run": 1, "kind": "advance"},
            {"t": "2026-09-12T19:00:00Z", "piece": "strip", "copy": 1, "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T19:10:00Z", "piece": "strip", "copy": 1, "row": 5, "run": 0, "kind": "jump"},
            {"t": "2026-09-12T19:30:00Z", "piece": "strip", "copy": 1, "row": 5, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T21:00:00Z", "piece": "fin", "copy": 1, "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T21:02:00Z", "piece": "strap", "copy": 1, "row": 10, "run": 0, "kind": "jump"},
        ],
    }
    return {
        "pattern.json": manifest,
        "charts/final-sc/chart.json": chart,
        "pieces/strip.rows.json": strip,
        "pieces/fin.rows.json": fin,
        "pieces/strap.rows.json": strap,
        "progress.json": progress_doc,
        "progress.expected.json": PIECES_EXPECTED,
    }


# Hand-worked from the progress document above (not produced by summarize_project):
# panel 3+5+3 = 11 of 24 cells; strip finished, 5 of 5 rows, 30 stitches; fin row 2 = 1 of 3
# rows, no stitch figures (one entry has no count); strap row 10 = 9 rows, open, no total.
# Sessions: 18:00-18:10 the panel's 11 cells; 19:00-19:30 the strip's 5 rows (the advance at
# 19:30 leaves row 5 unchanged, so it is the finishing advance and row 5 counts); 21:00-21:02 the
# fin's 1 row and the strap's 9. Pace: 11 chart stitches over the 600 s of the session that
# worked a chart.
PIECES_EXPECTED = {
    "pieces": [
        {
            "piece": "panel",
            "copy": 1,
            "kind": "chart",
            "finished": False,
            "percent": 45.8,
            "cells_done": 11,
            "total_cells": 24,
            "stitches_done": 11,
            "total_stitches": 24,
        },
        {
            "piece": "strip",
            "copy": 1,
            "kind": "rows",
            "finished": True,
            "rows_done": 5,
            "total_rows": 5,
            "percent": 100.0,
            "total_stitches": 30,
            "stitches_done": 30,
        },
        {
            "piece": "fin",
            "copy": 1,
            "kind": "rows",
            "finished": False,
            "rows_done": 1,
            "total_rows": 3,
            "percent": 33.3,
        },
        {"piece": "strap", "copy": 1, "kind": "rows", "finished": False, "rows_done": 9},
    ],
    "pieces_done": 1,
    "pieces_total": 5,
    "assembly_done": 1,
    "assembly_total": 2,
    "sessions": [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:10:00Z", "cells": 11, "rows": 0},
        {"start": "2026-09-12T19:00:00Z", "end": "2026-09-12T19:30:00Z", "cells": 0, "rows": 5},
        {"start": "2026-09-12T21:00:00Z", "end": "2026-09-12T21:02:00Z", "cells": 0, "rows": 10},
    ],
    "active_seconds": 2520,
    "stitches_per_hour": 66.0,
}


# Refusal fixtures (spec §9, fixtures/chart-format/refused/): each mutates shaped-basic exactly one
# way and is otherwise valid -- schema-clean, chart.id recomputed -- so the only reason a reader
# refuses it is the rule named in ext.fixture.refuses. `stats` is dropped: these are not worked.
def _refusal_base() -> dict:
    doc = json.loads(dump(shaped_basic_chart()))
    doc.pop("stats", None)
    return doc


def _recompute_chart_id(doc: dict) -> None:
    """Chart id, width and height after a rows/palette mutation, using the no-stitch code the way
    a reader derives it: the first palette entry marked `"stitch": false` (chartdoc.no_stitch_code)."""
    codes = [p["code"] for p in doc["palette"]]
    ns = next((p["code"] for p in doc["palette"] if p.get("stitch") is False), None)
    doc["chart"]["id"] = chart_id(
        codes, doc["rows"], doc["technique"], doc.get("passes"), doc["chart"].get("cell"), ns
    )
    doc["chart"]["width"] = sum(int(n) for n, _ in re.findall(r"(\d+)([A-Za-z]{1,3})", doc["rows"][0]))
    doc["chart"]["height"] = len(doc["rows"])


def _refuses(name: str, mutate) -> dict:
    doc = _refusal_base()
    mutate(doc)
    _recompute_chart_id(doc)
    doc["ext"] = {"fixture": {"refuses": name}}
    return doc


def refused_fixtures() -> dict[str, dict]:
    """name -> chart doc for fixtures/chart-format/refused/ (spec §9)."""

    def gap_in_row(d):
        d["rows"][0] = "1A1N5A"

    def row_without_stitches(d):
        d["rows"][0] = "7N"

    def two_no_stitch_codes(d):
        for p in d["palette"]:
            if p["code"] == "B":
                p["stitch"] = False

    def foundation_too_short(d):
        d["foundation"] = {"chain": 3, "first_stitch_in": 2}

    def written_wrong_length(d):
        d["written"] = d["written"][:1]

    return {
        "gap-in-row": _refuses("gap-in-row", gap_in_row),
        "row-without-stitches": _refuses("row-without-stitches", row_without_stitches),
        "two-no-stitch-codes": _refuses("two-no-stitch-codes", two_no_stitch_codes),
        "foundation-too-short": _refuses("foundation-too-short", foundation_too_short),
        "written-wrong-length": _refuses("written-wrong-length", written_wrong_length),
    }


def pieces_refused_fixtures(manifest: dict) -> dict[str, dict]:
    """file name (with its own extension) -> doc, for the pieces-basic refusals (spec §5.2, §5.3,
    §9): a rows gap, an open-ended entry that is not last, and a piece naming a chart not in
    `charts`; a chart no piece names; and a default chart that is not the first chart piece's
    (#228). `manifest` is pieces_basic()["pattern.json"]."""
    missing_chart = json.loads(json.dumps(manifest))
    missing_chart["pieces"][0]["chart"] = "sha256:" + "0" * 64

    # A second chart entry, not the default; nothing else about it is wrong.
    def extra_chart(doc: dict) -> dict:
        extra = dict(
            doc["charts"][0],
            id="sha256:" + "1" * 64,
            variant="extra",
            default=False,
            path="charts/extra-sc/chart.json",
            preview="charts/extra-sc/preview.png",
        )
        doc["charts"].append(extra)
        return extra

    unnamed_chart = json.loads(json.dumps(manifest))
    extra_chart(unnamed_chart)

    default_not_first = json.loads(json.dumps(manifest))
    lid = extra_chart(default_not_first)
    default_not_first["pieces"].insert(0, {"id": "lid", "title": "Lid", "make": 1, "chart": lid["id"]})
    return {
        # The strip's palette, so the gap is the only thing wrong with it.
        "rows-gap.rows.json": rows_doc("Gap", [STRIP_ROWS[0], STRIP_ROWS[2]], PIECES_PALETTE),
        "rows-open-not-last.rows.json": rows_doc("Open", [dict(STRAP_ROWS[1], **{"from": 1}), STRIP_ROWS[1]]),
        "piece-names-missing-chart.pattern.json": missing_chart,
        "chart-no-piece-names.pattern.json": unnamed_chart,
        "default-not-first-chart-piece.pattern.json": default_not_first,
    }


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

PROGRESS_STITCH_EVENTS = [
    {"t": "2026-09-12T18:00:00Z", "row": 1, "run": 0, "stitch": 10, "kind": "advance"},  # ten of the 14
    {
        "t": "2026-09-12T18:00:30Z",
        "row": 1,
        "run": 1,
        "kind": "advance",
    },  # the boundary position: row worked, not turned
    {"t": "2026-09-12T18:01:00Z", "row": 2, "run": 0, "kind": "advance"},  # turned
    {"t": "2026-09-12T18:01:30Z", "row": 1, "run": 1, "kind": "back"},  # back to the boundary
    {"t": "2026-09-12T18:02:00Z", "row": 2, "run": 0, "kind": "advance"},
    {"t": "2026-09-12T19:00:00Z", "row": 3, "run": 1, "stitch": 5, "kind": "jump"},  # a jump into a run
    {"t": "2026-09-12T19:03:00Z", "row": 3, "run": 2, "kind": "advance"},  # the step that completes it
]

PROGRESS_STITCH_EXPECTED = {
    "percent": 23.8,
    "cells_done": 40,
    "total_cells": 168,
    "stitches_done": 40,
    "total_stitches": 168,
    "sessions": [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:02:00Z", "cells": 14, "stitches": 14},
        {"start": "2026-09-12T19:00:00Z", "end": "2026-09-12T19:03:00Z", "cells": 26, "stitches": 26},
    ],
    "active_seconds": 300,
    "stitches_per_hour": 480.0,
}

# A cursor on the shaped chart: 3 + 5 cells of passes 1-2 and pass 3's first run of 3 are done,
# of 24 stitched cells -- the ground never enters the denominator.
PROGRESS_SHAPED_EVENTS = [
    ev("2026-09-12T18:00:00Z", 2, 0),
    ev("2026-09-12T18:05:00Z", 3, 0),
    ev("2026-09-12T18:10:00Z", 3, 1),
]
PROGRESS_SHAPED_EXPECTED = {
    "percent": 45.8,
    "cells_done": 11,
    "total_cells": 24,
    "stitches_done": 11,
    "total_stitches": 24,
    "sessions": [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:10:00Z", "cells": 11, "stitches": 11},
    ],
    "active_seconds": 600,
    "stitches_per_hour": 66.0,
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
    stitch_doc = {
        "schema": 1,
        "pattern_id": "minimal",
        "chart_id": minimal["chart"]["id"],
        "pattern_version": "1.0.0",
        "cursor": {"row": 3, "run": 2},
        "started": "2026-09-12T18:00:00Z",
        "finished": None,
        "events": PROGRESS_STITCH_EVENTS,
        "ext": {"fixture": {"chart": "minimal-rows"}},
    }
    shaped_chart = charts["shaped-basic"][0]
    shaped_doc = {
        "schema": 1,
        "pattern_id": "shaped-basic",
        "chart_id": shaped_chart["chart"]["id"],
        "pattern_version": "1.0.0",
        "cursor": {"row": 3, "run": 1},
        "started": "2026-09-12T18:00:00Z",
        "finished": None,
        "events": PROGRESS_SHAPED_EVENTS,
        "ext": {"fixture": {"chart": "shaped-basic"}},
    }
    return {
        "progress-basic": (doc, PROGRESS_BASIC_EXPECTED),
        "progress-stitch": (stitch_doc, PROGRESS_STITCH_EXPECTED),
        "progress-shaped": (shaped_doc, PROGRESS_SHAPED_EXPECTED),
    }


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
        "filet-blocks": (
            filet_blocks_chart(),
            {"passes": FILET_SEQ},
        ),
        "tiles-gauge": (
            chart(
                "tiles-gauge",
                "Tiles gauge",
                TILES_PALETTE,
                TILES_ROWS,
                ROWS_T,
                cell=TILES_CELL,
                gauge=TILES_GAUGE,
            ),
            {"passes": TILES_SEQ},
        ),
        "shaped-basic": (shaped_basic_chart(), {"passes": SHAPED_SEQ}),
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
    (out_dir / "shaped-basic.shaping.json").write_text(dump({"shaping": SHAPED_SHAPING}), encoding="utf-8")
    refused_dir = out_dir / "refused"
    refused_dir.mkdir(parents=True, exist_ok=True)
    for name, doc in refused_fixtures().items():
        (refused_dir / f"{name}.chart.json").write_text(dump(doc), encoding="utf-8")
    pieces_dir = out_dir / PIECES_DIR
    basic = pieces_basic()
    for rel, doc in basic.items():
        path = pieces_dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(dump(doc), encoding="utf-8")
    for name, doc in pieces_refused_fixtures(basic["pattern.json"]).items():
        (refused_dir / name).write_text(dump(doc), encoding="utf-8")


if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else HERE)
    print(f"wrote fixtures to {HERE}")
