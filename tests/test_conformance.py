import hashlib
import json
import runpy
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

from graphghan import chartdoc, manifestdoc, progress, rowsdoc

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "chart-format"
REFUSED = FIX / "refused"
CHART_SCHEMA = json.loads((ROOT / "schema" / "chart.schema.json").read_text(encoding="utf-8"))
NAMES = sorted(p.name[: -len(".chart.json")] for p in FIX.glob("*.chart.json"))
REFUSED_NAMES = sorted(p.name[: -len(".chart.json")] for p in REFUSED.glob("*.chart.json"))


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
        "tiles-gauge",
        "craigh-na-dun",
        "shaped-basic",
    }


def test_chart_schema_is_valid():
    Draft202012Validator.check_schema(CHART_SCHEMA)


def test_cell_kinds_match_schema_enum():
    """The five cardinalities are asserted in two independent places (docs/chart-format.md
    §Cells): `chartdoc.CELL_KINDS` and the schema enum. Nothing else keeps them in sync, so a kind
    added to one and not the other would refuse in one layer and validate clean in the other."""
    enum = CHART_SCHEMA["properties"]["chart"]["properties"]["cell"]["properties"]["kind"]["enum"]
    assert set(chartdoc.CELL_KINDS) == set(enum)


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
    generated = {p.name for p in tmp_path.iterdir() if p.suffix == ".json"}
    committed = {p.name for p in FIX.iterdir() if p.suffix == ".json"}
    assert generated == committed
    for name in generated:
        assert (FIX / name).read_bytes() == (tmp_path / name).read_bytes(), name
    generated_refused = {p.name for p in (tmp_path / "refused").iterdir() if p.suffix == ".json"}
    committed_refused = {p.name for p in REFUSED.iterdir() if p.suffix == ".json"}
    assert generated_refused == committed_refused
    for name in generated_refused:
        assert (REFUSED / name).read_bytes() == (tmp_path / "refused" / name).read_bytes(), name
    # The pieces-basic/ tree is a bundle's worth of files, not a flat *.json glob, and the two
    # preview.png files are committed once (not written by main()), so they are excluded here.
    generated_pieces = {
        p.relative_to(tmp_path / "pieces-basic").as_posix()
        for p in (tmp_path / "pieces-basic").rglob("*")
        if p.is_file() and p.name != "preview.png"
    }
    committed_pieces = {
        p.relative_to(FIX / "pieces-basic").as_posix()
        for p in (FIX / "pieces-basic").rglob("*")
        if p.is_file() and p.name != "preview.png"
    }
    assert generated_pieces == committed_pieces
    for rel in generated_pieces:
        assert (FIX / "pieces-basic" / rel).read_bytes() == (tmp_path / "pieces-basic" / rel).read_bytes(), (
            rel
        )


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


def test_validate_document_refuses_an_explicit_null_cell():
    """`"cell": null` must not be read as absent (chartdoc.py): the schema refuses it and Swift
    opens the document as `.stitch`, so a bare `is not None` guard that skips a JSON null would let
    this one document mean three different things across three readers (#44)."""
    good = load("minimal-rows")
    d = json.loads(json.dumps(good))
    d["chart"]["cell"] = None
    problems = chartdoc.validate_document(d)
    assert any("chart.cell is NoneType, not an object" in p for p in problems), problems
    assert not Draft202012Validator(CHART_SCHEMA).is_valid(d)


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


def test_tiles_gauge_fixture_derives_a_size():
    chart = json.loads((FIX / "tiles-gauge.chart.json").read_text(encoding="utf-8"))
    assert chartdoc.validate_document(chart) == []
    assert chartdoc.cell_kind(chart) == "tile"
    assert chartdoc.size_derives(chart)
    assert chartdoc.finished_size(chart) is not None


def test_tiles_gauge_withholds_when_the_cell_declaration_is_removed():
    """The direction absence alone cannot prove: a tiles gauge over stitch cells has no size."""
    chart = json.loads((FIX / "tiles-gauge.chart.json").read_text(encoding="utf-8"))
    del chart["chart"]["cell"]
    assert not chartdoc.size_derives(chart)
    assert chartdoc.finished_size(chart) is None


# The finished size every fixture that declares neither `chart.cell` nor `gauge.unit` had before
# #48 — frozen so the compatibility claim in spec §3.1 ("every finished size in the repo is
# unchanged by this phase") is pinned to actual numbers, not just to "a size still derives".
# Verified against chartdoc.finished_size(load(name)) for each name below.
FINISHED_SIZES_BEFORE_48 = {
    "craigh-na-dun": (54.0, 46.0, "in"),
    "explicit-passes": (1.1, 0.5, "in"),
    "layers-stitch": (3.4, 0.5, "in"),
    "minimal-rounds": (4.0, 3.0, "in"),
    "minimal-rows": (4.0, 3.0, "in"),
    "two-letter-codes": (3.4, 0.5, "in"),
    "unknown-technique": (0.9, 0.5, "in"),
    "shaped-basic": (2.0, 1.2, "in"),
}


