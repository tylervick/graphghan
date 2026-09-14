import json
from pathlib import Path

import numpy as np
import pytest

from graphghan import chartdoc
from graphghan import grid as gr
from graphghan.export import (
    chart_json,
    decode_rows,
    rle_rows,
    rows_to_strings,
    stats,
    write_dist,
    written_rows,
)
from graphghan.pattern import load_pattern

FIX = Path(__file__).parent / "fixtures" / "minimal"


def small():
    a = np.zeros((3, 5), dtype=np.uint8)
    a[1, 1:4] = 1
    return a


def test_rle_round_trip():
    a = small()
    assert rle_rows(a)[1] == [(0, 1), (1, 3), (0, 1)]
    s = rows_to_strings(a, ["A", "B"])
    assert s == ["5A", "1A3B1A", "5A"]
    assert np.array_equal(decode_rows(s, ["A", "B"]), a)


def test_written_rows_reverse_odd_rows():
    a = small()
    a[2, 0] = 1  # bottom row: B then A
    lines = written_rows(a, ["A", "B"])
    assert lines[0] == "Row 1 (RS): 4 A, 1 B  (5 sts)"  # read right to left
    assert lines[1].startswith("Row 2 (WS): 1 A, 3 B, 1 A")


def test_stats_sum_and_changes():
    gr.set_gauge("sc")
    s = stats(small(), ["A", "B"])
    assert s["stitches"] == 15 and s["counts"] == {"A": 12, "B": 3}
    assert s["color_changes_per_row"]["per_row"] == [0, 2, 0] and s["color_changes_per_row"]["max"] == 2
    assert s["size_in"] == [round(5 / 3.5, 1), 0.8]


def test_stats_always_reports_cells():
    a = small()
    s = stats(a, ["A", "B"])
    assert s["cells"] == a.shape[0] * a.shape[1]
    assert s["stitches"] == s["cells"]


def test_stats_withholds_stitch_numbers_for_a_non_stitch_kind():
    a = small()
    s = stats(a, ["A", "B"], kind="block")
    assert "stitches" not in s
    assert "yards_est" not in s
    assert "skeins_364yd" not in s
    # Cell-counting numbers stay: they are honest whatever a cell is.
    assert s["cells"] == a.shape[0] * a.shape[1]
    assert s["counts"] and s["color_changes_per_row"]


def test_chart_json_schema2_and_write_dist(tmp_path):
    meta = load_pattern(FIX)
    gr.set_gauge("sc")
    doc = chart_json(small(), meta, "sc", {"panel": (1, 1, 4, 2)})
    assert doc["schema"] == 2
    assert doc["pattern"] == {
        "id": "minimal",
        "title": "Minimal",
        "version": "0.0.1",
        "author": "",
        "license": "",
        "dedication": "",
        "quote": "",
        "url": "https://graphghan.milo.cat/patterns/minimal/",
    }
    assert doc["chart"]["width"] == 5 and doc["chart"]["height"] == 3
    assert doc["chart"]["variant"] == "final" and doc["chart"]["gauge_key"] == "sc"
    assert doc["chart"]["id"] == chartdoc.chart_id(["A", "B"], doc["rows"], doc["technique"])
    assert doc["generator"]["name"] == "graphghan" and doc["generator"]["version"]
    assert doc["gauge"] == {
        "stitches": 14,
        "rows": 16,
        "over": {"value": 4, "unit": "in"},
        "stitch": "sc",
        "hook": "5 mm",
        "yarn_weight": "worsted",
    }
    # whole gauge counts are written as ints, so "14" not "14.0" in the JSON
    assert isinstance(doc["gauge"]["stitches"], int) and isinstance(doc["gauge"]["rows"], int)
    assert doc["technique"] == chartdoc.TECHNIQUE_ROWS
    assert doc["palette"][0] == {
        "code": "A",
        "name": "Alpha",
        "hex": "#112233",
        "yarn": {"note": "any"},
        "use": "ground",
    }
    assert doc["instructions"] == [{"title": "Setup", "text": "Chain W + 1 in A."}]
    assert doc["ext"]["graphghan"]["report"] == {"panel": [1, 1, 4, 2]}
    assert "stats" in doc and doc["stats"]["stitches"] == 15
    for gone in ("slug", "title", "size_in", "cell_aspect", "first_row_color", "notes", "report", "stitch"):
        assert gone not in doc
    assert chartdoc.validate_document(doc) == []
    write_dist(small(), meta, "sc", {"panel": (1, 1, 4, 2)}, tmp_path)
    assert json.loads((tmp_path / "chart.json").read_text())["rows"] == ["5A", "1A3B1A", "5A"]
    for name in ("chart.png", "preview.png", "preview-grid.png", "written-rows.txt"):
        assert (tmp_path / name).exists()


