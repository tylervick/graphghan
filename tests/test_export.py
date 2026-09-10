import json
from pathlib import Path

import numpy as np

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
    a[2, 0] = 1                      # bottom row: B then A
    lines = written_rows(a, ["A", "B"])
    assert lines[0] == "Row 1 (RS): 4 A, 1 B  (5 sts)"   # read right to left
    assert lines[1].startswith("Row 2 (WS): 1 A, 3 B, 1 A")


def test_stats_sum_and_changes():
    gr.set_gauge("sc")
    s = stats(small(), ["A", "B"])
    assert s["stitches"] == 15 and s["counts"] == {"A": 12, "B": 3}
    assert s["color_changes_per_row"]["per_row"] == [0, 2, 0] and s["color_changes_per_row"]["max"] == 2
    assert s["size_in"] == [round(5 / 3.5, 1), 0.8]


def test_chart_json_schema_and_write_dist(tmp_path):
    meta = load_pattern(FIX)
    gr.set_gauge("sc")
    doc = chart_json(small(), meta, "sc", {"panel": (1, 1, 4, 2)})
    for key in ("schema", "slug", "title", "dedication", "quote", "version", "stitch", "gauge", "cell_aspect",
                "width", "height", "size_in", "palette", "rows", "stats", "notes", "report"):
        assert key in doc
    assert doc["schema"] == 1 and doc["gauge"] == {"st_per_in": 3.5, "rows_per_in": 4.0}
    assert doc["palette"][0] == {"code": "A", "name": "Alpha", "hex": "#112233", "yarn": "any", "use": "ground"}
    write_dist(small(), meta, "sc", {"panel": (1, 1, 4, 2)}, tmp_path)
    assert json.loads((tmp_path / "chart.json").read_text())["rows"] == ["5A", "1A3B1A", "5A"]
    for name in ("chart.png", "preview.png", "preview-grid.png", "written-rows.txt"):
        assert (tmp_path / name).exists()
