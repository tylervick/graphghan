import json
from pathlib import Path

from jsonschema import Draft202012Validator

from graphghan import manifestdoc

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "schema" / "manifest.schema.json").read_text(encoding="utf-8"))
CHART = "sha256:" + "a" * 64
ROWS = "sha256:" + "b" * 64


def chart_entry(default=True):
    return {
        "id": CHART,
        "variant": "final",
        "gauge_key": "sc",
        "default": default,
        "path": "charts/final-sc/chart.json",
        "preview": "charts/final-sc/preview.png",
        "width": 7,
        "height": 5,
        "stitch": "sc",
        "colors": 2,
        "stitches": 24,
        "changes_per_row": {"mean": 0.8, "max": 2},
        "yards_est": 1,
    }


def manifest(**extra):
    m = {
        "schema": 2,
        "id": "bag",
        "title": "Bag",
        "version": "0.1.0",
        "dedication": "",
        "quote": "",
        "author": "",
        "license": "",
        "preview": "preview.png",
        "palette": [],
        "charts": [chart_entry()],
        "pieces": [
            {"id": "panel", "title": "Panel", "make": 1, "chart": CHART, "pages": [9]},
            {"id": "strip", "title": "Strip", "make": 2, "rows": "pieces/strip.rows.json", "rows_id": ROWS},
        ],
        "assembly": [{"title": "Sew up", "pages": [3]}],
        "updated": "1980-01-01T00:00:00Z",
    }
    m.update(extra)
    return m


def test_a_pieced_manifest_validates():
    assert manifestdoc.validate_manifest(manifest()) == []
    assert Draft202012Validator(SCHEMA).is_valid(manifest())


def test_a_schema_1_manifest_is_one_piece():
    m = manifest(schema=1)
    del m["pieces"], m["assembly"]
    assert manifestdoc.validate_manifest(m) == []
    assert manifestdoc.pieces(m) == [{"id": "chart", "title": "Bag", "make": 1, "chart": CHART, "pages": []}]


def test_pieces_default_make_to_one():
    m = manifest()
    del m["pieces"][0]["make"]
    assert manifestdoc.pieces(m)[0]["make"] == 1


def test_refusals():
    cases = {
        "names a chart": lambda m: m["pieces"][0].__setitem__("chart", "sha256:" + "c" * 64),
        "exactly one of": lambda m: m["pieces"][1].__setitem__("chart", CHART),
        "rows_id": lambda m: m["pieces"][1].pop("rows_id"),
        "duplicate": lambda m: m["pieces"][1].__setitem__("id", "panel"),
        "make": lambda m: m["pieces"][1].__setitem__("make", 0),
        "pieces is empty": lambda m: m.__setitem__("pieces", []),
        "default": lambda m: m["charts"][0].__setitem__("default", False),
        "pieces needs schema 2": lambda m: m.__setitem__("schema", 1),
    }
    for needle, mutate in cases.items():
        m = manifest()
        mutate(m)
        problems = manifestdoc.validate_manifest(m)
        assert any(needle in p for p in problems), (needle, problems)


def test_a_written_only_pattern_has_no_charts_and_no_default():
    m = manifest(charts=[])
    m["pieces"] = [m["pieces"][1]]
    assert manifestdoc.validate_manifest(m) == []


def test_schema_rejects_a_piece_with_both_chart_and_rows_but_no_rows_id():
    # CodeRabbit review of #206: the chart branch of `pieces.items.oneOf` only required "chart",
    # so a piece with both "chart" and "rows" (but no "rows_id") matched it -- although
    # `manifestdoc.validate_manifest` refuses that piece as neither one thing nor the other.
    m = manifest()
    m["pieces"][0]["rows"] = "pieces/panel.rows.json"
    assert not Draft202012Validator(SCHEMA).is_valid(m)
    assert manifestdoc.validate_manifest(m) != []


def test_schema_still_accepts_the_existing_valid_manifests():
    assert Draft202012Validator(SCHEMA).is_valid(manifest())
    m1 = manifest(schema=1)
    del m1["pieces"], m1["assembly"]
    assert Draft202012Validator(SCHEMA).is_valid(m1)
    written_only = manifest(charts=[])
    written_only["pieces"] = [written_only["pieces"][1]]
    assert Draft202012Validator(SCHEMA).is_valid(written_only)