def test_chart_json_palette_optional_fields(tmp_path):
    (tmp_path / "pattern.toml").write_text(
        (FIX / "pattern.toml")
        .read_text()
        .replace(
            'use = "ground"', 'use = "ground"\nsymbol = "*"\n[colors.thread]\nsystem = "DMC"\nnumber = "310"'
        )
    )
    meta = load_pattern(tmp_path)
    gr.set_gauge("sc")
    doc = chart_json(small(), meta, "sc", {})
    assert (
        doc["palette"][0]["thread"] == {"system": "DMC", "number": "310"}
        and doc["palette"][0]["symbol"] == "*"
    )
    assert "thread" not in doc["palette"][1] and "symbol" not in doc["palette"][1]


def test_chart_json_keeps_fractional_gauge_counts():
    meta = load_pattern(FIX)
    gr.set_gauge("square")  # 4.0 st/in, 4.0 rows/in -> 16 over 4 in
    try:
        doc = chart_json(small(), meta, "square", {})
        assert doc["gauge"]["stitches"] == 16 and doc["gauge"]["rows"] == 16
        gr.register_gauge("odd", 1.625, 4.0)  # 6.5 sts over 4 in is not whole
        gr.set_gauge("odd")
        doc = chart_json(small(), meta, "odd", {})
        assert doc["gauge"]["stitches"] == 6.5 and doc["gauge"]["rows"] == 16
    finally:
        gr.GAUGES.pop("odd", None)
        gr.set_gauge("sc")


def test_write_dist_validates_before_writing(tmp_path, monkeypatch):
    meta = load_pattern(FIX)
    gr.set_gauge("sc")
    real = chart_json

    def broken(*args, **kwargs):
        doc = real(*args, **kwargs)
        doc["palette"][1]["code"] = "Zz"  # a code no row uses, so every row has an unknown code
        return doc

    monkeypatch.setattr("graphghan.export.chart_json", broken)
    out = tmp_path / "dist"
    with pytest.raises(ValueError, match="chart failed validation"):
        write_dist(small(), meta, "sc", {}, out)
    assert not out.exists()  # nothing written, not even a half-built directory


def test_chart_json_requires_matching_active_gauge():
    meta = load_pattern(FIX)
    gr.set_gauge("square")  # registered by the minimal fixture's pattern.toml
    try:
        with pytest.raises(ValueError):
            chart_json(small(), meta, "sc", {})
    finally:
        gr.set_gauge("sc")


PATTERN_LEVEL = 'stitch = "sc"\ncraft = "crochet"\nterms = "US"\nterms_also = "UK"\nlanguage = "en"'
STITCH_SC = (
    '\n[stitch.sc]\nchain = 1\ncounts_as_stitch = false\nchain_color = "next"\nfirst_stitch_in = 2\n'
    'name = "single crochet"\nunit = "stitches"\n'
)


def _phase1_meta(tmp_path):
    """The minimal fixture with every Phase 1 field authored for sc."""
    src = (FIX / "pattern.toml").read_text().replace('stitch = "sc"', PATTERN_LEVEL) + STITCH_SC
    (tmp_path / "pattern.toml").write_text(src)
    return load_pattern(tmp_path)