def _declares_a_pairing(chart: dict) -> bool:
    return "cell" in chart["chart"] or bool(chart["gauge"].get("unit"))


@pytest.mark.parametrize("name", NAMES)
def test_no_existing_finished_size_moved(name):
    """Global constraint: both fields default and their defaults pair, so every chart that carries
    neither keeps the exact size it had before #48 — not merely *a* size, the same tuple."""
    chart = json.loads((FIX / f"{name}.chart.json").read_text(encoding="utf-8"))
    if _declares_a_pairing(chart):
        pytest.skip("declares a pairing; covered by the tests above")
    assert chartdoc.finished_size(chart) == FINISHED_SIZES_BEFORE_48[name]


def test_finished_sizes_before_48_covers_exactly_the_non_skipping_fixtures():
    """Keeps the frozen dict above and the skip condition in test_no_existing_finished_size_moved
    from silently drifting apart: a fixture added to one without the other would either skip
    unpinned or fail with a KeyError instead of naming the real problem."""
    non_skipping = {name for name in NAMES if not _declares_a_pairing(load(name))}
    assert set(FINISHED_SIZES_BEFORE_48) == non_skipping


def test_shaped_fixture_shaping_matches_expected():
    doc = load("shaped-basic")
    expected = json.loads((FIX / "shaped-basic.shaping.json").read_text(encoding="utf-8"))
    assert chartdoc.shaping(chartdoc.sequence(doc)) == expected["shaping"]


def test_shaped_fixture_counts_stitched_cells_only():
    st = load("shaped-basic")["stats"]
    assert st["cells"] == 24 and st["stitches"] == 24
    assert st["counts"] == {"A": 22, "B": 2}  # the ground is no yarn
    assert set(st["yards_est"]) == {"A", "B"}
    assert st["color_changes_per_row"]["per_row"] == [0, 2, 2, 0, 0]


def test_schema_accepts_schema_3_keys_and_rejects_bad_ones():
    v = Draft202012Validator(CHART_SCHEMA)
    assert v.is_valid(load("shaped-basic"))
    for mutate in (
        lambda d: d.__setitem__("schema", 4),
        lambda d: d["palette"][2].__setitem__("stitch", "no"),
        lambda d: d.__setitem__("written", [1, 2]),
    ):
        d = load("shaped-basic")
        mutate(d)
        assert not v.is_valid(d)


def load_refused(name):
    return json.loads((REFUSED / f"{name}.chart.json").read_text(encoding="utf-8"))


def test_refused_fixture_set_matches_spec():
    """Spec §9's five refusal cases, each in its own file so a reader can be pointed at exactly
    one broken rule at a time."""
    assert set(REFUSED_NAMES) == {
        "gap-in-row",
        "row-without-stitches",
        "two-no-stitch-codes",
        "foundation-too-short",
        "written-wrong-length",
    }


@pytest.mark.parametrize("name", REFUSED_NAMES)
def test_refused_fixture_validates_against_schema(name):
    """Otherwise valid: the JSON Schema alone cannot express the rule that refuses it (spec §9),
    so it must still pass schema validation."""
    errors = list(Draft202012Validator(CHART_SCHEMA).iter_errors(load_refused(name)))
    assert errors == [], [e.message for e in errors]


@pytest.mark.parametrize("name", REFUSED_NAMES)
def test_refused_fixture_is_refused(name):
    assert chartdoc.validate_document(load_refused(name)) != []


def test_refused_directory_listing_matches_spec():
    """The full refused/ listing, not just the *.chart.json glob REFUSED_NAMES draws from: the
    five pieces-basic refusals (a rows gap, an open-ended entry that is not last, a piece naming
    a chart not in `charts`, a chart no piece names, a default chart that is not the first chart
    piece's) live alongside the five chart refusals."""
    assert {p.name for p in REFUSED.glob("*.json")} == {f"{name}.chart.json" for name in REFUSED_NAMES} | {
        "rows-gap.rows.json",
        "rows-open-not-last.rows.json",
        "piece-names-missing-chart.pattern.json",
        "chart-no-piece-names.pattern.json",
        "default-not-first-chart-piece.pattern.json",
    }


PIECES = FIX / "pieces-basic"
MANIFEST_SCHEMA = json.loads((ROOT / "schema" / "manifest.schema.json").read_text(encoding="utf-8"))
ROWS_SCHEMA = json.loads((ROOT / "schema" / "rows.schema.json").read_text(encoding="utf-8"))


def pieced(name):
    return json.loads((PIECES / name).read_text(encoding="utf-8"))


def test_pieces_fixture_manifest_is_valid():
    m = pieced("pattern.json")
    assert Draft202012Validator(MANIFEST_SCHEMA).is_valid(m)
    assert manifestdoc.validate_manifest(m) == []
    assert [p["id"] for p in manifestdoc.pieces(m)] == ["panel", "strip", "fin", "strap"]


