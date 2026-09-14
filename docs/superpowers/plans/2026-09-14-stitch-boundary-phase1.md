# Stitch and Boundary (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put the stitch, the pass boundary (turning chain), the terminology and the foundation into the chart format as authored data, write them from `pattern.toml`, decode them in `GraphghanCore`, and show them on the Work screen and the Live Activity — without moving a single chart id.

**Architecture:** Every new field is optional, additive and lives in `gauge`, `pattern` or a new top-level `foundation`, all outside the `chart.id` hash. The Python generator copies authored values from a new `[stitch.<gauge_key>]` table and never invents a number. The Swift reader adds one value type file (`Stitch.swift`), threads it through `ChartDocument` → `Chart.stitch` → `WorkActivityInfo`, and the UI changes are text plus one capsule. `Run`, `Pass`, `WorkSequence`, the pinned `*.sequence.json` files, the site build and the PWA do not change.

**Tech Stack:** Python 3.12 (`uv`, `pytest`, `jsonschema`, `ruff` line length 110), JSON Schema 2020-12, Swift 6 / SwiftUI / Swift Testing (`swift test` for the Core package on macOS; `xcodebuild` on the iPhone 17 simulator for the app, snapshots via `TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record`), `mise run check` (hk: ruff, hygiene, gitleaks, pytest).

**Spec:** `docs/superpowers/specs/2026-09-12-pattern-data-model-design.md` §6 (Phase 1, normative). Read §6.1–§6.6 before starting; the plan argues from it.

## Global Constraints

- `schema` stays `2`. Every new key is optional; readers MUST ignore unknown keys at every level (`docs/chart-format.md` §Design).
- **No chart id moves.** `chart.id` hashes `{codes, rows, technique}` (+ `passes`); nothing in this plan touches those. Task 5 pins the Craigh na Dun id `sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f` in a test.
- **No fixture gains or loses a name.** `tests/test_conformance.py::test_fixture_set_matches_spec` and `GraphghanCoreTests/FixturesTests.swift` stay as they are; no `*.sequence.json` changes.
- `Run`, `Pass`, `WorkSequence`, `tests/test_js_parity.py`, `site/` are untouched.
- The generator never derives a turning chain, a foundation chain, or terms: absent in `pattern.toml` ⇒ absent in `chart.json`.
- Field names, verbatim from spec §6.1: `gauge.unit` (`stitches` | `tiles` | `repeats` | `rounds`), `gauge.stitch_name`, `gauge.terms` (`US` | `UK`), `gauge.terms_also`, `gauge.boundary { kind, chain, counts_as_stitch, color }` with `kind` ∈ `turn` | `join` | `rejoin` | `spiral` | `return`, `chain` integer ≥ 0, `color` ∈ `next` | `current`; `pattern.craft` (`crochet` | `knit` | `tunisian` | `cross-stitch`), `pattern.language` (BCP 47 string); top-level `foundation { chain, first_stitch_in, note }`.
- Phase 1 readers act on `boundary.kind == "turn"` only; other kinds decode and show nothing.
- iOS design rules: no raw colours or system fonts outside the tokens (`ios/Tests/DesignRulesTests.swift`). The badge uses `Font.Heather.label` and the column's existing foreground colour.
- Commit messages end with the attribution lines the session reminder gives. Run `mise run check` before every Python commit; `cd ios && mise run core-test` before every Core commit; `cd ios && mise run test` before every app commit.
- Branch: `tylervick/stitch-boundary-phase1` (already created off `main` at `1f6a686`). Do not touch `tylervick/style`.

---

## File map

| File | Responsibility in this plan |
|---|---|
| `docs/chart-format.md` | Normative text for the new keys (Task 1) |
| `schema/chart.schema.json` | Enums and shapes for the new keys (Task 1) |
| `src/graphghan/pattern.py` | `[stitch.<key>]` and `[pattern].craft/terms/terms_also/language` → `PatternMeta` (Task 2) |
| `src/graphghan/export.py` | `chart_json` writes the keys; `written_rows` gains the chain prefix; `write_dist` passes the stitch through (Tasks 3, 4) |
| `src/graphghan/chartdoc.py` | `validate_document` rejects a malformed `boundary` (Task 3) |
| `patterns/craigh-na-dun/pattern.toml`, `dist/` | Author sc/hdc stitches and regenerate (Task 5) |
| `fixtures/chart-format/craigh-na-dun.chart.json` | Regenerated copy of dist (Task 5) |
| `tests/test_pattern.py`, `tests/test_export.py`, `tests/test_conformance.py` | Python tests (Tasks 1–5) |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/Stitch.swift` | `Terms`, `BoundaryKind`, `ChainColor`, `Boundary`, `Stitch`, `StitchNames` (Task 6) |
| `.../GraphghanCore/ChartDocument.swift` | New `Gauge`/`PatternInfo` keys, `Foundation`, lenient `boundary` decode (Task 7) |
| `.../GraphghanCore/Chart.swift` | `Chart.stitch`, `Chart.foundation` (Task 8) |
| `.../GraphghanCore/LiveActivityState.swift` | `WorkActivityInfo.stitch` / `.turningChain` (Task 9) |
| `ios/Graphghan/Work/OnDeckRule.swift` | Chain prefix on the last run; foundation line at `.start` (Task 10) |
| `ios/Graphghan/Work/DoneField.swift`, `WorkScreen.swift` | Stitch badge; accessible Done label (Task 11) |
| `ios/Shared/WorkActivityViews.swift` | "ch N, turn" on the lock screen (Task 12) |
| Swift tests under `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/` and `ios/Tests/` | Tasks 6–12 |

---

### Task 1: Schema and format doc

**Files:**
- Modify: `schema/chart.schema.json` (properties `pattern`, `gauge`; add top-level `foundation`)
- Modify: `docs/chart-format.md` (Chart document example, §Gauge, new §Foundation, §Technique `turn` cross-reference, §Palette legend note)
- Test: `tests/test_conformance.py`

**Interfaces:**
- Produces: the JSON shapes every later task writes or reads. Gauge keys: `unit`, `stitch_name`, `terms`, `terms_also`, `boundary{kind, chain, counts_as_stitch, color}`. Pattern keys: `craft`, `language`. Top-level `foundation{chain, first_stitch_in, note}`.

- [ ] **Step 1: Write the failing schema tests**

Append to `tests/test_conformance.py`:

```python
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
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/test_conformance.py -k phase1 -q`
Expected: `test_schema_rejects_bad_phase1_values` FAILS (the schema accepts anything under `gauge`/`pattern` today); `test_schema_accepts_phase1_keys` passes already — that is fine, it guards the next step.

- [ ] **Step 3: Add the shapes to the schema**

In `schema/chart.schema.json`, inside `"pattern" → "properties"` add after `"url"`:

```json
"craft": { "enum": ["crochet", "knit", "tunisian", "cross-stitch"] },
"language": { "type": "string", "minLength": 2 }
```

Inside `"gauge" → "properties"` add after `"yarn_weight"`:

```json
"unit": { "enum": ["stitches", "tiles", "repeats", "rounds"] },
"stitch_name": { "type": "string", "minLength": 1 },
"terms": { "enum": ["US", "UK"] },
"terms_also": { "enum": ["US", "UK"] },
"boundary": {
  "type": "object",
  "required": ["kind", "chain"],
  "properties": {
    "kind": { "enum": ["turn", "join", "rejoin", "spiral", "return"] },
    "chain": { "type": "integer", "minimum": 0 },
    "counts_as_stitch": { "type": "boolean" },
    "color": { "enum": ["next", "current"] }
  }
}
```

At the top level of `"properties"`, add after `"gauge"`:

```json
"foundation": {
  "type": "object",
  "required": ["chain"],
  "properties": {
    "chain": { "type": "integer", "minimum": 1 },
    "first_stitch_in": { "type": "integer", "minimum": 1 },
    "note": { "type": "string" }
  }
}
```

Keep the file's existing two-space indentation; `hk` checks trailing whitespace and the final newline.

- [ ] **Step 4: Run the conformance tests**

Run: `uv run pytest tests/test_conformance.py -q`
Expected: all PASS (existing fixtures carry none of the new keys, so they still validate).

- [ ] **Step 5: Document the keys in `docs/chart-format.md`**

In the schema-2 example block, change the `pattern` line to end `"url": "https://graphghan.milo.cat/patterns/craigh-na-dun/", "craft": "crochet", "language": "en" },` and the `gauge` block to:

```json
  "gauge":    { "stitches": 14, "rows": 16, "over": { "value": 4, "unit": "in" }, "unit": "stitches",
                "stitch": "sc", "stitch_name": "single crochet", "terms": "US",
                "boundary": { "kind": "turn", "chain": 1, "counts_as_stitch": false, "color": "next" },
                "hook": "5 mm (US H-8)", "yarn_weight": "4" },
  "foundation": { "chain": 190, "first_stitch_in": 2, "note": "in Gold (Y)" },
```

Replace the `### Gauge` section body with:

