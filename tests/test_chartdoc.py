import hashlib
import json

import pytest

from graphghan import chartdoc


def doc(rows, codes=("A", "B"), technique=None, passes=None, width=None, layers=None):
    technique = technique or dict(chartdoc.TECHNIQUE_ROWS)
    d = {
        "schema": 2,
        "pattern": {"id": "t", "title": "T", "version": "0.0.1"},
        "chart": {
            "id": chartdoc.chart_id(list(codes), rows, technique, passes),
            "width": width or 4,
            "height": len(rows),
        },
        "palette": [{"code": c, "name": c, "hex": "#000000"} for c in codes],
        "rows": rows,
        "gauge": {"stitches": 14, "rows": 16, "over": {"value": 4, "unit": "in"}, "stitch": "sc"},
        "technique": technique,
    }
    if passes is not None:
        d["passes"] = passes
    if layers is not None:  # layers never enter chart.id
        d["layers"] = layers
    return d


def test_parse_runs_multi_letter_codes():
    assert chartdoc.parse_runs("7Gd2G3Y") == [("Gd", 7), ("G", 2), ("Y", 3)]
    assert chartdoc.parse_runs("7YB") == [("YB", 7)]


def test_chart_id_is_canonical_sha256_and_ignores_names():
    rows = ["2A2B", "4A"]
    t = dict(chartdoc.TECHNIQUE_ROWS)
    canonical = json.dumps(
        {"codes": ["A", "B"], "rows": rows, "technique": t},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    assert chartdoc.chart_id(["A", "B"], rows, t) == "sha256:" + hashlib.sha256(canonical).hexdigest()
    assert chartdoc.chart_id(["A", "B"], rows, t) != chartdoc.chart_id(["A", "C"], rows, t)
    assert chartdoc.chart_id(["A", "B"], rows, t, passes=[]) != chartdoc.chart_id(["A", "B"], rows, t)


def test_sequence_rows_bottom_start_alternates_side_and_direction():
    passes = chartdoc.sequence(doc(["4A", "1A2B1A", "4B"]))
    assert [p["label"] for p in passes] == ["Row 1", "Row 2", "Row 3"]
    assert passes[0] == {
        "label": "Row 1",
        "side": "RS",
        "direction": "rtl",
        "grid_row": 2,
        "runs": [{"code": "B", "count": 4, "x0": 0}],
    }
    assert passes[1]["side"] == "WS" and passes[1]["direction"] == "ltr" and passes[1]["grid_row"] == 1
    assert passes[1]["runs"] == [
        {"code": "A", "count": 1, "x0": 0},
        {"code": "B", "count": 2, "x0": 1},
        {"code": "A", "count": 1, "x0": 3},
    ]
    assert passes[2]["runs"] == [{"code": "A", "count": 4, "x0": 0}] and passes[2]["side"] == "RS"


def test_sequence_rows_rtl_reverses_runs_but_keeps_x0():
    passes = chartdoc.sequence(doc(["1A2B1A"]))
    assert passes[0]["runs"] == [
        {"code": "A", "count": 1, "x0": 3},
        {"code": "B", "count": 2, "x0": 1},
        {"code": "A", "count": 1, "x0": 0},
    ]


def test_sequence_rows_top_start_and_ws_first():
    t = {"type": "rows", "start": "top", "first_side": "WS", "rs_direction": "rtl", "turn": True}
    passes = chartdoc.sequence(doc(["4A", "4B"], technique=t))
    assert passes[0]["grid_row"] == 0 and passes[0]["side"] == "WS" and passes[0]["direction"] == "ltr"
    assert passes[1]["grid_row"] == 1 and passes[1]["side"] == "RS" and passes[1]["direction"] == "rtl"


def test_sequence_rounds_same_side_every_pass():
    t = {"type": "rounds", "start": "bottom", "first_side": "RS", "rs_direction": "rtl"}
    passes = chartdoc.sequence(doc(["4A", "4B"], technique=t))
    assert [p["label"] for p in passes] == ["Round 1", "Round 2"]
    assert all(p["side"] == "RS" and p["direction"] == "rtl" for p in passes)


def test_sequence_explicit_passes_override_and_normalize():
    explicit = [{"label": "Row 1", "runs": [{"code": "A", "count": 2}, {"code": "B", "count": 2}]}]
    passes = chartdoc.sequence(doc(["2A2B"], technique={"type": "none"}, passes=explicit))
    assert passes == [
        {
            "label": "Row 1",
            "side": None,
            "direction": None,
            "grid_row": None,
            "runs": [{"code": "A", "count": 2, "x0": None}, {"code": "B", "count": 2, "x0": None}],
        }
    ]


@pytest.mark.parametrize("ttype", ["none", "c2c", "tunisian"])
def test_sequence_unknown_or_reserved_technique_raises(ttype):
    with pytest.raises(chartdoc.UnsupportedTechnique):
        chartdoc.sequence(doc(["4A"], technique={"type": ttype}))


def test_validate_document_ok():
    assert chartdoc.validate_document(doc(["2A2B", "4A"])) == []


def test_validate_document_reports_problems():
    d = doc(["2A2B", "4A"])
    d["rows"][1] = "3A"
    d["chart"]["id"] = "sha256:" + "0" * 64
    d["palette"].append({"code": "A", "name": "dup", "hex": "#000000"})
    d["palette"][0]["hex"] = "red"
    problems = chartdoc.validate_document(d)
    assert any("row 1" in p and "3" in p for p in problems)  # sums to 3, not 4
    assert any("chart.id" in p for p in problems)
    assert any("duplicate" in p for p in problems)
    assert any("hex" in p for p in problems)


def test_validate_document_unknown_code_and_height():
    d = doc(["2A2C"])
    d["chart"]["height"] = 5
    problems = chartdoc.validate_document(d)
    assert any("'C'" in p for p in problems) and any("height" in p for p in problems)


def test_validate_document_checks_explicit_passes():
    explicit = [
        {
            "label": "Row 1",
            "grid_row": 0,
            "runs": [{"code": "A", "count": 2, "x0": 0}, {"code": "B", "count": 2, "x0": 1}],
        }
    ]
    d = doc(["2A2B"], technique={"type": "none"}, passes=explicit)
    problems = chartdoc.validate_document(d)
    assert any("passes[0].runs[1]" in p for p in problems)  # x0=1 is an A cell, not B
    explicit[0]["runs"][1]["x0"] = 2
    d = doc(["2A2B"], technique={"type": "none"}, passes=explicit)
    assert chartdoc.validate_document(d) == []


def test_validate_document_never_raises_on_malformed_passes():
    # (a) a run missing "count" -- must be reported, not KeyError'd, and must mention "count"
    d = doc(
        ["2A"],
        width=2,
        technique={"type": "none"},
        passes=[{"label": "Row 1", "grid_row": 0, "runs": [{"code": "A", "x0": 0}]}],
    )
    problems = chartdoc.validate_document(d)
    assert problems and any("count" in p for p in problems)

    # (b) a run that is a string, not an object
    d = doc(
        ["2A"],
        width=2,
        technique={"type": "none"},
        passes=[{"label": "Row 1", "grid_row": 0, "runs": ["bad"]}],
    )
    assert chartdoc.validate_document(d)

    # (c) "runs" that is a dict, not a list
    d = doc(
        ["2A"],
        width=2,
        technique={"type": "none"},
        passes=[{"label": "Row 1", "grid_row": 0, "runs": {"code": "A", "count": 2, "x0": 0}}],
    )
    assert chartdoc.validate_document(d)

    # (d) count = "7" (a string, not an int) -- must be reported and must mention "count"
    d = doc(
        ["2A"],
        width=2,
        technique={"type": "none"},
        passes=[{"label": "Row 1", "grid_row": 0, "runs": [{"code": "A", "count": "7", "x0": 0}]}],
    )
    problems = chartdoc.validate_document(d)
    assert problems and any("count" in p for p in problems)

    # (e) grid_row = "0" (a string, not an int): the malformed run itself must not
    # crash (the type guard treats it as absent and skips the cell check); mutating
    # it in after construction also leaves chart.id stale, which is what surfaces
    # the non-empty problems list here.
    d = doc(
        ["2A"],
        width=2,
        technique={"type": "none"},
        passes=[{"label": "Row 1", "grid_row": 0, "runs": [{"code": "A", "count": 2, "x0": 0}]}],
    )
    d["passes"][0]["grid_row"] = "0"
    assert chartdoc.validate_document(d)


def test_validate_document_short_row_with_in_width_pass_is_reported_not_raised():
    # The pass fits chart.width but not the row as written: bounding on width alone indexed off
    # the end of the parsed row and raised IndexError.
    d = doc(
        ["2A"],
        width=4,
        technique={"type": "none"},
        passes=[{"label": "Row 1", "grid_row": 0, "runs": [{"code": "A", "count": 4, "x0": 0}]}],
    )
    problems = chartdoc.validate_document(d)
    assert "passes[0].runs[0] lies outside the grid" in problems


def test_validate_document_non_object_palette_entry_is_reported():
    d = doc(["4A"])
    d["palette"][1] = "B"  # a bare string where an object belongs
    problems = chartdoc.validate_document(d)
    assert "palette[1] is not an object" in problems


def test_validate_document_two_codeless_entries_are_not_duplicates():
    d = doc(["4A"])
    del d["palette"][0]["code"]
    del d["palette"][1]["code"]
    problems = chartdoc.validate_document(d)
    assert sum("is not 1-3 letters" in p for p in problems) == 2
    assert not any("duplicate" in p for p in problems)


def test_validate_document_checks_layers():
    rows = ["2A2B", "4A"]

    def layer(legend, lrows):
        return {"stitch": {"legend": legend, "rows": lrows}}

    knit = {"k": "knit", "p": "purl"}
    assert chartdoc.validate_document(doc(rows, layers=layer(knit, ["4k", "2k2p"]))) == []
    cases = {
        "layers.stitch has 1 rows, chart has 2": layer(knit, ["4k"]),
        "layers.stitch row 1 is not a run string": layer(knit, ["4k", "k4"]),
        "layers.stitch row 1 does not sum to chart.width": layer(knit, ["4k", "3k"]),
        "layers.stitch row 1 uses code 'p' missing from legend": layer({"k": "knit"}, ["4k", "4p"]),
    }
    for expected, layers in cases.items():
        assert expected in chartdoc.validate_document(doc(rows, layers=layers)), expected


def test_derived_sizes():
    d = doc(["4A"], width=4)
    d["chart"]["width"], d["chart"]["height"] = 14, 12
    assert chartdoc.cell_aspect(d) == 0.875
    assert chartdoc.finished_size(d) == (4.0, 3.0, "in")
    d["gauge"] = {"stitches": 10, "rows": 10, "over": {"value": 10, "unit": "cm"}}
    assert chartdoc.finished_size(d) == (14.0, 12.0, "cm")
