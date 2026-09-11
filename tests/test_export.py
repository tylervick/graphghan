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
        "stitches": 14.0,
        "rows": 16.0,
        "over": {"value": 4, "unit": "in"},
        "stitch": "sc",
        "hook": "5 mm",
        "yarn_weight": "worsted",
    }
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


def test_chart_json_requires_matching_active_gauge():
    meta = load_pattern(FIX)
    gr.set_gauge("square")  # registered by the minimal fixture's pattern.toml
    try:
        with pytest.raises(ValueError):
            chart_json(small(), meta, "sc", {})
    finally:
        gr.set_gauge("sc")