```markdown
### Gauge

`stitches` and `rows` over `over.value` `over.unit` (`in` or `cm`), the way gauge is stated on a
pattern. Derived values: cell aspect = `stitches / rows`; finished width = `width / (stitches /
over.value)` in `over.unit`, likewise height. `unit` says what `stitches` and `rows` count —
`stitches` (default), `tiles`, `repeats` or `rounds`; a reader that does not understand the unit
derives no finished size.

`stitch` is the abbreviation the chart is worked in; `stitch_name` its spelled-out name, required
when `stitch` is not in the CYC master list and ignored when it is (a chart cannot rename `sc`).
`terms` is `US` or `UK`; absent means `US`. A reader MUST NOT spell out an abbreviation under the
wrong system. `terms_also` names the other system when the written instructions carry both; readers
spell out from `terms` only.

`boundary` is what happens at the end of a pass, authored and never derived:

- `kind` (required): `turn` — turn the work (flat rows); `join` — close the round with a slip
  stitch; `rejoin` — fasten off and start the next pass at the same edge (overlay mosaic,
  one-direction tapestry); `spiral` — continuous rounds, nothing happens; `return` — Tunisian, the
  return pass is the boundary. Readers implement `turn` today and show nothing for the rest.
- `chain` (required): chains made at the boundary; `0` is legal.
- `counts_as_stitch`: default `false`.
- `color`: `next` or `current`. Absent means unstated; a reader says nothing about colour rather
  than guess.

`pattern.craft` (`crochet`, `knit`, `tunisian`, `cross-stitch`) and `pattern.language` (BCP 47)
are optional; absent means unstated.

### Foundation

Top-level, optional: `{ "chain": 190, "first_stitch_in": 2, "note": "in Gold (Y)" }`. `chain` is
the authored foundation chain count and `first_stitch_in` the 1-based chain from the hook where
the first pass's first stitch goes. Both are authored; no reader cross-checks one against the
other or against `chart.width` — a foundation with extra chains for an edge is legitimate.
```

In the `### Technique and passes` bullet for `rows`, change `` `turn` is informational (true for flat work). `` to `` `turn` is informational (true for flat work); what to do at the turn — how many chains, whether they count — is `gauge.boundary`. ``

In `### Palette and cells`, after the `layers` bullet add: `- A layer's legend describes each cell as it looks on the **right side** of the work (the CYC rule for crochet and knit chart symbols), so a knit legend of `{"k": "knit", "p": "purl"}` reads correctly on a WS pass. Readers do not enforce this yet (#36).`

- [ ] **Step 6: Run the checks and commit**

Run: `mise run check`
Expected: green.

```bash
git add schema/chart.schema.json docs/chart-format.md tests/test_conformance.py
git commit -m "format: gauge.boundary, unit, terms, stitch_name; pattern.craft/language; foundation (schema + doc)"
```

---

### Task 2: `pattern.toml` gains `[stitch.<key>]` and pattern-level terms, craft, language

**Files:**
- Modify: `src/graphghan/pattern.py` (`PatternMeta`, `load_pattern`)
- Test: `tests/test_pattern.py`

**Interfaces:**
- Produces: `PatternMeta.craft: str`, `PatternMeta.terms: str`, `PatternMeta.terms_also: str`, `PatternMeta.language: str` (all `""` when unauthored) and `PatternMeta.stitches: dict[str, dict]` keyed by gauge key. Each stitch dict carries only the keys the TOML authored, normalised: `boundary: str`, `chain: int`, `counts_as_stitch: bool`, `chain_color: str`, `first_stitch_in: int`, `name: str`, `unit: str`. If `chain` is present and `boundary` is not, `boundary` is `"turn"`.

- [ ] **Step 1: Write the failing tests**

Add `import pytest` to the imports of `tests/test_pattern.py`, then append:

```python
def test_stitch_table_and_pattern_terms(tmp_path):
    src = (FIX / "pattern.toml").read_text()
    src = src.replace('stitch = "sc"', 'stitch = "sc"\ncraft = "crochet"\nterms = "US"\nterms_also = "UK"\nlanguage = "en"')
    src += (
        '\n[stitch.sc]\nchain = 1\ncounts_as_stitch = false\nchain_color = "next"\nfirst_stitch_in = 2\n'
        '\n[stitch.square]\nboundary = "join"\nchain = 3\nname = "granny cluster"\nunit = "tiles"\n'
    )
    (tmp_path / "pattern.toml").write_text(src)
    meta = load_pattern(tmp_path)
    assert meta.craft == "crochet" and meta.terms == "US" and meta.terms_also == "UK" and meta.language == "en"
    assert meta.stitches["sc"] == {
        "boundary": "turn",  # defaulted because chain is authored
        "chain": 1,
        "counts_as_stitch": False,
        "chain_color": "next",
        "first_stitch_in": 2,
    }
    assert meta.stitches["square"] == {"boundary": "join", "chain": 3, "name": "granny cluster", "unit": "tiles"}


def test_stitch_table_absent_means_nothing_authored():
    meta = load_pattern(FIX)
    assert meta.stitches == {}
    assert meta.craft == "" and meta.terms == "" and meta.terms_also == "" and meta.language == ""


def test_stitch_table_rejects_unknown_keys_and_bad_values(tmp_path):
    for body in ('[stitch.sc]\nturning_chain = 1\n', '[stitch.sc]\nchain = -1\n', '[stitch.sc]\nboundary = "flip"\nchain = 1\n'):
        (tmp_path / "pattern.toml").write_text((FIX / "pattern.toml").read_text() + "\n" + body)
        with pytest.raises(ValueError):
            load_pattern(tmp_path)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/test_pattern.py -q`
Expected: 3 FAIL with `AttributeError: 'PatternMeta' object has no attribute 'stitches'` / `craft`.

- [ ] **Step 3: Implement the loader**

In `src/graphghan/pattern.py`, add fields to `PatternMeta` after `license: str`:

```python
    craft: str
    terms: str
    terms_also: str
    language: str
    stitches: dict[str, dict]
```

Add module-level constants and a parser above `load_pattern`:

```python
BOUNDARY_KINDS = ("turn", "join", "rejoin", "spiral", "return")
CHAIN_COLORS = ("next", "current")
GAUGE_UNITS = ("stitches", "tiles", "repeats", "rounds")
STITCH_KEYS = ("boundary", "chain", "counts_as_stitch", "chain_color", "first_stitch_in", "name", "unit")


def _stitch_entry(key: str, raw: dict) -> dict:
    """One [stitch.<key>] table, normalised. Only authored keys survive; nothing is invented
    except boundary = "turn" when a chain is given without a kind (every chart we generate today
    is worked in turned rows)."""
    unknown = sorted(set(raw) - set(STITCH_KEYS))
    if unknown:
        raise ValueError(f"[stitch.{key}] has unknown keys {unknown}; allowed: {list(STITCH_KEYS)}")
    out: dict = {}
    if "boundary" in raw:
        if raw["boundary"] not in BOUNDARY_KINDS:
            raise ValueError(f"[stitch.{key}].boundary {raw['boundary']!r} is not one of {BOUNDARY_KINDS}")
        out["boundary"] = str(raw["boundary"])
    if "chain" in raw:
        chain = raw["chain"]
        if isinstance(chain, bool) or not isinstance(chain, int) or chain < 0:
            raise ValueError(f"[stitch.{key}].chain {chain!r} must be an integer >= 0")
        out["chain"] = chain
        out.setdefault("boundary", "turn")
    if "counts_as_stitch" in raw:
        if not isinstance(raw["counts_as_stitch"], bool):
            raise ValueError(f"[stitch.{key}].counts_as_stitch must be true or false")
        out["counts_as_stitch"] = raw["counts_as_stitch"]
    if "chain_color" in raw:
        if raw["chain_color"] not in CHAIN_COLORS:
            raise ValueError(f"[stitch.{key}].chain_color {raw['chain_color']!r} is not one of {CHAIN_COLORS}")
        out["chain_color"] = str(raw["chain_color"])
    if "first_stitch_in" in raw:
        fsi = raw["first_stitch_in"]
        if isinstance(fsi, bool) or not isinstance(fsi, int) or fsi < 1:
            raise ValueError(f"[stitch.{key}].first_stitch_in {fsi!r} must be an integer >= 1")
        out["first_stitch_in"] = fsi
    if "name" in raw:
        out["name"] = str(raw["name"])
    if "unit" in raw:
        if raw["unit"] not in GAUGE_UNITS:
            raise ValueError(f"[stitch.{key}].unit {raw['unit']!r} is not one of {GAUGE_UNITS}")
        out["unit"] = str(raw["unit"])
    return out
```

In `load_pattern`, after the `instructions` loop and before `return PatternMeta(`:

```python
    stitches = {str(k): _stitch_entry(str(k), dict(v)) for k, v in data.get("stitch", {}).items()}
    for field, allowed in (("terms", ("US", "UK")), ("terms_also", ("US", "UK")), ("craft", ("crochet", "knit", "tunisian", "cross-stitch"))):
        if p.get(field, "") not in ("", *allowed):
            raise ValueError(f"[pattern].{field} {p[field]!r} is not one of {allowed}")
```

and in the constructor call add after `license=p.get("license", ""),`:

```python
        craft=p.get("craft", ""),
        terms=p.get("terms", ""),
        terms_also=p.get("terms_also", ""),
        language=p.get("language", ""),
        stitches=stitches,
```

- [ ] **Step 4: Run the tests**

Run: `uv run pytest tests/test_pattern.py -q`
Expected: all PASS.

- [ ] **Step 5: Commit**

Run: `mise run check`

```bash
git add src/graphghan/pattern.py tests/test_pattern.py
git commit -m "pattern: [stitch.<key>] table and [pattern] craft/terms/terms_also/language"
```

---

### Task 3: `chart_json` writes the authored fields; `validate_document` guards `boundary`

**Files:**
- Modify: `src/graphghan/export.py` (`chart_json`)
- Modify: `src/graphghan/chartdoc.py` (`validate_document`)
- Test: `tests/test_export.py`, `tests/test_conformance.py`

**Interfaces:**
- Consumes: `PatternMeta.stitches`, `.craft`, `.terms`, `.terms_also`, `.language` from Task 2.
- Produces: `chart_json(...)` output with `pattern.craft`/`language`, `gauge.unit`/`stitch_name`/`terms`/`terms_also`/`boundary`, top-level `foundation` — each only when authored. `foundation.chain == width + first_stitch_in - 1`.