def test_pieces_fixture_files_match_the_manifest():
    m = pieced("pattern.json")
    for c in m["charts"]:
        chart = pieced(c["path"])
        assert chartdoc.validate_document(chart) == [] and chart["chart"]["id"] == c["id"]
    for p in m["pieces"]:
        if "rows" in p:
            rd = pieced(p["rows"])
            assert Draft202012Validator(ROWS_SCHEMA).is_valid(rd)
            assert rowsdoc.validate_rows_document(rd) == [] and rd["id"] == p["rows_id"]


def test_a_strip_row_is_not_ascii():
    """The rows id hashes UTF-8 (spec §5.2): a non-ASCII character in the strip pins both readers
    to the same bytes (the Swift reader's `theIDMatchesThePythons` covers the strip)."""
    assert any(not e["text"].isascii() for e in pieced("pieces/strip.rows.json")["rows"])


def test_pieces_fixture_progress_summarizes():
    m = pieced("pattern.json")
    docs = {c["id"]: pieced(c["path"]) for c in m["charts"]}
    for p in m["pieces"]:
        if "rows" in p:
            docs[p["rows_id"]] = pieced(p["rows"])
    doc = pieced("progress.json")
    assert Draft202012Validator(PROGRESS_SCHEMA).is_valid(doc)
    assert progress.summarize_project(doc, m, docs) == pieced("progress.expected.json")


@pytest.mark.parametrize("name", ["rows-gap.rows.json", "rows-open-not-last.rows.json"])
def test_refused_rows_documents(name):
    rd = json.loads((FIX / "refused" / name).read_text(encoding="utf-8"))
    assert Draft202012Validator(ROWS_SCHEMA).is_valid(rd)
    assert rowsdoc.validate_rows_document(rd) != []


def test_the_rows_gap_fixture_is_refused_only_for_its_gap():
    rd = json.loads((FIX / "refused" / "rows-gap.rows.json").read_text(encoding="utf-8"))
    assert rowsdoc.validate_rows_document(rd) == ["rows[1] starts at 5; row 2 is missing or printed twice"]


def test_refused_manifest_naming_a_missing_chart():
    m = json.loads((FIX / "refused" / "piece-names-missing-chart.pattern.json").read_text(encoding="utf-8"))
    assert Draft202012Validator(MANIFEST_SCHEMA).is_valid(m)
    assert any("not in `charts`" in p for p in manifestdoc.validate_manifest(m))


@pytest.mark.parametrize(
    ("name", "problem"),
    [
        ("chart-no-piece-names.pattern.json", "which no piece names"),
        (
            "default-not-first-chart-piece.pattern.json",
            "the default chart must be the first chart piece's chart",
        ),
    ],
)
def test_refused_manifest_is_refused_for_its_one_reason(name, problem):
    """#228: schema-valid, and refused for exactly the one rule it breaks (the Swift reader refuses
    the same two files in PatternBundleTests)."""
    m = json.loads((FIX / "refused" / name).read_text(encoding="utf-8"))
    assert Draft202012Validator(MANIFEST_SCHEMA).is_valid(m)
    problems = manifestdoc.validate_manifest(m)
    assert len(problems) == 1 and problem in problems[0]


PHONE = FIX / "phone-pieced"


def phone(name):
    return json.loads((PHONE / name).read_text(encoding="utf-8"))


def test_phone_pieced_fixture_is_valid():
    """The phone's own writers' pieced pattern (Swift `PhonePiecedFixtureTests` pins its bytes):
    every file passes its schema and its validator, and every id is the one Python computes."""
    m = phone("pattern.json")
    assert list(Draft202012Validator(MANIFEST_SCHEMA).iter_errors(m)) == []
    assert manifestdoc.validate_manifest(m) == []
    assert [p["id"] for p in manifestdoc.pieces(m)] == ["panel", "strap"]
    for c in m["charts"]:
        chart = phone(c["path"])
        assert [e.message for e in Draft202012Validator(CHART_SCHEMA).iter_errors(chart)] == []
        assert chartdoc.validate_document(chart) == [] and chart["schema"] == 3
        codes = [p["code"] for p in chart["palette"]]
        computed = chartdoc.chart_id(
            codes, chart["rows"], chart["technique"], no_stitch=chartdoc.no_stitch_code(chart)
        )
        assert computed == chart["chart"]["id"] == c["id"]
    for p in m["pieces"]:
        if "rows" in p:
            rd = phone(p["rows"])
            assert [e.message for e in Draft202012Validator(ROWS_SCHEMA).iter_errors(rd)] == []
            assert rowsdoc.validate_rows_document(rd) == [] and rd["id"] == p["rows_id"]


def test_phone_pieced_fixture_with_its_panel_twice_is_refused():
    """What the phone wrote before identical grids folded into one piece: a second piece naming
    the same chart, which spec §5.3 refuses (the phone now writes `make: 2` instead)."""
    m = phone("pattern.json")
    m["pieces"].insert(1, {**m["pieces"][0], "id": "panel-2", "make": 1})
    assert any("same chart" in p for p in manifestdoc.validate_manifest(m))
