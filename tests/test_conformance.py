import hashlib
import json
import runpy
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

from graphghan import chartdoc, progress

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "chart-format"
CHART_SCHEMA = json.loads((ROOT / "schema" / "chart.schema.json").read_text(encoding="utf-8"))
NAMES = sorted(p.name[: -len(".chart.json")] for p in FIX.glob("*.chart.json"))


def load(name):
    return json.loads((FIX / f"{name}.chart.json").read_text(encoding="utf-8"))


def canonical(passes) -> bytes:
    return json.dumps(passes, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def test_fixture_set_matches_spec():
    assert set(NAMES) == {
        "minimal-rows",
        "minimal-rounds",
        "two-letter-codes",
        "layers-stitch",
        "explicit-passes",
        "unknown-technique",
        "filet-blocks",
        "craigh-na-dun",
    }


def test_chart_schema_is_valid():
    Draft202012Validator.check_schema(CHART_SCHEMA)


@pytest.mark.parametrize("name", NAMES)
def test_fixture_validates_against_schema(name):
    errors = sorted(Draft202012Validator(CHART_SCHEMA).iter_errors(load(name)), key=lambda e: list(e.path))
    assert errors == [], [e.message for e in errors]


@pytest.mark.parametrize("name", NAMES)
def test_fixture_is_structurally_valid(name):
    assert chartdoc.validate_document(load(name)) == []


@pytest.mark.parametrize("name", NAMES)
def test_sequence_matches_expected(name):
    doc = load(name)
    expected_path = FIX / f"{name}.sequence.json"
    if not expected_path.exists():
        with pytest.raises(chartdoc.UnsupportedTechnique):
            chartdoc.sequence(doc)
        return
    expected = json.loads(expected_path.read_text(encoding="utf-8"))
    passes = chartdoc.sequence(doc)
    if "sha256" in expected:
        assert hashlib.sha256(canonical(passes)).hexdigest() == expected["sha256"]
    else:
        assert passes == expected["passes"]


def test_fixtures_are_fresh(tmp_path):
    gen = runpy.run_path(str(FIX / "generate.py"), run_name="fixtures_generate")
    gen["main"](tmp_path)
    generated = {p.name for p in tmp_path.iterdir()}
    committed = {p.name for p in FIX.iterdir() if p.suffix == ".json"}
    assert generated == committed
    for name in generated:
        assert (FIX / name).read_bytes() == (tmp_path / name).read_bytes(), name


def test_craigh_fixture_equals_committed_dist():
    dist = json.loads(
        (ROOT / "patterns" / "craigh-na-dun" / "dist" / "chart.json").read_text(encoding="utf-8")
    )
    assert load("craigh-na-dun") == dist


PROGRESS_SCHEMA = json.loads((ROOT / "schema" / "progress.schema.json").read_text(encoding="utf-8"))
PROGRESS_NAMES = sorted(p.name[: -len(".progress.json")] for p in FIX.glob("*.progress.json"))


def test_progress_schema_is_valid():
    Draft202012Validator.check_schema(PROGRESS_SCHEMA)


@pytest.mark.parametrize("name", PROGRESS_NAMES)
def test_progress_fixture_validates_and_summarizes(name):
    doc = json.loads((FIX / f"{name}.progress.json").read_text(encoding="utf-8"))
    errors = list(Draft202012Validator(PROGRESS_SCHEMA).iter_errors(doc))
    assert errors == [], [e.message for e in errors]
    chart = load(doc["ext"]["fixture"]["chart"])
    assert chart["chart"]["id"] == doc["chart_id"]
    expected = json.loads((FIX / f"{name}.progress.expected.json").read_text(encoding="utf-8"))
    assert progress.summarize(doc, chartdoc.sequence(chart), kind=chartdoc.cell_kind(chart)) == expected


def test_schema_rejects_bad_documents():
    v = Draft202012Validator(CHART_SCHEMA)
    good = load("minimal-rows")
    for mutate in (
        lambda d: d.pop("pattern"),
        lambda d: d.__setitem__("schema", 1),
        lambda d: d["rows"].__setitem__(0, "14ABCD"),
        lambda d: d["palette"][0].__setitem__("code", "A1"),
        lambda d: d["gauge"]["over"].__setitem__("unit", "mm"),
        lambda d: d["chart"].__setitem__("id", "nope"),
    ):
        d = json.loads(json.dumps(good))
        mutate(d)
        assert not v.is_valid(d)
    bad_cell = json.loads((FIX / "minimal-rows.chart.json").read_text(encoding="utf-8"))
    bad_cell["chart"]["cell"] = {"kind": "sparkle"}
    assert list(Draft202012Validator(CHART_SCHEMA).iter_errors(bad_cell)) != []


def test_schema_accepts_phase1_keys():
    v = Draft202012Validator(CHART_SCHEMA)
    d = load("minimal-rows")
    d["pattern"]["craft"] = "crochet"
    d["pattern"]["language"] = "en"
    d["gauge"].update(
        {
            "unit": "stitches",
            "stitch_name": "single crochet",
            "terms": "US",
            "terms_also": "UK",
            "boundary": {"kind": "turn", "chain": 1, "counts_as_stitch": False, "color": "next"},
        }
    )
    d["foundation"] = {"chain": 15, "first_stitch_in": 2, "note": "in A"}
    assert v.is_valid(d), [e.message for e in v.iter_errors(d)]


def test_schema_rejects_bad_phase1_values():
    v = Draft202012Validator(CHART_SCHEMA)
    good = load("minimal-rows")
    for mutate in (
        lambda d: d["gauge"].__setitem__("boundary", {"kind": "flip", "chain": 1}),
        lambda d: d["gauge"].__setitem__("boundary", {"kind": "turn"}),  # chain is required
        lambda d: d["gauge"].__setitem__("boundary", {"kind": "turn", "chain": -1}),
        lambda d: d["gauge"].__setitem__("boundary", {"kind": "turn", "chain": 1, "color": "same"}),
        lambda d: d["gauge"].__setitem__("terms", "us"),
        lambda d: d["gauge"].__setitem__("unit", "cells"),
        lambda d: d["pattern"].__setitem__("craft", "weaving"),
        lambda d: d.__setitem__("foundation", {"first_stitch_in": 2}),  # chain is required
        lambda d: d.__setitem__("foundation", {"chain": 0}),
    ):
        d = json.loads(json.dumps(good))
        mutate(d)
        assert not v.is_valid(d)


def test_validate_document_rejects_malformed_boundary():
    good = load("minimal-rows")
    for boundary in (
        {"kind": "turn"},
        {"kind": "flip", "chain": 1},
        {"kind": "turn", "chain": "1"},
        {"kind": "turn", "chain": -1},
    ):
        d = json.loads(json.dumps(good))
        d["gauge"]["boundary"] = boundary
        assert any("boundary" in p for p in chartdoc.validate_document(d)), boundary
    d = json.loads(json.dumps(good))
    d["gauge"]["boundary"] = {"kind": "spiral", "chain": 0}
    assert chartdoc.validate_document(d) == []
    d = json.loads(json.dumps(good))
    d["gauge"] = ["not", "a", "dict"]
    assert isinstance(chartdoc.validate_document(d), list)  # never raises


def test_validate_document_refuses_a_foundation_shorter_than_the_first_row():
    """A maker could not work row 1 (#50): refused, not warned. Extra chains are fine."""
    good = load("minimal-rows")  # width 14
    d = json.loads(json.dumps(good))
    d["foundation"] = {"chain": 15, "first_stitch_in": 2}
    assert chartdoc.validate_document(d) == []
    d["foundation"] = {"chain": 20, "first_stitch_in": 2}  # an edge's worth of extra chains
    assert chartdoc.validate_document(d) == []
    d["foundation"] = {"chain": 14, "first_stitch_in": 2}
    assert any("foundation" in p for p in chartdoc.validate_document(d))
    d["foundation"] = {"chain": 13}  # first_stitch_in absent means 1: needs at least width
    assert any("foundation" in p for p in chartdoc.validate_document(d))
    d["foundation"] = {"chain": 14}
    assert chartdoc.validate_document(d) == []


def test_craigh_chart_id_is_stable_across_phase1():
    """Authoring the stitch and the boundary must not move a chart id (spec §6.6): projects in
    flight would read the change as a new chart."""
    doc = load("craigh-na-dun")
    assert doc["chart"]["id"] == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f"
    assert doc["gauge"]["boundary"] == {
        "kind": "turn",
        "chain": 1,
        "counts_as_stitch": False,
        "color": "next",
    }
    assert doc["gauge"]["terms"] == "US"
    assert doc["foundation"] == {"chain": 190, "first_stitch_in": 2, "note": "in Gold (Y)"}
    assert doc["pattern"]["craft"] == "crochet" and doc["pattern"]["language"] == "en"


def test_filet_fixture_opens_and_withholds_stitch_numbers():
    """A filet block is not a stitch (docs/research/genres/filet.md, #44): the fixture must open,
    work and sequence, and carry `cells` but none of the stitch-derived stats."""
    chart = load("filet-blocks")
    assert chartdoc.validate_document(chart) == []
    assert chartdoc.cell_kind(chart) == "block"
    assert chartdoc.sequence(chart)  # it is workable: it opens and sequences
    st = chart.get("stats") or {}
    assert st.get("cells") == 72
    assert "stitches" not in st and "yards_est" not in st and "skeins_364yd" not in st


def test_filet_fixture_refuses_stitch_stats_if_added():
    """The other direction of the rule above: proving the withholding by omission alone is not
    enough (an absent stats block would pass trivially), so add stitches back and require refusal."""
    chart = load("filet-blocks")
    chart["stats"]["stitches"] = chart["stats"]["cells"]
    problems = chartdoc.validate_document(chart)
    assert any("stats.stitches" in p and "block" in p for p in problems), problems