- [ ] **Step 1: Write the failing export tests**

Append to `tests/test_export.py`:

```python
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
    assert doc["gauge"]["boundary"] == {"kind": "turn", "chain": 1, "counts_as_stitch": False, "color": "next"}
    assert doc["foundation"] == {"chain": 5 + 2 - 1, "first_stitch_in": 2}
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
```

Then fix `test_chart_json_writes_authored_stitch_fields` to expect the note as well: change its `foundation` assertion to
`assert doc["foundation"] == {"chain": 6, "first_stitch_in": 2, "note": "in Alpha (A)"}`.

And append to `tests/test_conformance.py` (structural check, independent of jsonschema):

```python
def test_validate_document_rejects_malformed_boundary():
    good = load("minimal-rows")
    for boundary in ({"kind": "turn"}, {"kind": "flip", "chain": 1}, {"kind": "turn", "chain": "1"}, {"kind": "turn", "chain": -1}):
        d = json.loads(json.dumps(good))
        d["gauge"]["boundary"] = boundary
        assert any("boundary" in p for p in chartdoc.validate_document(d)), boundary
    d = json.loads(json.dumps(good))
    d["gauge"]["boundary"] = {"kind": "spiral", "chain": 0}
    assert chartdoc.validate_document(d) == []
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/test_export.py tests/test_conformance.py -q`
Expected: the four new export tests FAIL on missing keys; the validate test FAILS because no problem mentions `boundary`.

- [ ] **Step 3: Implement `chart_json`**

In `src/graphghan/export.py`, replace the body of `chart_json` from `codes = meta.palette.codes` to the end with:

```python
    codes = meta.palette.codes
    rows = rows_to_strings(a, codes)
    technique = dict(TECHNIQUE_ROWS)
    report_out = {k: (list(v) if isinstance(v, tuple) else v) for k, v in report.items()}
    stitch = meta.stitches.get(gauge_key, {})
    pattern = {
        "id": meta.slug,
        "title": meta.title,
        "version": meta.version,
        "author": meta.author,
        "license": meta.license,
        "dedication": meta.dedication,
        "quote": meta.quote,
        "url": f"{SITE_URL}patterns/{meta.slug}/",
    }
    if meta.craft:
        pattern["craft"] = meta.craft
    if meta.language:
        pattern["language"] = meta.language
    gauge = {
        "stitches": _gauge_number(st * 4),
        "rows": _gauge_number(rows_per_in * 4),
        "over": {"value": 4, "unit": "in"},
        "stitch": gauge_key,
        "hook": meta.hook,
        "yarn_weight": meta.yarn_weight,
    }
    if "unit" in stitch:
        gauge["unit"] = stitch["unit"]
    if "name" in stitch:
        gauge["stitch_name"] = stitch["name"]
    if meta.terms:
        gauge["terms"] = meta.terms
    if meta.terms_also:
        gauge["terms_also"] = meta.terms_also
    if "boundary" in stitch:  # always paired with chain by pattern._stitch_entry
        boundary = {"kind": stitch["boundary"], "chain": stitch["chain"]}
        if "counts_as_stitch" in stitch:
            boundary["counts_as_stitch"] = stitch["counts_as_stitch"]
        if "chain_color" in stitch:
            boundary["color"] = stitch["chain_color"]
        gauge["boundary"] = boundary
    doc = {
        "schema": SCHEMA,
        "pattern": pattern,
        "chart": {
            "id": chart_id(codes, rows, technique),
            "variant": variant,
            "gauge_key": gauge_key,
            "width": int(a.shape[1]),
            "height": int(a.shape[0]),
        },
        "generator": {"name": "graphghan", "version": generator_version()},
        "palette": palette_entries(meta.palette),
        "rows": rows,
        "gauge": gauge,
        "technique": technique,
        "instructions": [dict(s) for s in meta.instructions],
        "stats": stats(a, codes),
        "ext": {"graphghan": {"report": report_out}},
    }
    if "first_stitch_in" in stitch:
        fsi = stitch["first_stitch_in"]
        foundation = {"chain": int(a.shape[1]) + fsi - 1, "first_stitch_in": fsi}
        first = next((c for c in meta.palette.colors if c.code == meta.first_row_color), None)
        if first is not None:
            foundation["note"] = f"in {first.name} ({first.code})"
        doc["foundation"] = foundation
    return doc
```

(`Palette.colors` entries have `.code` and `.name`, as `palette_entries` already uses.)

- [ ] **Step 4: Implement the structural check**

In `src/graphghan/chartdoc.py`, add module constants after `TECHNIQUE_ROWS`:

```python
BOUNDARY_KINDS = ("turn", "join", "rejoin", "spiral", "return")
CHAIN_COLORS = ("next", "current")
```

and in `validate_document`, before `expected = chart_id(...)`:

```python
    boundary = (doc.get("gauge") or {}).get("boundary")
    if boundary is not None:
        if not isinstance(boundary, dict):
            problems.append("gauge.boundary is not an object")
        else:
            if boundary.get("kind") not in BOUNDARY_KINDS:
                problems.append(f"gauge.boundary.kind {boundary.get('kind')!r} is not one of {BOUNDARY_KINDS}")
            chain = boundary.get("chain")
            if isinstance(chain, bool) or not isinstance(chain, int) or chain < 0:
                problems.append(f"gauge.boundary.chain {chain!r} is not an integer >= 0")
            if "color" in boundary and boundary["color"] not in CHAIN_COLORS:
                problems.append(f"gauge.boundary.color {boundary['color']!r} is not one of {CHAIN_COLORS}")
```

- [ ] **Step 5: Run the tests**

Run: `uv run pytest tests/test_export.py tests/test_conformance.py -q`
Expected: all PASS. `test_chart_json_schema2_and_write_dist` still passes because the minimal fixture authors nothing.

- [ ] **Step 6: Commit**

Run: `mise run check`

```bash
git add src/graphghan/export.py src/graphghan/chartdoc.py tests/test_export.py tests/test_conformance.py
git commit -m "export: write gauge.boundary/unit/terms/stitch_name, pattern.craft/language, foundation from pattern.toml"
```

---

### Task 4: `written_rows` gains the turning chain

**Files:**
- Modify: `src/graphghan/export.py` (`written_rows`, `write_dist`)
- Test: `tests/test_export.py`

**Interfaces:**
- Produces: `written_rows(a, codes, boundary=None)` where `boundary` is the `gauge.boundary` dict or `None`. Rows 2..n are prefixed `ch N, turn, ` when `boundary["kind"] == "turn"`; row 1 and every other kind are unchanged. `write_dist` passes `doc["gauge"].get("boundary")`.

Note on the spec: §6.2 says the written rows gain "the stitch and the chain". The stitch abbreviation is deliberately **not** added to the line body: `site/tests/test_build.py::test_pattern_chart_json_contract` parses the first line's runs with `(\d+)\s+([A-Za-z]+)` and strips a trailing `(N sts)`, so a `(28 sc)` suffix or a `sc` token would break the published site's contract. The stitch is already in `gauge.stitch`, which the site prints in its specs table. The chain goes at the start of the row, which is where 29 of 39 corpus patterns put it and where Crochetpop's generator prints it.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_export.py`:

```python
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
    assert written_rows(a, ["A", "B"], boundary={"kind": "turn", "chain": 0})[1] == "Row 2 (WS): turn, 1 A, 3 B, 1 A  (5 sts)"


def test_write_dist_written_rows_carry_the_chain(tmp_path):
    meta = _phase1_meta(tmp_path)
    gr.set_gauge("sc")
    write_dist(small(), meta, "sc", {}, tmp_path / "dist")
    lines = (tmp_path / "dist" / "written-rows.txt").read_text().splitlines()
    assert lines[0].startswith("Row 1 (RS): 5 A") and lines[1].startswith("Row 2 (WS): ch 1, turn, ")
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/test_export.py -k written -q`
Expected: FAIL with `TypeError: written_rows() got an unexpected keyword argument 'boundary'`.

- [ ] **Step 3: Implement**

Replace `written_rows` in `src/graphghan/export.py`:

```python
def written_rows(a, codes, boundary=None):
    """One line per pass. From row 2 on, a `turn` boundary prints its chain first — where most
    published patterns and Crochetpop's generator put it. Other boundary kinds print nothing:
    Phase 1 readers implement `turn` only (docs/chart-format.md §Gauge)."""
    runs = rle_rows(a)
    h = len(runs)
    prefix = ""
    if boundary and boundary.get("kind") == "turn":
        chain = int(boundary.get("chain", 0))
        prefix = (f"ch {chain}, turn, " if chain > 0 else "turn, ")
    lines = []
    for i in range(h):
        row_no = i + 1
        row = runs[h - 1 - i]
        if row_no % 2 == 1:
            row = row[::-1]
        side = "RS" if row_no % 2 == 1 else "WS"
        lines.append(
            f"Row {row_no} ({side}): "
            + (prefix if row_no > 1 else "")
            + ", ".join(f"{n} {codes[c]}" for c, n in row)
            + f"  ({sum(n for _, n in row)} sts)"
        )
    return lines
```

In `write_dist`, change the written-rows line to:

```python
    (out / "written-rows.txt").write_text(
        "\n".join(written_rows(a, meta.palette.codes, boundary=doc["gauge"].get("boundary"))) + "\n"
    )
```

- [ ] **Step 4: Run the tests**

Run: `uv run pytest tests/test_export.py -q`
Expected: all PASS (`test_written_rows_reverse_odd_rows` is unchanged: no boundary, no prefix).

- [ ] **Step 5: Commit**

Run: `mise run check`