def test_chart_json_writes_authored_stitch_fields(tmp_path):
    meta = _phase1_meta(tmp_path)
    gr.set_gauge("sc")
    doc = chart_json(small(), meta, "sc", {})
    assert doc["pattern"]["craft"] == "crochet" and doc["pattern"]["language"] == "en"
    assert doc["gauge"]["unit"] == "stitches"
    assert doc["gauge"]["stitch_name"] == "single crochet"
    assert doc["gauge"]["terms"] == "US" and doc["gauge"]["terms_also"] == "UK"
    assert doc["gauge"]["boundary"] == {
        "kind": "turn",
        "chain": 1,
        "counts_as_stitch": False,
        "color": "next",
    }
    assert doc["foundation"] == {"chain": 6, "first_stitch_in": 2, "note": "in Alpha (A)"}
    assert chartdoc.validate_document(doc) == []
    # the id is a function of codes, rows and technique only: authoring a stitch never moves it
    assert doc["chart"]["id"] == chartdoc.chart_id(["A", "B"], doc["rows"], doc["technique"])


def test_chart_json_omits_unauthored_stitch_fields():
    meta = load_pattern(FIX)
    gr.set_gauge("sc")
    doc = chart_json(small(), meta, "sc", {})
    for key in ("unit", "stitch_name", "terms", "terms_also", "boundary"):
        assert key not in doc["gauge"], key
    for key in ("craft", "language"):
        assert key not in doc["pattern"], key
    assert "foundation" not in doc


def test_chart_json_uses_the_charts_own_gauge_key(tmp_path):
    src = (FIX / "pattern.toml").read_text() + '\n[stitch.square]\nboundary = "join"\nchain = 3\n'
    (tmp_path / "pattern.toml").write_text(src)
    meta = load_pattern(tmp_path)
    gr.set_gauge("square")
    try:
        doc = chart_json(small(), meta, "square", {})
        assert doc["gauge"]["boundary"] == {"kind": "join", "chain": 3}
        assert "foundation" not in doc  # no first_stitch_in authored
    finally:
        gr.set_gauge("sc")


def test_chart_json_foundation_note_from_first_row_color(tmp_path):
    meta = _phase1_meta(tmp_path)  # first_row_color = "A" (Alpha) in the minimal fixture
    gr.set_gauge("sc")
    doc = chart_json(small(), meta, "sc", {})
    assert doc["foundation"]["note"] == "in Alpha (A)"


def test_written_rows_prefix_turning_chain_from_row_two():
    a = small()
    lines = written_rows(a, ["A", "B"], boundary={"kind": "turn", "chain": 1, "counts_as_stitch": False})
    assert lines[0] == "Row 1 (RS): 5 A  (5 sts)"  # the foundation, not a chain, precedes row 1
    assert lines[1] == "Row 2 (WS): ch 1, turn, 1 A, 3 B, 1 A  (5 sts)"
    assert lines[2] == "Row 3 (RS): ch 1, turn, 5 A  (5 sts)"


def test_written_rows_only_turn_kind_adds_a_chain():
    a = small()
    plain = written_rows(a, ["A", "B"])
    assert written_rows(a, ["A", "B"], boundary=None) == plain
    assert written_rows(a, ["A", "B"], boundary={"kind": "join", "chain": 3}) == plain
    assert (
        written_rows(a, ["A", "B"], boundary={"kind": "turn", "chain": 0})[1]
        == "Row 2 (WS): turn, 1 A, 3 B, 1 A  (5 sts)"
    )


def test_write_dist_written_rows_carry_the_chain(tmp_path):
    meta = _phase1_meta(tmp_path)
    gr.set_gauge("sc")
    write_dist(small(), meta, "sc", {}, tmp_path / "dist")
    lines = (tmp_path / "dist" / "written-rows.txt").read_text().splitlines()
    assert lines[0].startswith("Row 1 (RS): 5 A") and lines[1].startswith("Row 2 (WS): ch 1, turn, ")
