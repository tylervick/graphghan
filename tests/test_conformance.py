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
    assert progress.summarize(doc, chartdoc.sequence(chart)) == expected


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