```bash
git add src/graphghan/export.py tests/test_export.py
git commit -m "export: written rows print the turning chain from row 2"
```

---

### Task 5: Author Craigh na Dun's stitches, regenerate dist and the fixture, pin the id

**Files:**
- Modify: `patterns/craigh-na-dun/pattern.toml`
- Regenerate: `patterns/craigh-na-dun/dist/**`, `fixtures/chart-format/craigh-na-dun.chart.json`
- Test: `tests/test_conformance.py`, `tests/test_drift.py`

**Interfaces:**
- Produces: a committed `chart.json` (sc, default) carrying `gauge.terms = "US"`, `gauge.boundary = {kind: turn, chain: 1, counts_as_stitch: false, color: next}`, `foundation = {chain: 190, first_stitch_in: 2, note: "in Gold (Y)"}`, `pattern.craft = "crochet"`, `pattern.language = "en"`; the hdc chart carries `chain: 2`. The Craigh na Dun chart id is unchanged.

- [ ] **Step 1: Write the id-stability test**

Append to `tests/test_conformance.py`:

```python
def test_craigh_chart_id_is_stable_across_phase1():
    """Authoring the stitch and the boundary must not move a chart id (spec §6.6): projects in
    flight would read the change as a new chart."""
    doc = load("craigh-na-dun")
    assert doc["chart"]["id"] == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f"
    assert doc["gauge"]["boundary"] == {"kind": "turn", "chain": 1, "counts_as_stitch": False, "color": "next"}
    assert doc["gauge"]["terms"] == "US"
    assert doc["foundation"] == {"chain": 190, "first_stitch_in": 2, "note": "in Gold (Y)"}
    assert doc["pattern"]["craft"] == "crochet" and doc["pattern"]["language"] == "en"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `uv run pytest tests/test_conformance.py -k stable -q`
Expected: FAIL with `KeyError: 'boundary'` (the id assertion passes: it is the committed value).

- [ ] **Step 3: Author the stitches**

In `patterns/craigh-na-dun/pattern.toml`, under `[pattern]` after `license = "CC-BY-NC-SA-4.0"` add:

```toml
craft = "crochet"
terms = "US"
language = "en"
```

After the `[gauge]` table add:

```toml
# What happens at the end of every row, per gauge key (docs/chart-format.md §Gauge). Authored,
# never derived: the design note's corpus found dc split 7:5 between ch 3 and ch 2, so no reader
# guesses. hdc as ch 2 is the reviewed choice for this blanket; 3 of 4 hdc patterns in the corpus
# use ch 1 — confirm before republishing the hdc chart (#41).
[stitch.sc]
name = "single crochet"
chain = 1
counts_as_stitch = false
chain_color = "next"
first_stitch_in = 2

[stitch.hdc]
name = "half double crochet"
chain = 2
counts_as_stitch = false
chain_color = "next"
first_stitch_in = 2
```

- [ ] **Step 4: Regenerate dist and the fixture**

Run:

```bash
uv run graphghan render patterns/craigh-na-dun
uv run python fixtures/chart-format/generate.py
git status --short
```

Expected: modified `patterns/craigh-na-dun/dist/chart.json`, `dist/written-rows.txt`, `dist/charts/final-sc/{chart.json,written-rows.txt}`, `dist/charts/final-hdc/{chart.json,written-rows.txt}`, and `fixtures/chart-format/craigh-na-dun.chart.json`. **No other fixture file changes** and no PNG changes. If a PNG shows as modified, the render is nondeterministic on this machine — stop and investigate before committing.

Check the diff is only the new keys:

```bash
git diff --stat
git diff fixtures/chart-format/craigh-na-dun.chart.json | head -40
head -3 patterns/craigh-na-dun/dist/written-rows.txt
```

Expected: `Row 2 (WS): ch 1, turn, 189 Y  (189 sts)` on the second line; the id line in the diff is absent (unchanged).

- [ ] **Step 5: Run the whole suite**

Run: `uv run pytest -q`
Expected: all PASS, including `test_fixtures_are_fresh`, `test_craigh_fixture_equals_committed_dist`, `test_committed_dist_matches_code`, `test_sequence_matches_expected[craigh-na-dun]` (the pinned sequence hash is unaffected), and `site/tests/test_build.py::test_pattern_chart_json_contract`.

- [ ] **Step 6: Commit**

Run: `mise run check`

```bash
git add patterns/craigh-na-dun tests/test_conformance.py fixtures/chart-format/craigh-na-dun.chart.json
git commit -m "craigh-na-dun: author sc/hdc turning chains, terms and foundation; regenerate dist and fixture"
```

---

### Task 6: `Stitch.swift` — value types and the US/UK name tables

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Stitch.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/StitchTests.swift`

**Interfaces:**
- Produces:

```swift
public enum Terms: String, Codable, Sendable { case us = "US", uk = "UK" }
public enum BoundaryKind: String, Codable, Sendable { case turn, join, rejoin, spiral, `return` }
public enum ChainColor: String, Codable, Sendable { case next, current }
public struct Boundary: Codable, Equatable, Sendable { kind, chain, countsAsStitch, color }
public struct Stitch: Equatable, Sendable { code, name: String?, terms, boundary: Boundary? }
public enum StitchNames { static func name(_ code: String, terms: Terms) -> String? }
```

`Boundary` decodes from the JSON object (`counts_as_stitch` default `false`, `color` optional).

- [ ] **Step 1: Write the failing tests**

Create `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/StitchTests.swift`:

```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct StitchTests {
    @Test func usNamesCoverTheCYCList() {
        #expect(StitchNames.name("sc", terms: .us) == "single crochet")
        #expect(StitchNames.name("hdc", terms: .us) == "half double crochet")
        #expect(StitchNames.name("dc", terms: .us) == "double crochet")
        #expect(StitchNames.name("tr", terms: .us) == "treble crochet")
        #expect(StitchNames.name("dtr", terms: .us) == "double treble crochet")
        #expect(StitchNames.name("sl st", terms: .us) == "slip stitch")
        #expect(StitchNames.name("ch", terms: .us) == "chain")
    }

    @Test func ukNamesCollideWithUSOnPurpose() {
        // The same abbreviation names a different stitch under each system: the reason terms is declared.
        #expect(StitchNames.name("dc", terms: .uk) == "double crochet")
        #expect(StitchNames.name("tr", terms: .uk) == "treble")
        #expect(StitchNames.name("htr", terms: .uk) == "half treble")
        #expect(StitchNames.name("dtr", terms: .uk) == "double treble")
        #expect(StitchNames.name("ss", terms: .uk) == "slip stitch")
        #expect(StitchNames.name("sc", terms: .uk) == nil)   // not a UK abbreviation
        #expect(StitchNames.name("hdc", terms: .uk) == nil)
    }

    @Test func unknownCodeHasNoName() {
        #expect(StitchNames.name("hhdc", terms: .us) == nil)
        #expect(StitchNames.name("", terms: .us) == nil)
    }

    @Test func boundaryDecodesWithDefaults() throws {
        let b = try JSONDecoder().decode(Boundary.self, from: Data(#"{"kind":"turn","chain":1}"#.utf8))
        #expect(b == Boundary(kind: .turn, chain: 1, countsAsStitch: false, color: nil))
        let full = try JSONDecoder().decode(Boundary.self, from: Data(#"{"kind":"join","chain":3,"counts_as_stitch":true,"color":"next"}"#.utf8))
        #expect(full == Boundary(kind: .join, chain: 3, countsAsStitch: true, color: .next))
    }

    @Test func boundaryRejectsUnknownKindAndMissingChain() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Boundary.self, from: Data(#"{"kind":"flip","chain":1}"#.utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Boundary.self, from: Data(#"{"kind":"turn"}"#.utf8)) }
    }

    @Test func stitchResolvesNameFromTermsOrOverride() {
        let sc = Stitch(code: "sc", terms: .us, stitchName: nil, boundary: nil)
        #expect(sc.name == "single crochet")
        let ukDC = Stitch(code: "dc", terms: .uk, stitchName: nil, boundary: nil)
        #expect(ukDC.name == "double crochet")
        let custom = Stitch(code: "hhdc", terms: .us, stitchName: "herringbone half double crochet", boundary: nil)
        #expect(custom.name == "herringbone half double crochet")
        let renamed = Stitch(code: "sc", terms: .us, stitchName: "not really", boundary: nil)
        #expect(renamed.name == "single crochet")  // a chart cannot rename a CYC stitch
        let unknown = Stitch(code: "xyz", terms: .us, stitchName: nil, boundary: nil)
        #expect(unknown.name == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && mise run core-test`
Expected: compile error, `cannot find 'StitchNames' in scope`.

- [ ] **Step 3: Implement `Stitch.swift`**

Create `ios/Packages/GraphghanCore/Sources/GraphghanCore/Stitch.swift`:

