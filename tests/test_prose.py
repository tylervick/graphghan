"""prose.json: the mapping from written rows to the grid, the checks that name rows, the cross-check."""

import json
from pathlib import Path

import jsonschema
import numpy as np
import pytest

from graphghan import prose

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "schema" / "import-prose.schema.json").read_text(encoding="utf-8"))
CODES = ["A", "B", "C"]

# A 5-wide, 4-tall chart in display order (top row first), as palette indexes.
DISPLAY = np.array(
    [
        [0, 0, 1, 0, 0],
        [0, 1, 1, 1, 0],
        [2, 0, 1, 0, 2],
        [0, 0, 0, 0, 0],
    ],
    dtype=np.uint8,
)


def runs_of(cells):
    out = []
    for c in cells:
        if out and out[-1][0] == CODES[c]:
            out[-1][1] += 1
        else:
            out.append([CODES[c], 1])
    return out


def written(row1):
    """The written rows a pattern with this row-1 corner would print for DISPLAY."""
    rows = []
    h = DISPLAY.shape[0]
    for k in range(1, h + 1):
        y = h - k if row1.startswith("bottom") else k - 1
        cells = list(DISPLAY[y])
        if prose.reads_right_to_left(k, row1):
            cells.reverse()
        rows.append({"row": k, "runs": runs_of(cells), "text": f"Row {k}"})
    return rows


def validate(doc):
    jsonschema.validate(doc, SCHEMA)
    assert prose.check_prose(doc) == []


@pytest.mark.parametrize("row1", prose.ROW1_POSITIONS)
def test_written_rows_map_back_from_every_corner(row1):
    doc = {
        "schema": prose.SCHEMA_ID,
        "chart": {"row1": row1, "width": 5, "height": 4},
        "written_rows": written(row1),
    }
    validate(doc)
    grid, problems = prose.written_to_grid(doc["written_rows"], CODES, 5, 4, row1)
    assert problems == [] and np.array_equal(grid, DISPLAY)


def test_bottom_right_reverses_odd_rows_only():
    rows = written("bottom-right")
    assert rows[0]["runs"] == [["A", 5]]  # row 1 = bottom row, all A
    assert rows[1]["runs"] == [["C", 1], ["A", 1], ["B", 1], ["A", 1], ["C", 1]]  # row 2 (WS) left to right
    assert rows[2]["runs"] == [["A", 1], ["B", 3], ["A", 1]]  # row 3 (RS) read right to left, symmetric here
    assert rows[3]["runs"] == [["A", 2], ["B", 1], ["A", 2]]  # row 4 = top row, left to right


def test_a_bad_total_names_the_row_and_quotes_the_text():
    rows = written("bottom-right")
    rows[1]["runs"] = [["A", 1], ["B", 3], ["A", 2]]
    rows[1]["page"] = 3
    rows[1]["text"] = "Row 2: 1 A, 3 B, 2 A"
    grid, problems = prose.written_to_grid(rows, CODES, 5, 4)
    assert grid is None
    assert problems == ['row 2: runs sum to 6, chart width is 5 (page 3: "Row 2: 1 A, 3 B, 2 A")']


def test_a_printed_total_that_disagrees_is_named():
    rows = written("bottom-right")
    rows[0]["total"] = 6
    assert prose.row_total_problems(rows, 5) == [
        'row 1: runs sum to 5 but the pattern prints 6 sts ("Row 1")'
    ]


def test_duplicate_and_missing_rows_are_named():
    rows = written("bottom-right")
    rows.append(dict(rows[1]))  # row 2 twice
    del rows[2]  # row 3 gone
    _, problems = prose.written_to_grid(rows, CODES, 5, 4)
    assert "row 2 printed twice" in problems and "missing rows 3 of 4" in problems


def test_unknown_code_is_named():
    rows = written("bottom-right")
    rows[0]["runs"] = [["Q", 5]]
    _, problems = prose.written_to_grid(rows, CODES, 5, 4)
    assert problems == ["row 1 uses code 'Q', not in the palette ['A', 'B', 'C'] (\"Row 1\")"]


def test_cross_check_reports_a_row_and_its_first_column():
    other = DISPLAY.copy()
    other[1, 3] = 2  # display row 1 = written row 3 (bottom-right), column from the right = 5 - 3 = 2
    mismatches, error = prose.cross_check(DISPLAY, other)
    assert mismatches == ["row 3: 1 cell(s) differ from the chart, first at column 2"] and error is None


def test_cross_check_flags_a_flipped_orientation():
    mismatches, error = prose.cross_check(DISPLAY, DISPLAY[::-1])
    assert len(mismatches) == 4 and error and "flipped top to bottom" in error


def test_cross_check_size_mismatch_is_an_error():
    _, error = prose.cross_check(DISPLAY, DISPLAY[:, :4])
    assert error == "written rows give 5x4, the chart reads 4x4"


def test_gauge_and_size_convert_to_inches():
    assert prose.gauge_per_inch({"stitches": 20, "rows": 20, "over": {"value": 10, "unit": "cm"}}) == (
        5.08,
        5.08,
    )
    assert prose.gauge_per_inch({"stitches": 14, "rows": 16, "over": {"value": 4, "unit": "in"}}) == (
        3.5,
        4.0,
    )
    assert prose.gauge_per_inch({"stitches": 14}) is None
    assert prose.size_inches({"width": 40, "height": 16, "unit": "cm"}) == (15.7, 6.3)
    assert prose.gauge_key({"stitch_name": "Single Crochet"}) == "sc"
    assert prose.gauge_key({"stitch": "hbdc"}) == "hbdc"


def test_check_prose_names_what_is_wrong():
    doc = {
        "schema": "nope",
        "palette": [{"code": "toolong"}, {"code": "A", "hex": "red"}],
        "chart": {"row1": "middle"},
        "written_rows": [{"row": 0, "runs": [["A", 0]]}],
    }
    problems = prose.check_prose(doc)
    assert any("schema must be" in p for p in problems)
    assert any("palette[0].code" in p for p in problems) and any("palette[1].hex" in p for p in problems)
    assert any("chart.row1" in p for p in problems) and any("written_rows[0].row" in p for p in problems)
    assert any("runs[0]" in p for p in problems)


def test_meta_from_prose_carries_the_pattern_toml_fields():
    doc = {
        "schema": prose.SCHEMA_ID,
        "pattern": {"title": "Orca Bag", "author": "Jin", "terms": "US"},
        "gauge": {
            "stitches": 20,
            "rows": 20,
            "over": {"value": 10, "unit": "cm"},
            "stitch_name": "single crochet",
            "hook": "3 mm",
            "boundary": {"kind": "turn", "chain": 1},
        },
        "finished_size": {"width": 40, "height": 16, "unit": "cm"},
        "notes": {"setup": ["Start at the bottom."]},
        "uncertain": ["row 30 wraps"],
    }
    validate(doc)
    meta = prose.meta_from_prose(doc)
    assert meta["title"] == "Orca Bag" and meta["gauge"] == (5.08, 5.08) and meta["stitch"] == "sc"
    assert (
        meta["hook"] == "3 mm"
        and meta["size_in"] == (15.7, 6.3)
        and meta["boundary"] == {"kind": "turn", "chain": 1}
    )
    assert meta["notes"]["setup"] == ["Start at the bottom."] and meta["uncertain"] == ["row 30 wraps"]