```swift
import Foundation

/// Terminology system of the abbreviations (docs/chart-format.md §Gauge). `dc`, `tr` and `htr`
/// collide between the two, so a reader never spells out without knowing which one applies.
public enum Terms: String, Codable, Sendable {
    case us = "US"
    case uk = "UK"
}

/// What happens at the end of a pass. Phase 1 readers act on `turn` and show nothing for the rest.
public enum BoundaryKind: String, Codable, Sendable {
    case turn, join, rejoin, spiral
    case `return`
}

public enum ChainColor: String, Codable, Sendable {
    case next, current
}

/// `gauge.boundary`, exactly as authored. Never derived from the stitch: published patterns split
/// on the number (dc is ch 3 in 7 of 12 corpus patterns and ch 2 in the other 5).
public struct Boundary: Codable, Equatable, Sendable {
    public let kind: BoundaryKind
    public let chain: Int
    public let countsAsStitch: Bool
    public let color: ChainColor?

    public init(kind: BoundaryKind, chain: Int, countsAsStitch: Bool = false, color: ChainColor? = nil) {
        self.kind = kind; self.chain = chain; self.countsAsStitch = countsAsStitch; self.color = color
    }

    enum CodingKeys: String, CodingKey { case kind, chain, countsAsStitch = "counts_as_stitch", color }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(BoundaryKind.self, forKey: .kind)
        chain = try c.decode(Int.self, forKey: .chain)
        countsAsStitch = try c.decodeIfPresent(Bool.self, forKey: .countsAsStitch) ?? false
        color = try c.decodeIfPresent(ChainColor.self, forKey: .color)
    }
}

/// The stitch a chart is worked in, resolved from `gauge.stitch`, `gauge.terms`, `gauge.stitch_name`
/// and `gauge.boundary`. `name` is nil for an abbreviation the tables do not know and the chart
/// did not name; the UI then shows the abbreviation alone.
public struct Stitch: Equatable, Sendable {
    public let code: String
    public let terms: Terms
    public let boundary: Boundary?
    public let name: String?

    public init(code: String, terms: Terms, stitchName: String?, boundary: Boundary?) {
        self.code = code
        self.terms = terms
        self.boundary = boundary
        // The CYC table wins over stitch_name so a chart cannot rename `sc` (spec §6.1).
        self.name = StitchNames.name(code, terms: terms) ?? stitchName
    }
}

/// The Craft Yarn Council master abbreviation list, one table per terminology system.
public enum StitchNames {
    static let us: [String: String] = [
        "ch": "chain", "sl st": "slip stitch", "sc": "single crochet", "hdc": "half double crochet",
        "dc": "double crochet", "tr": "treble crochet", "dtr": "double treble crochet",
        "trtr": "triple treble crochet", "sc2tog": "single crochet 2 together",
        "dc2tog": "double crochet 2 together", "hdc2tog": "half double crochet 2 together",
        "fsc": "foundation single crochet", "fdc": "foundation double crochet",
    ]
    static let uk: [String: String] = [
        "ch": "chain", "ss": "slip stitch", "sl st": "slip stitch", "dc": "double crochet", "htr": "half treble",
        "tr": "treble", "dtr": "double treble", "trtr": "triple treble", "qtr": "quadruple treble",
        "dc2tog": "double crochet 2 together", "tr2tog": "treble 2 together",
    ]

    public static func name(_ code: String, terms: Terms) -> String? {
        let key = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        switch terms {
        case .us: return us[key]
        case .uk: return uk[key]
        }
    }
}
```

- [ ] **Step 4: Run the Core tests**

Run: `cd ios && mise run core-test`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore/Sources/GraphghanCore/Stitch.swift ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/StitchTests.swift
git commit -m "core: Stitch, Boundary, Terms and the CYC name tables"
```

---

### Task 7: `ChartDocument` decodes the new keys and `foundation`

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ChartDocument.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartDocumentTests.swift`

**Interfaces:**
- Consumes: `Boundary`, `Terms` (Task 6).
- Produces: `ChartDocument.Gauge.unit: String?`, `.stitchName: String?`, `.terms: Terms?`, `.termsAlso: Terms?`, `.boundary: Boundary?`; `ChartDocument.PatternInfo.craft: String?`, `.language: String?`; `ChartDocument.Foundation { chain: Int, firstStitchIn: Int?, note: String? }` and `ChartDocument.foundation: Foundation?`. A `boundary` object that fails to decode (unknown `kind`, missing `chain`) yields `nil` while the rest of `gauge` loads; an unknown `terms` string yields `nil` likewise.

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite struct ChartDocumentTests` in `ChartDocumentTests.swift`:

```swift
    @Test func phase1KeysDecode() throws {
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1","craft":"crochet","language":"en"},
         "chart":{"id":"sha256:x","width":1,"height":1},
         "palette":[{"code":"A","name":"a","hex":"#000000"}],"rows":["1A"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"sc","unit":"stitches",
                  "stitch_name":"single crochet","terms":"US","terms_also":"UK",
                  "boundary":{"kind":"turn","chain":1,"counts_as_stitch":false,"color":"next"}},
         "technique":{"type":"rows"},
         "foundation":{"chain":2,"first_stitch_in":2,"note":"in a (A)"}}
        """#
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(doc.pattern.craft == "crochet" && doc.pattern.language == "en")
        #expect(doc.gauge.unit == "stitches" && doc.gauge.stitchName == "single crochet")
        #expect(doc.gauge.terms == .us && doc.gauge.termsAlso == .uk)
        #expect(doc.gauge.boundary == Boundary(kind: .turn, chain: 1, countsAsStitch: false, color: .next))
        let f = try #require(doc.foundation)
        #expect(f.chain == 2 && f.firstStitchIn == 2 && f.note == "in a (A)")
    }

    @Test func phase1KeysAbsentAreNil() throws {
        let doc = try ChartDocument.decode(Fixtures.data("minimal-rows.chart.json"))
        #expect(doc.pattern.craft == nil && doc.pattern.language == nil)
        #expect(doc.gauge.unit == nil && doc.gauge.stitchName == nil && doc.gauge.terms == nil && doc.gauge.termsAlso == nil)
        #expect(doc.gauge.boundary == nil && doc.foundation == nil)
    }

    @Test func unknownBoundaryKindOrTermsDecodesAsAbsent() throws {
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"sha256:x","width":1,"height":1},
         "palette":[{"code":"A","name":"a","hex":"#000000"}],"rows":["1A"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"sc","terms":"AU",
                  "boundary":{"kind":"somersault","chain":1}},
         "technique":{"type":"rows"}}
        """#
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(doc.gauge.stitch == "sc")       // the rest of gauge still loads
        #expect(doc.gauge.boundary == nil && doc.gauge.terms == nil)
    }

    @Test func craighCarriesItsStitch() throws {
        let doc = try ChartDocument.decode(Fixtures.data("craigh-na-dun.chart.json"))
        #expect(doc.gauge.terms == .us)
        #expect(doc.gauge.boundary == Boundary(kind: .turn, chain: 1, countsAsStitch: false, color: .next))
        #expect(doc.foundation?.chain == 190 && doc.foundation?.firstStitchIn == 2)
        #expect(doc.pattern.craft == "crochet")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && mise run core-test`
Expected: compile errors on `craft`, `unit`, `boundary`, `foundation`.

- [ ] **Step 3: Implement**

In `ChartDocument.swift`:

`PatternInfo` — add after `public let url: String?`:

```swift
        public let craft: String?
        public let language: String?
```

`Gauge` — replace the struct with:

```swift
    public struct Gauge: Decodable, Sendable {
        public struct Over: Decodable, Sendable {
            public let value: Double
            public let unit: String
        }
        public let stitches: Double
        public let rows: Double
        public let over: Over
        public let stitch: String?
        public let hook: String?
        public let yarnWeight: String?
        public let unit: String?
        public let stitchName: String?
        public let terms: Terms?
        public let termsAlso: Terms?
        /// nil when absent — and when present but not understood (an unknown `kind`, a missing
        /// `chain`), so a future kind reads as "no boundary" instead of failing the chart.
        public let boundary: Boundary?

        enum CodingKeys: String, CodingKey {
            case stitches, rows, over, stitch, hook, yarnWeight = "yarn_weight"
            case unit, stitchName = "stitch_name", terms, termsAlso = "terms_also", boundary
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            stitches = try c.decode(Double.self, forKey: .stitches)
            rows = try c.decode(Double.self, forKey: .rows)
            over = try c.decode(Over.self, forKey: .over)
            stitch = try c.decodeIfPresent(String.self, forKey: .stitch)
            hook = try c.decodeIfPresent(String.self, forKey: .hook)
            yarnWeight = try c.decodeIfPresent(String.self, forKey: .yarnWeight)
            unit = try c.decodeIfPresent(String.self, forKey: .unit)
            stitchName = try c.decodeIfPresent(String.self, forKey: .stitchName)
            terms = (try? c.decodeIfPresent(Terms.self, forKey: .terms)) ?? nil
            termsAlso = (try? c.decodeIfPresent(Terms.self, forKey: .termsAlso)) ?? nil
            boundary = (try? c.decodeIfPresent(Boundary.self, forKey: .boundary)) ?? nil
        }
    }
```

Add a new nested type after `Instruction`:

```swift
    /// Top-level `foundation`: authored, never cross-checked against `chart.width`.
    public struct Foundation: Decodable, Sendable, Equatable {
        public let chain: Int
        public let firstStitchIn: Int?
        public let note: String?
        enum CodingKeys: String, CodingKey { case chain, firstStitchIn = "first_stitch_in", note }
    }
```

Add the stored property after `public let instructions: [Instruction]`:

```swift
    public let foundation: Foundation?
```

Add `foundation` to `CodingKeys` (`case schema, pattern, chart, generator, palette, rows, layers, gauge, technique, passes, instructions, foundation`) and in `init(from:)` after the `instructions` line:

```swift
        foundation = try c.decodeIfPresent(Foundation.self, forKey: .foundation)
```

- [ ] **Step 4: Run the Core tests**

Run: `cd ios && mise run core-test`
Expected: all PASS. (`craighCarriesItsStitch` needs Task 5's regenerated fixture; both are on this branch.)

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore/Sources/GraphghanCore/ChartDocument.swift ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartDocumentTests.swift
git commit -m "core: decode gauge.boundary/unit/terms/stitch_name, pattern.craft/language and foundation"
```

---

### Task 8: `Chart.stitch` and `Chart.foundation`

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Chart.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartTests.swift`

**Interfaces:**
- Consumes: `Stitch` (Task 6), `ChartDocument.Gauge`/`.foundation` (Task 7).
- Produces: `Chart.stitch: Stitch?` — nil when `gauge.stitch` is absent or empty; otherwise `Stitch(code:, terms: gauge.terms ?? .us, stitchName: gauge.stitchName, boundary: gauge.boundary)`. `Chart.foundation: ChartDocument.Foundation?` passthrough.

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite struct ChartTests`:

```swift
    @Test func stitchIsResolvedFromGauge() throws {
        let craigh = try Self.chart("craigh-na-dun")
        let stitch = try #require(craigh.stitch)
        #expect(stitch.code == "sc" && stitch.name == "single crochet" && stitch.terms == .us)
        #expect(stitch.boundary?.kind == .turn && stitch.boundary?.chain == 1 && stitch.boundary?.color == .next)
        #expect(craigh.foundation?.chain == 190)
    }

    @Test func stitchIsNilWithoutAGaugeStitch() throws {
        // ChartTests.doc writes a gauge with no `stitch`
        let chart = try Chart(document: ChartDocument.decode(Self.doc(rows: ["2A2B", "4A"])))
        #expect(chart.stitch == nil && chart.foundation == nil)
    }

    @Test func termsDefaultToUSAndBoundaryIsNeverDerived() throws {
        let minimal = try Self.chart("minimal-rows")   // gauge.stitch = "sc", nothing else
        let stitch = try #require(minimal.stitch)
        #expect(stitch.terms == .us && stitch.name == "single crochet")
        #expect(stitch.boundary == nil)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && mise run core-test`
Expected: compile error, `value of type 'Chart' has no member 'stitch'`.

- [ ] **Step 3: Implement**

In `Chart.swift`, after `public var title: String { document.pattern.title }` add:

```swift
    /// The stitch the chart is worked in, from `gauge` only. Nil without `gauge.stitch`; the
    /// boundary comes from the document or not at all (spec §6.3: never derived).
    public var stitch: Stitch? {
        guard let code = document.gauge.stitch, !code.isEmpty else { return nil }
        return Stitch(code: code, terms: document.gauge.terms ?? .us, stitchName: document.gauge.stitchName, boundary: document.gauge.boundary)
    }

    public var foundation: ChartDocument.Foundation? { document.foundation }
```

- [ ] **Step 4: Run the Core tests**

Run: `cd ios && mise run core-test`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore/Sources/GraphghanCore/Chart.swift ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartTests.swift
git commit -m "core: Chart.stitch and Chart.foundation"
```

---

### Task 9: `WorkActivityInfo` carries the stitch and the turning chain

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/LiveActivityState.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/LiveActivityStateTests.swift`

**Interfaces:**
- Consumes: `Chart.stitch` (Task 8).
- Produces: `WorkActivityInfo.stitch: String?` (the abbreviation) and `WorkActivityInfo.turningChain: Int?` (the chain count, set only when `boundary.kind == .turn`), both defaulting to `nil` in the memberwise `init` so existing call sites compile. `LiveActivityState.info(...)` fills them from `chart.stitch`.

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite struct LiveActivityStateTests`:

```swift
    @Test func infoCarriesStitchAndTurningChain() throws {
        let craigh = try Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
        let info = LiveActivityState.info(projectID: UUID(), chart: craigh, sequence: try WorkSequence(chart: craigh))
        #expect(info.stitch == "sc" && info.turningChain == 1)
        let plain = LiveActivityState.info(projectID: UUID(), chart: Self.chart, sequence: Self.seq)  // two-letter-codes: no boundary
        #expect(plain.stitch == "sc" && plain.turningChain == nil)
    }

    @Test func turningChainIsNilForOtherBoundaryKinds() throws {
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"ID","width":2,"height":1},
         "palette":[{"code":"A","name":"a","hex":"#000000"}],"rows":["2A"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"dc","boundary":{"kind":"join","chain":3}},
         "technique":{"type":"rounds"}}
        """#
        let id = ChartID.compute(codes: ["A"], rows: ["2A"], technique: .object(["type": .string("rounds")]), passes: nil)
        let chart = try Chart.load(Data(json.replacingOccurrences(of: "\"ID\"", with: "\"\(id)\"").utf8))
        let info = LiveActivityState.info(projectID: UUID(), chart: chart, sequence: try WorkSequence(chart: chart))
        #expect(info.stitch == "dc" && info.turningChain == nil)
    }

    @Test func infoRoundTripsThroughCodable() throws {
        let craigh = try Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
        let info = LiveActivityState.info(projectID: UUID(), chart: craigh, sequence: try WorkSequence(chart: craigh))
        let back = try JSONDecoder().decode(WorkActivityInfo.self, from: JSONEncoder().encode(info))
        #expect(back == info)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && mise run core-test`
Expected: compile error, `value of type 'WorkActivityInfo' has no member 'stitch'`.

- [ ] **Step 3: Implement**

In `LiveActivityState.swift`, replace `WorkActivityInfo` with:

```swift
/// Static attributes of one project's activity (spec §7). `stitch` and `turningChain` are static
/// for a project, so they live here rather than in the state.
public struct WorkActivityInfo: Codable, Hashable, Sendable {
    public let projectID: UUID
    public let title: String
    public let totalRows: Int
    public let totalStitches: Int
    public let palette: [ActivitySwatch]
    /// The abbreviation the chart is worked in (`gauge.stitch`), when the chart says.
    public let stitch: String?
    /// Chains to make at the turn, only for a `turn` boundary; nil means the chart does not say.
    public let turningChain: Int?
    public init(projectID: UUID, title: String, totalRows: Int, totalStitches: Int, palette: [ActivitySwatch],
                stitch: String? = nil, turningChain: Int? = nil) {
        self.projectID = projectID; self.title = title; self.totalRows = totalRows; self.totalStitches = totalStitches; self.palette = palette
        self.stitch = stitch; self.turningChain = turningChain
    }
    public func swatch(for code: String) -> ActivitySwatch? { palette.first { $0.code == code } }
}
```

and replace `LiveActivityState.info` with:

```swift
    public static func info(projectID: UUID, chart: Chart, sequence: WorkSequence) -> WorkActivityInfo {
        let stitch = chart.stitch
        let chain: Int? = stitch?.boundary.flatMap { $0.kind == .turn ? $0.chain : nil }
        return WorkActivityInfo(projectID: projectID, title: chart.title, totalRows: sequence.passes.count, totalStitches: sequence.totalStitches,
                                palette: chart.palette.map { ActivitySwatch(code: $0.code, name: $0.name, hex: $0.hex) },
                                stitch: stitch?.code, turningChain: chain)
    }
```

Because `Codable` synthesis is automatic and the new properties are optionals, an activity info encoded by an older build decodes with both `nil`.

- [ ] **Step 4: Run the Core tests**

Run: `cd ios && mise run core-test`
Expected: all PASS, including the unchanged `infoCarriesPalette`.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore/Sources/GraphghanCore/LiveActivityState.swift ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/LiveActivityStateTests.swift
git commit -m "core: WorkActivityInfo.stitch and turningChain"
```

---

### Task 10: `OnDeckRule` — the chain at the end of a row, the foundation at the start

**Files:**
- Modify: `ios/Graphghan/Work/OnDeckRule.swift`
- Test: `ios/Tests/OnDeckRuleTests.swift`

**Interfaces:**
- Consumes: `Chart.stitch`, `Chart.foundation` (Task 8).
- Produces: `OnDeckRule.onDeck(cursor:chart:sequence:)` unchanged in signature. Text rules (spec §6.4):
  - last run of a row, `turn` boundary, chain N > 0: `"ch N, turn — next row starts in <Name>"`; with `color == .next`: `"ch N in <Name>, turn — next row starts in <Name>"`; with `countsAsStitch`: append `" (counts as a st)"`; chain 0: `"turn — next row starts in <Name>"`.
  - last run of a row, any other kind or no boundary: `"next row starts in <Name>"` (today's text).
  - `cursor == .start` with a `foundation`: `"Chain <chain>, first <code> in the <ordinal> chain"` (`first_stitch_in` absent ⇒ `"Chain <chain>"`), hex of the first run's colour. Without a foundation, today's text.
  - `OnDeckRule.ordinal(2) == "2nd"`, `ordinal(3) == "3rd"`, `ordinal(4) == "4th"`, `ordinal(11) == "11th"`, `ordinal(22) == "22nd"`.

- [ ] **Step 1: Write the failing tests**

Replace `ios/Tests/OnDeckRuleTests.swift` with:

```swift
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct OnDeckRuleTests {
    // two-letter-codes: Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3 ; no stitch fields
    static let chart = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static func name(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].name }
    static func hex(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].hex }

    /// The same two rows with an authored stitch, boundary and foundation.
    static func authored(boundary: String, foundation: String? = "\"foundation\":{\"chain\":13,\"first_stitch_in\":2},") -> Chart {
        let rows = ["7Gd2G3Y", "2G7Gd3Kb"]
        let id = ChartID.compute(codes: ["G", "Gd", "Kb", "Y"], rows: rows, technique: .object(["type": .string("rows")]), passes: nil)
        let json = """
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\(id)","width":12,"height":2},
         "palette":[{"code":"G","name":"Green","hex":"#1E4D3A"},{"code":"Gd","name":"Gold","hex":"#D9A21B"},
                    {"code":"Kb","name":"Charcoal","hex":"#2B2F33"},{"code":"Y","name":"Cream","hex":"#F2E8D5"}],
         "rows":["7Gd2G3Y","2G7Gd3Kb"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"sc","terms":"US","boundary":\(boundary)},
         "technique":{"type":"rows"},\(foundation ?? "")"instructions":[]}
        """
        return try! Chart.load(Data(json.utf8))
    }

    @Test func nextRunInRow() {
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 0), chart: Self.chart, sequence: Self.seq)
        #expect(d?.text == "then 7 \(Self.name("Gd"))")
        #expect(d?.hex == Self.hex("Gd"))
    }

    @Test func lastRunInRowNamesNextRowsColor() {
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: Self.chart, sequence: Self.seq)
        #expect(d?.text == "next row starts in \(Self.name("Gd"))")
        #expect(d?.hex == Self.hex("Gd"))
    }

    @Test func lastRunOfPatternHasNothingOnDeck() {
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 2, run: 2), chart: Self.chart, sequence: Self.seq) == nil)
    }

    @Test func turnBoundaryPrependsTheChain() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":1}"#)
        let seq = try WorkSequence(chart: chart)
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq)
        #expect(d?.text == "ch 1, turn — next row starts in Gold")
        #expect(d?.hex == "#D9A21B")
    }

    @Test func chainColorAndCountsAsStitchAreSpelledOut() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":2,"counts_as_stitch":true,"color":"next"}"#)
        let seq = try WorkSequence(chart: chart)
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq)
        #expect(d?.text == "ch 2 in Gold, turn — next row starts in Gold (counts as a st)")
    }

    @Test func zeroChainStillSaysTurn() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":0}"#)
        let seq = try WorkSequence(chart: chart)
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq)?.text == "turn — next row starts in Gold")
    }

    @Test func otherBoundaryKindsLeaveTheLineAlone() throws {
        let chart = Self.authored(boundary: #"{"kind":"join","chain":3}"#)
        let seq = try WorkSequence(chart: chart)
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq)?.text == "next row starts in Gold")
    }

    @Test func foundationShowsAtTheStartOnly() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":1}"#)
        let seq = try WorkSequence(chart: chart)
        let start = OnDeckRule.onDeck(cursor: .start, chart: chart, sequence: seq)
        #expect(start?.text == "Chain 13, first sc in the 2nd chain")
        #expect(start?.hex == "#2B2F33")  // Row 1 reads right to left: Kb first
        let second = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 1), chart: chart, sequence: seq)
        #expect(second?.text == "then 2 Green")
    }

    @Test func noFoundationMeansTodaysText() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":1}"#, foundation: nil)
        let seq = try WorkSequence(chart: chart)
        #expect(OnDeckRule.onDeck(cursor: .start, chart: chart, sequence: seq)?.text == "then 7 Gold")
    }

    @Test func ordinals() {
        #expect(OnDeckRule.ordinal(1) == "1st" && OnDeckRule.ordinal(2) == "2nd" && OnDeckRule.ordinal(3) == "3rd")
        #expect(OnDeckRule.ordinal(4) == "4th" && OnDeckRule.ordinal(11) == "11th" && OnDeckRule.ordinal(12) == "12th")
        #expect(OnDeckRule.ordinal(13) == "13th" && OnDeckRule.ordinal(22) == "22nd" && OnDeckRule.ordinal(103) == "103rd")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && mise run test`
Expected: compile error on `OnDeckRule.ordinal`; the new text expectations would fail after that.

- [ ] **Step 3: Implement**

Replace `ios/Graphghan/Work/OnDeckRule.swift` with:

```swift
import GraphghanCore

/// What sits under the current swatch (spec §6.1): the next run, the next row's first color, or nothing.
struct OnDeck: Hashable {
    let text: String
    let hex: String
}

enum OnDeckRule {
    static func onDeck(cursor: Cursor, chart: Chart, sequence: WorkSequence) -> OnDeck? {
        guard let pass = sequence.pass(at: cursor.row) else { return nil }
        func entry(_ code: String) -> (name: String, hex: String) {
            let e = chart.palette[chart.colorIndex(of: code) ?? 0]
            return (e.name, e.hex)
        }
        // At the very start the line is the foundation, when the chart states one (spec §6.4).
        if cursor == .start, let foundation = chart.foundation, let first = pass.runs.first {
            var text = "Chain \(foundation.chain)"
            if let into = foundation.firstStitchIn {
                let stitch = chart.stitch?.code ?? "stitch"
                text += ", first \(stitch) in the \(ordinal(into)) chain"
            }
            return OnDeck(text: text, hex: entry(first.code).hex)
        }
        if cursor.run + 1 < pass.runs.count {
            let next = pass.runs[cursor.run + 1]
            let e = entry(next.code)
            return OnDeck(text: "then \(next.count) \(e.name)", hex: e.hex)
        }
        if let nextPass = sequence.pass(at: cursor.row + 1), let first = nextPass.runs.first {
            let e = entry(first.code)
            var text = "next row starts in \(e.name)"
            // Only a `turn` boundary changes the line; other kinds are for later readers (spec §6.1).
            if let boundary = chart.stitch?.boundary, boundary.kind == .turn {
                let chain: String
                if boundary.chain > 0 {
                    chain = boundary.color == .next ? "ch \(boundary.chain) in \(e.name), turn" : "ch \(boundary.chain), turn"
                } else {
                    chain = "turn"
                }
                text = "\(chain) — \(text)"
                if boundary.countsAsStitch { text += " (counts as a st)" }
            }
            return OnDeck(text: text, hex: e.hex)
        }
        return nil
    }

    /// 1 → "1st", 2 → "2nd", 11 → "11th", 22 → "22nd".
    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if (11...13).contains(tens) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}
```

- [ ] **Step 4: Run the app tests**

Run: `cd ios && mise run test`
Expected: `OnDeckRuleTests` all PASS. `WorkScreenTests.lastRunInRow` will now FAIL because the Craigh na Dun fixture carries a boundary and the on-deck line changed — that is expected and is re-recorded in Task 11, Step 5. Do not re-record yet.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/OnDeckRule.swift ios/Tests/OnDeckRuleTests.swift
git commit -m "work: on-deck line carries the turning chain; foundation at the start"
```

---

### Task 11: The stitch badge and the accessible Done label

**Files:**
- Modify: `ios/Graphghan/Work/DoneField.swift` (`WorkFieldContent`, the current column)
- Modify: `ios/Graphghan/Work/WorkScreen.swift` (`fieldContent`, `doneLabel`)
- Test: `ios/Tests/WorkScreenTests.swift` (+ snapshots under `ios/Tests/__Snapshots__/`)

**Interfaces:**
- Consumes: `Chart.stitch` (Task 8), `OnDeckRule` (Task 10).
- Produces: `WorkFieldContent.stitch: String?` (the abbreviation, drawn as a capsule beside the count in `Font.Heather.label`, stroked and tinted with the column's `doneForeground`); `WorkScreen.doneLabel` reads `"Done with 4 single crochet in Charcoal"` when the stitch name is known, `"Done with 4 sc in Charcoal"` with only a code, and today's `"Done with 4 Charcoal"` without a stitch.

- [ ] **Step 1: Write the failing tests**

Append inside `@Suite struct WorkScreenTests`:

```swift
    @Test func doneLabelSpellsOutTheStitch() {
        // Craigh na Dun: gauge.stitch = sc, terms = US
        let label = WorkScreen.doneLabel(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 42, run: 8))
        let run = Self.seq.pass(at: 42)!.runs[8]
        let name = Self.chart.palette[Self.chart.colorIndex(of: run.code)!].name
        #expect(label == "Done with \(run.count) single crochet in \(name)")
        // two-letter-codes: gauge.stitch = sc with no terms → US → still named; palette names are "Color <code>"
        let plainChart = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let plainSeq = try! WorkSequence(chart: plainChart)
        #expect(WorkScreen.doneLabel(chart: plainChart, sequence: plainSeq, cursor: .start) == "Done with 3 single crochet in Color Kb")
        // a chart with no gauge.stitch keeps today's label
        let end = Cursor(row: Self.seq.passes.count, run: Self.seq.passes.last!.runs.count)
        #expect(WorkScreen.doneLabel(chart: Self.chart, sequence: Self.seq, cursor: end) == "Close")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && mise run test`
Expected: compile error, `type 'WorkScreen' has no member 'doneLabel'`.

- [ ] **Step 3: Implement the content and the badge**

In `DoneField.swift`, replace `WorkFieldContent`:

```swift
struct WorkFieldContent: Equatable {
    let count: Int
    let code: String
    let name: String
    let onDeck: String?
    /// The stitch abbreviation, when the chart states one; drawn as a small capsule by the count.
    var stitch: String? = nil
}
```

In the current column's `VStack` (inside `glass(zones:)`), replace

```swift
                        Text("\(content.count)").font(Font.Heather.count).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
```

with

```swift
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(content.count)").font(Font.Heather.count).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            if let stitch = content.stitch {
                                Text(stitch)
                                    .font(Font.Heather.label)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .overlay(Capsule().strokeBorder(doneForeground.opacity(0.6), lineWidth: 1.5))
                                    .accessibilityHidden(true)  // the Done label already spells the stitch out
                            }
                        }
```

`doneForeground` is already a property of `WorkField`, so the capsule takes the column's own ink; no new colour token, so `DesignRulesTests` stays green.

- [ ] **Step 4: Wire the screen**

In `WorkScreen.swift`, replace `fieldContent` and `doneLabel`:

```swift
    private var fieldContent: WorkFieldContent? {
        guard !finished, let pass = sequence.pass(at: cursor.row), let entry = currentEntry else { return nil }
        return WorkFieldContent(count: pass.runs[cursor.run].count, code: entry.code, name: entry.name,
                                onDeck: OnDeckRule.onDeck(cursor: cursor, chart: chart, sequence: sequence)?.text,
                                stitch: chart.stitch?.code)
    }

    private var doneLabel: String { Self.doneLabel(chart: chart, sequence: sequence, cursor: cursor) }

    /// "Done with 4 single crochet in Charcoal": the stitch name when the chart states one the
    /// tables know, its abbreviation otherwise, nothing when the chart is silent (spec §6.4).
    static func doneLabel(chart: Chart, sequence: WorkSequence, cursor: Cursor) -> String {
        guard !WorkEngine.isFinished(cursor, in: sequence) else { return "Close" }
        guard let pass = sequence.pass(at: cursor.row), cursor.run < pass.runs.count else { return "Done" }
        let run = pass.runs[cursor.run]
        let entry = chart.palette[chart.colorIndex(of: run.code) ?? 0]
        if let stitch = chart.stitch {
            return "Done with \(run.count) \(stitch.name ?? stitch.code) in \(entry.name)"
        }
        return "Done with \(run.count) \(entry.name)"
    }
```

- [ ] **Step 5: Re-record the Work screen snapshots and run the app tests**

Run:

```bash
cd ios && TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record mise run test
git status --short Tests/__Snapshots__
```

Expected: exactly `work-mid-row.png`, `work-mid-row-ax5.png`, `work-last-in-row.png` and `work-finished.png` (unchanged content but re-recorded) change under `ios/Tests/__Snapshots__/`; open `work-last-in-row.png` and confirm the line reads `ch 1 in <colour>, turn — next row starts in <colour>` and the `sc` capsule sits beside the count; confirm `work-mid-row-ax5.png` shows nothing clipped or overlapping the Done field at accessibility size 5. If the capsule pushes the count off the column at ax5, wrap the `HStack` in `ViewThatFits(in: .horizontal) { hstack; Text("\(content.count)")... }` so the badge drops first.

Then run without recording: `cd ios && mise run test`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/Graphghan/Work/DoneField.swift ios/Graphghan/Work/WorkScreen.swift ios/Tests/WorkScreenTests.swift ios/Tests/__Snapshots__
git commit -m "work: stitch badge by the count; Done label spells out the stitch"
```

---

### Task 12: Live Activity says "ch N, turn"

**Files:**
- Modify: `ios/Shared/WorkActivityViews.swift` (`RunPanel.nextText`)
- Test: `ios/Tests/WorkActivityViewsTests.swift` (+ `lock-last-in-row.png`)

**Interfaces:**
- Consumes: `WorkActivityInfo.turningChain` (Task 9).
- Produces: on the last run of a row the panel's trailing text is `"ch N, turn"` when `info.turningChain` is set (`"turn"` for 0), else today's `"last in row"`.

- [ ] **Step 1: Write the failing test**

`ios/Tests/WorkActivityViewsTests.swift` builds `static let info` with `LiveActivityState.info(...)` from the Craigh na Dun fixture, so after Tasks 5 and 9 it already carries `stitch == "sc"` and `turningChain == 1`; `lastInRow` is `Cursor(row: 1, run: 0)` (row 1 is one run of 189 Y). The `lock-last-in-row` snapshot therefore changes on its own. Add a pure-text test next to the snapshot tests:

```swift
    @Test func lastInRowTextNamesTheChain() {
        #expect(Self.info.turningChain == 1)  // from the fixture, via LiveActivityState.info
        #expect(RunPanel.nextText(info: Self.info, state: Self.lastInRow) == "ch 1, turn")
        let plain = WorkActivityInfo(projectID: Self.info.projectID, title: Self.info.title, totalRows: Self.info.totalRows,
                                     totalStitches: Self.info.totalStitches, palette: Self.info.palette)
        #expect(RunPanel.nextText(info: plain, state: Self.lastInRow) == "last in row")
        let zero = WorkActivityInfo(projectID: Self.info.projectID, title: "t", totalRows: 1, totalStitches: 1, palette: [], stitch: "sc", turningChain: 0)
        #expect(RunPanel.nextText(info: zero, state: Self.lastInRow) == "turn")
        #expect(RunPanel.nextText(info: Self.info, state: Self.midway).hasPrefix("then "))
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios && mise run test`
Expected: compile error — `RunPanel` is `private` and has no static `nextText`.

- [ ] **Step 3: Implement**

In `ios/Shared/WorkActivityViews.swift`, change `private struct RunPanel: View` to `struct RunPanel: View` and replace its `nextText`:

```swift
    private var nextText: String { Self.nextText(info: info, state: state) }

    /// The trailing line of the panel: the next run, or what to do at the end of the row.
    static func nextText(info: WorkActivityInfo, state: WorkActivityState) -> String {
        if let code = state.nextCode, let count = state.nextCount { return "then \(count) \(info.swatch(for: code)?.name ?? code)" }
        guard state.isLastInRow else { return "" }
        if let chain = info.turningChain { return chain > 0 ? "ch \(chain), turn" : "turn" }
        return "last in row"
    }
```

- [ ] **Step 4: Re-record the one snapshot and run the app tests**

Run:

```bash
cd ios && TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record mise run test
git status --short Tests/__Snapshots__
```

Expected: only `lock-last-in-row.png` differs in content (it now reads `ch 1, turn`); others re-record byte-identical or with no visible change. Look at the PNG. Then `cd ios && mise run test` → all PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Shared/WorkActivityViews.swift ios/Tests/WorkActivityViewsTests.swift ios/Tests/__Snapshots__
git commit -m "live activity: last run of a row says ch N, turn"
```

---

### Task 13: Full verification and the pull request

**Files:**
- None new. Read: `docs/superpowers/specs/2026-09-12-pattern-data-model-design.md` §6.5–6.6.

- [ ] **Step 1: Run everything**

```bash
mise run check
cd ios && mise run core-test && mise run script-test && mise run test && cd ..
git diff --stat main..HEAD -- fixtures/ | cat
```

Expected: all green; the fixtures diff lists **only** `craigh-na-dun.chart.json`.

- [ ] **Step 2: Confirm the id invariant one more way**

```bash
uv run python -c "import json;print(json.load(open('patterns/craigh-na-dun/dist/chart.json'))['chart']['id'])"
git show main:patterns/craigh-na-dun/dist/chart.json | uv run python -c "import json,sys;print(json.load(sys.stdin)['chart']['id'])"
```

Expected: both print `sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f`.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin tylervick/stitch-boundary-phase1
gh pr create --base main --title "Stitch and boundary: Phase 1 of the pattern data model" --body "$(cat <<'EOF'
Implements Phase 1 of `docs/superpowers/specs/2026-09-12-pattern-data-model-design.md` (§6).

- Format: `gauge.boundary {kind, chain, counts_as_stitch, color}`, `gauge.unit`, `gauge.terms` / `terms_also`, `gauge.stitch_name`, `pattern.craft` / `language`, top-level `foundation`; all optional, all outside the `chart.id` hash. Schema, doc, and a structural check for `boundary`.
- Generator: `[stitch.<gauge_key>]` and `[pattern].craft/terms/terms_also/language` in `pattern.toml`; `chart_json` copies what is authored and invents nothing; written rows print `ch N, turn` from row 2.
- Craigh na Dun authored (sc ch 1, hdc ch 2, US terms, foundation 190). **Chart id unchanged** — pinned by `test_craigh_chart_id_is_stable_across_phase1`.
- `GraphghanCore`: `Stitch.swift` (US/UK CYC tables, `Boundary`), new document keys with lenient `boundary` decode, `Chart.stitch` / `.foundation`, `WorkActivityInfo.stitch` / `.turningChain`.
- App: on-deck line carries the chain (and the foundation at the start), a stitch capsule by the count, Done spells out the stitch for VoiceOver, the lock screen says `ch 1, turn`.

No change to `Run`, `Pass`, `WorkSequence`, the pinned sequences, the site or the PWA. Phase 1 acts on `kind: turn` only; #43, #48, #49 carry the rest.

Closes #25.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01U2LQf4NDtt3KiGxcftN8eR
EOF
)"
```

- [ ] **Step 4: Watch CI**

Run: `gh pr checks --watch`
Expected: `test`, `ios-changes`, `ios` green. The `ios` job renders snapshots in `render` mode; if it fails on a snapshot, download the `ios-snapshots` artifact and compare against the re-recorded PNGs before touching anything.

---

## Self-review against the spec

- §6.1 schema — Task 1 (schema + doc), Task 3 (structural check). ✔
- §6.2 `pattern.toml` and generator — Task 2 (loader), Task 3 (`chart_json`, foundation chain = width + first_stitch_in − 1), Task 4 (written rows), Task 5 (Craigh na Dun sc ch 1 / hdc ch 2 with the corpus caveat as a TOML comment). The spec's `boundary = "turn"` default when `chain` is authored — Task 2. ✔
- §6.3 reader — Tasks 6, 7, 8, 9; unknown `kind` decodes as no boundary (Task 7); `Run`/`Pass`/`WorkSequence` untouched. ✔
- §6.4 app — Task 10 (on-deck: chain, colour, counts-as, foundation), Task 11 (badge, Done label), Task 12 (Live Activity). ✔
- §6.5 fixtures, docs, tests — Task 1 (doc incl. the RS-face legend note), Task 5 (fixture regenerates, set unchanged, id-stable test), Swift tests per task, snapshots re-recorded in Tasks 11–12. Deviation recorded in Task 4: the stitch abbreviation is not added to the written-rows line body because the site contract test parses it. ✔
- §6.6 compatibility — id pinned (Tasks 3, 5, 13); `WorkActivityInfo` fields optional with defaults so stale activity payloads still decode (Task 9). ✔
- Not in scope, on purpose: the site manifest gaining `craft` (#49), rendering `instructions[]` in the app (#40), other boundary kinds (#43).
