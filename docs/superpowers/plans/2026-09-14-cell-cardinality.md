# Cell Cardinality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a chart declare what one grid cell is, and stop every reader from reporting stitch counts, yarn and pace for a chart whose cells are not stitches.

**Architecture:** One optional object, `chart.cell: {kind}`, defaulting to `stitch` when absent. Numbers that count cells are renamed to say so and are always emitted; numbers that count stitches are emitted only when the kind is `stitch`, and are otherwise **absent** rather than zero or null. `cell` joins the `chart.id` canonical form when present, on the rule `passes` already follows, so no existing id moves. Python leads, Swift mirrors, and a filet fixture pins both.

**Tech Stack:** Python 3 (`uv run pytest`), Swift 6 / SwiftUI (`mise run core-test`, `mise run test` in `ios/`), vanilla JS for the site, JSON Schema Draft 2020-12.

**Spec:** `docs/superpowers/specs/2026-09-14-cell-cardinality-design.md`

## Global Constraints

- `kind` is exactly one of `stitch`, `block`, `tile`, `motif`, `pair`. The enum is closed; a value outside it fails schema validation and the document is refused.
- Absent `chart.cell` means `kind: "stitch"`. No existing document is edited, and **every existing `chart.id` must stay byte-identical** — Task 1 pins this with a test.
- A withheld number is an **absent key**. Never `0`, never `null`, never a renamed key holding the same value.
- Cell-counting numbers (`stats.cells`, `total_cells`, `cells_done`, `percent`) are emitted for every chart including `stitch` ones, where they equal the stitch figures.
- The generator authors no `cell` in this plan: `pattern.toml` gains no surface (spec §4.4). The withholding paths are exercised by fixtures and tests only.
- `WorkActivityInfo`'s **encoded** key stays `totalStitches` (`CodingKeys`), because a Live Activity started before an app upgrade decodes with the old key. Only the Swift property name moves.
- Python: run `uv run pytest -q` from the repo root. Swift package: `mise run core-test` from `ios/`. App: `mise run test` from `ios/`. Lint: `mise run lint`.
- Commit after every task. Conventional-commit subjects, matching the repo's existing style (`format:`, `work:`, `docs:`).

---

### Task 1: `cell` joins the chart id

**Files:**
- Modify: `src/graphghan/chartdoc.py:36-40` (`chart_id`)
- Test: `tests/test_chartdoc.py` (add tests; extend the `doc()` helper at `:9-28`)

**Interfaces:**
- Consumes: nothing.
- Produces: `chartdoc.chart_id(codes, rows, technique, passes=None, cell=None) -> str`. `cell` is included in the canonical object only when it `isinstance(cell, dict)` — the same presence-and-type guard `passes` uses. Later tasks call it with `cell=doc["chart"].get("cell")`.
- Produces: `doc(rows, codes=..., technique=None, passes=None, width=None, layers=None, cell=None)` test helper, which puts `cell` into `d["chart"]["cell"]` and passes it to `chart_id` so the built document's id is self-consistent.

- [ ] **Step 1: Write the failing tests**

In `tests/test_chartdoc.py`, after `test_chart_id_is_canonical_sha256_and_ignores_names`:

```python
def test_chart_id_unchanged_when_cell_absent():
    """Every id in the repo predates `cell`; none of them may move."""
    rows = ["2A2B", "4A"]
    t = dict(chartdoc.TECHNIQUE_ROWS)
    assert chartdoc.chart_id(["A", "B"], rows, t) == chartdoc.chart_id(["A", "B"], rows, t, cell=None)


def test_chart_id_includes_cell_when_present():
    rows = ["2A2B", "4A"]
    t = dict(chartdoc.TECHNIQUE_ROWS)
    plain = chartdoc.chart_id(["A", "B"], rows, t)
    block = chartdoc.chart_id(["A", "B"], rows, t, cell={"kind": "block"})
    assert block != plain
    canonical = json.dumps(
        {"cell": {"kind": "block"}, "codes": ["A", "B"], "rows": rows, "technique": t},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    assert block == "sha256:" + hashlib.sha256(canonical).hexdigest()


def test_chart_id_ignores_a_non_object_cell():
    """Same guard `passes` uses: a wrong-typed value is not hashed, it is caught by validation."""
    rows = ["2A2B", "4A"]
    t = dict(chartdoc.TECHNIQUE_ROWS)
    assert chartdoc.chart_id(["A", "B"], rows, t, cell="block") == chartdoc.chart_id(["A", "B"], rows, t)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest tests/test_chartdoc.py -k chart_id -v`
Expected: FAIL — `TypeError: chart_id() got an unexpected keyword argument 'cell'`

- [ ] **Step 3: Add the parameter**

In `src/graphghan/chartdoc.py`, replace `chart_id`:

```python
def chart_id(
    codes: list[str],
    rows: list[str],
    technique: dict,
    passes: list[dict] | None = None,
    cell: dict | None = None,
) -> str:
    obj = {"codes": list(codes), "rows": list(rows), "technique": technique}
    if passes is not None:
        obj["passes"] = passes
    if isinstance(cell, dict):  # presence-and-type, exactly as `passes` is guarded at the call site
        obj["cell"] = cell
    return "sha256:" + hashlib.sha256(_canonical(obj)).hexdigest()
```

- [ ] **Step 4: Extend the test helper**

In `tests/test_chartdoc.py`, replace the `doc()` signature and its `chart` block:

```python
def doc(rows, codes=("A", "B"), technique=None, passes=None, width=None, layers=None, cell=None):
    technique = technique or dict(chartdoc.TECHNIQUE_ROWS)
    chart = {
        "id": chartdoc.chart_id(list(codes), rows, technique, passes, cell),
        "width": width or 4,
        "height": len(rows),
    }
    if cell is not None:
        chart["cell"] = cell
    d = {
        "schema": 2,
        "pattern": {"id": "t", "title": "T", "version": "0.0.1"},
        "chart": chart,
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
```

- [ ] **Step 5: Thread `cell` through the id check in `validate_document`**

In `src/graphghan/chartdoc.py`, replace the `expected = chart_id(...)` line near the end of `validate_document`:

```python
    expected = chart_id(
        codes,
        rows,
        doc.get("technique") or {},
        passes if isinstance(passes, list) else None,
        doc.get("chart", {}).get("cell"),
    )
```

- [ ] **Step 6: Run the full Python suite**

Run: `uv run pytest -q`
Expected: PASS, all tests. Every existing fixture id still verifies — that is the compatibility claim from spec §4.7, now enforced.

- [ ] **Step 7: Commit**

```bash
git add src/graphghan/chartdoc.py tests/test_chartdoc.py
git commit -m "format: chart.cell joins the chart id when present"
```

---

### Task 2: Declare `chart.cell` in the schema and refuse a bad one

**Files:**
- Modify: `schema/chart.schema.json` (`properties.chart.properties`)
- Modify: `src/graphghan/chartdoc.py` (add `CELL_KINDS` and `cell_kind()` near `BOUNDARY_KINDS` at `:21`; add a validation block in `validate_document`)
- Test: `tests/test_chartdoc.py`, `tests/test_conformance.py`

**Interfaces:**
- Consumes: `chart_id(..., cell=...)` from Task 1.
- Produces: `chartdoc.CELL_KINDS = ("stitch", "block", "tile", "motif", "pair")` and `chartdoc.cell_kind(doc: dict) -> str`, returning `"stitch"` for an absent or unreadable declaration. Every later task reads the kind through `cell_kind`, never by poking at the dict.

- [ ] **Step 1: Write the failing tests**

In `tests/test_chartdoc.py`:

```python
def test_cell_kind_defaults_to_stitch():
    assert chartdoc.cell_kind(doc(["4A"])) == "stitch"
    assert chartdoc.cell_kind({}) == "stitch"


def test_cell_kind_reads_a_declared_kind():
    assert chartdoc.cell_kind(doc(["4A"], cell={"kind": "block"})) == "block"


def test_validate_accepts_every_declared_kind():
    for kind in chartdoc.CELL_KINDS:
        assert chartdoc.validate_document(doc(["4A"], cell={"kind": kind})) == []


def test_validate_refuses_an_unknown_cell_kind():
    problems = chartdoc.validate_document(doc(["4A"], cell={"kind": "sparkle"}))
    assert any("chart.cell.kind" in p and "sparkle" in p for p in problems)


def test_validate_refuses_a_non_object_cell():
    """#55's shape: report the field and its type, never silently skip the block."""
    d = doc(["4A"])
    d["chart"]["cell"] = "block"
    problems = chartdoc.validate_document(d)
    assert any("chart.cell" in p and "str" in p for p in problems)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest tests/test_chartdoc.py -k cell -v`
Expected: FAIL — `AttributeError: module 'graphghan.chartdoc' has no attribute 'cell_kind'`

- [ ] **Step 3: Add the constant and the accessor**

In `src/graphghan/chartdoc.py`, after `CHAIN_COLORS` (line 22):

```python
# What one grid cell is. Absent means `stitch` (docs/chart-format.md §Cells); a reader that does
# not implement a kind still opens the chart and withholds the stitch-derived numbers (#44).
CELL_KINDS = ("stitch", "block", "tile", "motif", "pair")


def cell_kind(doc: dict) -> str:
    cell = doc.get("chart", {}).get("cell")
    if isinstance(cell, dict) and cell.get("kind") in CELL_KINDS:
        return cell["kind"]
    return "stitch"
```

- [ ] **Step 4: Add the validation block**

In `validate_document`, immediately after the `foundation` block and before `expected = chart_id(...)`:

```python
    cell = doc.get("chart", {}).get("cell")
    if cell is not None:
        if not isinstance(cell, dict):
            problems.append(f"chart.cell is {type(cell).__name__}, not an object")
        elif cell.get("kind") not in CELL_KINDS:
            problems.append(f"chart.cell.kind {cell.get('kind')!r} is not one of {CELL_KINDS}")
```

- [ ] **Step 5: Add the schema property**

In `schema/chart.schema.json`, inside `properties.chart.properties`, after `"height"`:

```json
"cell": {
  "type": "object",
  "required": ["kind"],
  "properties": {
    "kind": { "enum": ["stitch", "block", "tile", "motif", "pair"] }
  }
}
```

- [ ] **Step 6: Add the schema-level test**

In `tests/test_conformance.py`, inside `test_schema_rejects_bad_documents`, add a case alongside the existing ones (follow the local style for building an invalid document — copy a valid fixture, mutate, assert `iter_errors` is non-empty):

```python
    bad_cell = json.loads((FIX / "minimal-rows.chart.json").read_text(encoding="utf-8"))
    bad_cell["chart"]["cell"] = {"kind": "sparkle"}
    assert list(Draft202012Validator(CHART_SCHEMA).iter_errors(bad_cell)) != []
```

- [ ] **Step 7: Run the suite**

Run: `uv run pytest -q`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add schema/chart.schema.json src/graphghan/chartdoc.py tests/test_chartdoc.py tests/test_conformance.py
git commit -m "format: declare chart.cell and refuse an unknown kind"
```

---

### Task 3: Withhold the stitch-derived stats

**Files:**
- Modify: `src/graphghan/export.py:96-122` (`stats`), `:223` (the `chart_json` call site)
- Modify: `src/graphghan/chartdoc.py` (`validate_document`: refuse a document whose stats contradict its kind)
- Test: `tests/test_export.py`, `tests/test_chartdoc.py`

**Interfaces:**
- Consumes: `chartdoc.cell_kind`, `chartdoc.CELL_KINDS` from Task 2.
- Produces: `export.stats(a, codes, kind="stitch") -> dict`. Always carries `cells`, `size_in`, `counts`, `single_stitch_runs`, `color_changes_per_row`. Carries `stitches`, `yards_est`, `skeins_364yd` only when `kind == "stitch"`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_export.py`:

```python
def test_stats_always_reports_cells():
    a, codes = _grid()  # use this module's existing grid helper
    s = export.stats(a, codes)
    assert s["cells"] == a.shape[0] * a.shape[1]
    assert s["stitches"] == s["cells"]


def test_stats_withholds_stitch_numbers_for_a_non_stitch_kind():
    a, codes = _grid()
    s = export.stats(a, codes, kind="block")
    assert "stitches" not in s
    assert "yards_est" not in s
    assert "skeins_364yd" not in s
    # Cell-counting numbers stay: they are honest whatever a cell is.
    assert s["cells"] == a.shape[0] * a.shape[1]
    assert s["counts"] and s["color_changes_per_row"]
```

If `tests/test_export.py` has no grid helper, build one inline in each test with
`numpy.zeros((3, 4), dtype=numpy.uint8)` and `codes = ["A"]`, matching how the other tests in that
file construct a grid.

In `tests/test_chartdoc.py`:

```python
def test_validate_refuses_stats_that_contradict_the_cell_kind():
    d = doc(["4A"], cell={"kind": "block"})
    d["stats"] = {"cells": 4, "stitches": 4}
    problems = chartdoc.validate_document(d)
    assert any("stats.stitches" in p and "block" in p for p in problems)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest tests/test_export.py -k stats tests/test_chartdoc.py -k contradict -v`
Expected: FAIL — `TypeError: stats() got an unexpected keyword argument 'kind'`, and the validator test finds no problem.

- [ ] **Step 3: Rewrite `stats`**

In `src/graphghan/export.py`, replace the `return {...}` at the end of `stats` (and its signature):

```python
def stats(a, codes, kind="stitch"):
    h, w = a.shape
    counts = {codes[i]: int((a == i).sum()) for i in range(len(codes))}
    runs = rle_rows(a)
    singles = {c: 0 for c in codes}
    per_row = []
    for row in runs:
        per_row.append(len(row) - 1)
        for c, n in row:
            if n == 1:
                singles[codes[c]] += 1
    cell_sqin = gr.SW * gr.SH
    yards = {
        code: n * cell_sqin * 1.1 * 1.2 for code, n in counts.items()
    }  # 1.1 yd/sq in worsted sc, +20% tails
    out = {
        "cells": int(w * h),
        "size_in": [round(w * gr.SW, 1), round(h * gr.SH, 1)],
        "counts": counts,
        "single_stitch_runs": singles,
        "color_changes_per_row": {
            "mean": round(sum(per_row) / len(per_row), 1),
            "max": max(per_row),
            "per_row": per_row,
        },
    }
    if kind == "stitch":
        # Every number below counts stitches. A cell is only a stitch when the chart says so, and
        # a missing key cannot be misread the way a wrong number can (#44).
        out["stitches"] = int(w * h)
        out["yards_est"] = {k: int(round(v)) for k, v in yards.items()}
        out["skeins_364yd"] = {k: round(v / 364, 1) for k, v in yards.items()}
    return out
```

- [ ] **Step 4: Add the validator gate**

In `src/graphghan/chartdoc.py`, extend the block added in Task 2 so it also refuses a contradictory
`stats` — this is what makes `write_dist` unable to emit one, since `write_dist` validates before
writing:

```python
    kind = cell_kind(doc)
    if kind != "stitch":
        st = doc.get("stats")
        if isinstance(st, dict):
            for key in ("stitches", "yards_est", "skeins_364yd"):
                if key in st:
                    problems.append(
                        f"stats.{key} counts stitches, but chart.cell.kind is {kind!r}"
                    )
```

- [ ] **Step 5: Run the tests**

Run: `uv run pytest tests/test_export.py tests/test_chartdoc.py -q`
Expected: PASS. Any existing assertion on `stats["stitches"]` still passes — the generator authors no `cell`, so its kind is `stitch` and the key is present.

- [ ] **Step 6: Run the full suite**

Run: `uv run pytest -q`
Expected: PASS. If a published fixture's `stats` is compared key-for-key, add `"cells"` to it with the same value as `"stitches"`.

- [ ] **Step 7: Commit**

```bash
git add src/graphghan/export.py src/graphghan/chartdoc.py tests/test_export.py tests/test_chartdoc.py
git commit -m "format: stats report cells always, stitches only when a cell is one"
```

---

### Task 4: Withhold the stitch-derived progress numbers

**Files:**
- Modify: `src/graphghan/progress.py:18-30` (rename), `:33-66` (`summarize`)
- Modify: `tests/test_conformance.py:101` (pass the kind)
- Modify: `fixtures/chart-format/progress-basic.progress.expected.json`
- Test: `tests/test_progress.py`

**Interfaces:**
- Consumes: `chartdoc.cell_kind` from Task 2.
- Produces: `progress.total_cells(passes) -> int` and `progress.cells_before(passes, row, run) -> int` (renamed from `total_stitches` / `stitches_before`; no aliases are kept — the old names counted cells and said stitches, which is the bug).
- Produces: `progress.summarize(doc, passes, gap_seconds=GAP_SECONDS, kind="stitch") -> dict`. Always carries `percent`, `cells_done`, `total_cells`, `sessions`, `active_seconds`; session entries always carry `cells`. Carries `stitches_done`, `total_stitches`, `stitches_per_hour` only when `kind == "stitch"`, and session entries carry `stitches` only then.

**Note for the reviewer:** the spec's §4.3 table does not name `sessions[].stitches`. It counts cells by the same argument as the rest, so this task renames it to `cells` and adds `stitches` alongside for the `stitch` kind. If that reads as scope creep, drop the session half and keep `stitches` as-is; nothing else in the plan depends on it.

- [ ] **Step 1: Write the failing tests**

In `tests/test_progress.py`, alongside the existing `summarize` tests:

```python
def test_summarize_reports_cells_and_stitches_for_a_stitch_chart():
    doc = _doc_with_events()  # reuse this module's existing fixture builder
    s = progress.summarize(doc, PASSES)
    assert s["total_cells"] == s["total_stitches"]
    assert s["cells_done"] == s["stitches_done"]
    assert s["sessions"][0]["cells"] == s["sessions"][0]["stitches"]


def test_summarize_withholds_stitch_numbers_for_a_non_stitch_kind():
    doc = _doc_with_events()
    s = progress.summarize(doc, PASSES, kind="block")
    assert "total_stitches" not in s
    assert "stitches_done" not in s
    assert "stitches_per_hour" not in s
    assert all("stitches" not in sess for sess in s["sessions"])
    # Progress itself is unchanged: cells done over cells total is the same arithmetic.
    assert s["percent"] == progress.summarize(doc, PASSES)["percent"]
    assert s["total_cells"] == progress.summarize(doc, PASSES)["total_cells"]
```

Replace `_doc_with_events()` with whatever the module already uses to build a progress document with
events — the existing tests at `:43`, `:60`, `:72`, `:89` and `:100` show the shape; reuse it rather
than inventing a second one.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest tests/test_progress.py -k "cells or withholds" -v`
Expected: FAIL — `KeyError: 'total_cells'`

- [ ] **Step 3: Rename the two counters**

In `src/graphghan/progress.py`, rename and update the docstring:

```python
def total_cells(passes: list[dict]) -> int:
    return sum(r["count"] for p in passes for r in p["runs"])


def cells_before(passes: list[dict], row: int, run: int) -> int:
    """Cells completed when the cursor sits at (row, run): every earlier pass plus runs before `run`."""
```

The body of `cells_before` is unchanged. Update the two internal call sites inside `summarize`
(`stitches_before(passes, cur["row"], cur["run"])` and `stitches_before(passes, *s["to"])` /
`*s["from"]`) and the `raise ValueError` message, which stays accurate as written.

- [ ] **Step 4: Rewrite the `summarize` return**

Replace the signature, the first line, the session accumulation and the return:

```python
def summarize(doc: dict, passes: list[dict], gap_seconds: int = GAP_SECONDS, kind: str = "stitch") -> dict:
    total = total_cells(passes)
    cur = doc["cursor"]
    done = cells_before(passes, cur["row"], cur["run"])
```

```python
    out_sessions, active, advanced = [], 0, 0
    for s in sessions:
        st = max(0, cells_before(passes, *s["to"]) - cells_before(passes, *s["from"]))
        secs = int((s["end"] - s["start"]).total_seconds())
        active += secs
        advanced += st
        entry = {"start": _fmt(s["start"]), "end": _fmt(s["end"]), "cells": st}
        if kind == "stitch":
            entry["stitches"] = st
        out_sessions.append(entry)
    out = {
        "percent": round(100.0 * done / total, 1) if total else 0.0,
        "cells_done": done,
        "total_cells": total,
        "sessions": out_sessions,
        "active_seconds": active,
    }
    if kind == "stitch":
        out["stitches_done"] = done
        out["total_stitches"] = total
        out["stitches_per_hour"] = round(advanced / (active / 3600.0), 1) if active else None
    return out
```

- [ ] **Step 5: Update the conformance call site and the fixture**

In `tests/test_conformance.py:101`:

```python
    assert progress.summarize(doc, chartdoc.sequence(chart), kind=chartdoc.cell_kind(chart)) == expected
```

In `fixtures/chart-format/progress-basic.progress.expected.json`, add the cell keys beside the
stitch ones (the fixture's chart is a `stitch` chart, so both are present and equal):

```json
{
  "percent": 34.5,
  "cells_done": 58,
  "total_cells": 168,
  "stitches_done": 58,
  "total_stitches": 168,
  "sessions": [
    { "start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:10:00Z", "cells": 30, "stitches": 30 },
    { "start": "2026-09-12T19:00:00Z", "end": "2026-09-12T19:04:00Z", "cells": 10, "stitches": 10 },
    { "start": "2026-09-13T10:00:00Z", "end": "2026-09-13T10:15:00Z", "cells": 18, "stitches": 18 }
  ],
  "active_seconds": 1740,
  "stitches_per_hour": 120.0
}
```

- [ ] **Step 6: Fix the remaining call sites**

Run: `grep -rn "total_stitches\|stitches_before" src/ tests/ site/src`
Expected: no hits in `src/graphghan/progress.py` for the old names. Update any other caller the grep
finds (for example `src/graphghan/cli.py` or `publish.py`) to the new names, reading the kind with
`chartdoc.cell_kind(chart)` wherever a chart document is in hand.

- [ ] **Step 7: Run the full suite**

Run: `uv run pytest -q`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add src/graphghan/progress.py tests/ fixtures/chart-format/progress-basic.progress.expected.json
git commit -m "format: progress counts cells; stitch numbers only when a cell is one"
```

---

### Task 5: A filet fixture, so both languages are pinned

**Files:**
- Create: `fixtures/chart-format/filet-blocks.chart.json`
- Create: `fixtures/chart-format/filet-blocks.sequence.json`
- Modify: `fixtures/chart-format/generate.py`, `fixtures/chart-format/README.md`
- Test: `tests/test_conformance.py` (the existing parametrized fixture tests pick it up by name)

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: the fixture name `filet-blocks`, which Task 9's Swift conformance test also loads.

- [ ] **Step 1: Read how fixtures are produced**

Run: `cat fixtures/chart-format/generate.py && cat fixtures/chart-format/README.md`
The fixtures are generated, not hand-edited. Add the new chart to `generate.py` following the shape
of `minimal-rows`, then run the generator — do not write the JSON by hand.

- [ ] **Step 2: Add the chart to the generator**

In `fixtures/chart-format/generate.py`, add a fixture whose grid is the Bella Coco filet motif from
`docs/research/genres/filet.md`: a two-code palette (`F` filled, `O` open), 12 columns by 6 rows,
`technique: rows` with the repo's standard `TECHNIQUE_ROWS`, and:

```python
"chart": {"cell": {"kind": "block"}}
```

Its `chart.id` must be computed with `chartdoc.chart_id(codes, rows, technique, None, {"kind": "block"})`
— the generator should call `chart_id` rather than hard-coding a digest, as it does for the others.

Give the document a `stats` block produced by `export.stats(a, codes, kind="block")` if the
generator emits stats for its other fixtures; otherwise omit `stats` entirely.

- [ ] **Step 3: Run the generator**

Run: `uv run python fixtures/chart-format/generate.py`
Expected: `fixtures/chart-format/filet-blocks.chart.json` and `.sequence.json` are written.

- [ ] **Step 4: Verify the fixture opens, sequences, and withholds**

Run: `uv run pytest tests/test_conformance.py -q -k filet`
Expected: PASS — the fixture validates against the schema, its id verifies, and it sequences. Add
this assertion to `tests/test_conformance.py` if the parametrized tests do not already cover it:

```python
def test_filet_fixture_opens_and_withholds_stitch_numbers():
    chart = json.loads((FIX / "filet-blocks.chart.json").read_text(encoding="utf-8"))
    assert chartdoc.validate_document(chart) == []
    assert chartdoc.cell_kind(chart) == "block"
    assert chartdoc.sequence(chart)  # it is workable: it opens and sequences
    st = chart.get("stats") or {}
    assert "stitches" not in st and "yards_est" not in st and "skeins_364yd" not in st
```

- [ ] **Step 5: Document the fixture**

In `fixtures/chart-format/README.md`, add a line for `filet-blocks` saying what it pins: a chart
that opens, works and sequences, and whose stitch-derived numbers are absent because a cell is a
block.

- [ ] **Step 6: Run the full suite**

Run: `uv run pytest -q`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add fixtures/chart-format/ tests/test_conformance.py
git commit -m "format: filet conformance fixture, a chart whose cell is a block"
```

---

### Task 6: Swift — `CellKind` and decoding `chart.cell`

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ChartDocument.swift:19-26` (`ChartInfo`)
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Chart.swift` (add `cellKind`)
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartTests.swift`

**Interfaces:**
- Consumes: the `filet-blocks` fixture from Task 5.
- Produces: `public enum CellKind: String, Codable, Sendable { case stitch, block, tile, motif, pair }`, `ChartDocument.CellDeclaration` (`{ kind: CellKind }`), `ChartDocument.ChartInfo.cell: CellDeclaration?`, and `Chart.cellKind: CellKind` returning `.stitch` when absent. Tasks 8, 9 and 10 read `chart.cellKind` / `sequence.cellKind` and never the document directly.

- [ ] **Step 1: Write the failing test**

In `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartTests.swift`:

```swift
@Test func cellKindDefaultsToStitch() throws {
    let chart = try Fixtures.chart("minimal-rows")
    #expect(chart.cellKind == .stitch)
}

@Test func cellKindDecodesADeclaredKind() throws {
    let chart = try Fixtures.chart("filet-blocks")
    #expect(chart.cellKind == .block)
}
```

Use whatever fixture loader the test target already has; `Fixtures.chart(_:)` above stands for it.
Run `grep -rn "func chart(" ios/Packages/GraphghanCore/Tests` to find the real name first.

- [ ] **Step 2: Run the test to verify it fails**

Run (from `ios/`): `mise run core-test`
Expected: FAIL — `value of type 'Chart' has no member 'cellKind'`

- [ ] **Step 3: Add the enum and the declaration**

In `ios/Packages/GraphghanCore/Sources/GraphghanCore/Stitch.swift`, beside `BoundaryKind`:

```swift
/// What one grid cell is. Absent from a document means `.stitch`; a reader that does not implement
/// a kind still opens the chart and withholds every stitch-derived number (docs/chart-format.md §Cells).
public enum CellKind: String, Codable, Sendable {
    case stitch, block, tile, motif, pair
}
```

In `ChartDocument.swift`, add the nested type and extend `ChartInfo`:

```swift
    public struct CellDeclaration: Decodable, Sendable, Equatable {
        public let kind: CellKind
    }

    public struct ChartInfo: Decodable, Sendable {
        public let id: String
        public let variant: String?
        public let gaugeKey: String?
        public let width: Int
        public let height: Int
        public let cell: CellDeclaration?
        enum CodingKeys: String, CodingKey {
            case id, variant, gaugeKey = "gauge_key", width, height, cell
        }
    }
```

- [ ] **Step 4: Add the accessor**

In `Chart.swift`, beside `stitch`:

```swift
    /// What one grid cell is. `.stitch` unless the chart says otherwise.
    public var cellKind: CellKind { document.chart.cell?.kind ?? .stitch }
```

- [ ] **Step 5: Run the tests**

Run (from `ios/`): `mise run core-test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore/
git commit -m "core: decode chart.cell into a CellKind"
```

---

### Task 7: Swift — `cell` in the chart id

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ChartID.swift:10-20`
- Modify: the `ChartID.compute` call site (find with `grep -rn "ChartID.compute" ios/`)
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartIDTests.swift`

**Interfaces:**
- Consumes: Task 6's decoding.
- Produces: `ChartID.compute(codes:rows:technique:passes:cell:) -> String`, where `cell` is a `JSONValue?` included only when it is `.object` — mirroring Python's `isinstance(cell, dict)` guard from Task 1.

- [ ] **Step 1: Write the failing test**

```swift
@Test func chartIDIncludesCellWhenPresent() throws {
    let codes = ["A", "B"], rows = ["2A2B", "4A"]
    let technique = JSONValue.object([:])
    let plain = ChartID.compute(codes: codes, rows: rows, technique: technique, passes: nil, cell: nil)
    let block = ChartID.compute(codes: codes, rows: rows, technique: technique, passes: nil,
                                cell: .object(["kind": .string("block")]))
    #expect(plain != block)
}

@Test func filetFixtureIDVerifies() throws {
    // Cross-language: the id Python wrote for a cell-carrying document must verify here.
    let chart = try Fixtures.chart("filet-blocks")
    #expect(chart.id == chart.document.chart.id)
}
```

The second test passes only if `Chart.init(document:verifyID:)` recomputes the id including `cell`;
`Chart.load` verifies by default, so a mismatch throws before the expectation is reached.

- [ ] **Step 2: Run the test to verify it fails**

Run (from `ios/`): `mise run core-test`
Expected: FAIL — extra argument `cell` in call, and the filet fixture throws `ChartError` on id mismatch.

- [ ] **Step 3: Add the parameter**

```swift
    public static func compute(codes: [String], rows: [String], technique: JSONValue,
                               passes: JSONValue?, cell: JSONValue? = nil) -> String {
        var object: [String: JSONValue] = [
            "codes": .array(codes.map(JSONValue.string)),
            "rows": .array(rows.map(JSONValue.string)),
            "technique": technique,
        ]
        if let passes, case .array = passes { object["passes"] = passes }
        if let cell, case .object = cell { object["cell"] = cell }
        let canonical = CanonicalJSON.encode(.object(object))
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return prefix + digest.map { String(format: "%02x", $0) }.joined()
    }
```

Update the doc comment above it to name `cell` alongside `passes`.

- [ ] **Step 4: Pass the document's raw `cell` at the call site**

The call site verifies an id against the document. It needs the **raw** `cell` JSON, not the decoded
`CellDeclaration`, so the hash matches Python byte for byte. If `ChartDocument` does not already keep
the raw chart object, decode `cell` as a `JSONValue?` sibling on `ChartInfo`:

```swift
        public let cellRaw: JSONValue?
```

decoded from the same `cell` key with `try c.decodeIfPresent(JSONValue.self, forKey: .cell)`, and
pass `cellRaw` to `compute`. Keep the typed `cell` from Task 6 for reading the kind.

- [ ] **Step 5: Run the tests**

Run (from `ios/`): `mise run core-test`
Expected: PASS, including `filetFixtureIDVerifies`.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore/
git commit -m "core: chart.cell joins the chart id, matching the Python canonical form"
```

---

### Task 8: Swift — `WorkSequence.totalCells`

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/WorkSequence.swift:40,52-62`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/WorkSequenceTests.swift:65`

**Interfaces:**
- Consumes: `Chart.cellKind` from Task 6.
- Produces: `WorkSequence.cellKind: CellKind`, `WorkSequence.totalCells: Int`, `WorkSequence.totalStitches: Int?` (nil for a non-stitch kind), `Pass.cells: Int` (renamed from `Pass.stitches`). `init(passes:cellKind:)` defaults `cellKind` to `.stitch` so existing constructions compile unchanged.

- [ ] **Step 1: Write the failing test**

```swift
@Test func totalCellsIsTheDenominatorAndStitchesFollowTheKind() throws {
    let seq = try WorkSequence(chart: Fixtures.chart("craigh-na-dun"))
    #expect(seq.totalCells == 168)
    #expect(seq.totalStitches == 168)

    let filet = try WorkSequence(chart: Fixtures.chart("filet-blocks"))
    #expect(filet.totalCells > 0)
    #expect(filet.totalStitches == nil)
}
```

Replace `168` for `craigh-na-dun` with the value the existing test at `WorkSequenceTests.swift:65`
asserts, so the two agree.

- [ ] **Step 2: Run the test to verify it fails**

Run (from `ios/`): `mise run core-test`
Expected: FAIL — no member `totalCells`.

- [ ] **Step 3: Rename and add the kind**

```swift
    public var cells: Int { runs.reduce(0) { $0 + $1.count } }
```

(on `Pass`, replacing `stitches`), and on `WorkSequence`:

```swift
public struct WorkSequence: Sendable {
    public let passes: [Pass]
    public let cellKind: CellKind
    public let totalCells: Int
    private let before: [Int]  // cells before pass i (0-based)

    /// The stitch count, when a cell is a stitch. Nil otherwise: the number exists but this reader
    /// cannot compute it, and a wrong number is worse than none (#44).
    public var totalStitches: Int? { cellKind == .stitch ? totalCells : nil }

    public init(passes: [Pass], cellKind: CellKind = .stitch) {
        self.passes = passes
        self.cellKind = cellKind
        var before: [Int] = []
        var total = 0
        for p in passes { before.append(total); total += p.cells }
        self.before = before
        self.totalCells = total
    }
```

In `init(chart:)`, pass the chart's kind into every `self.init(passes:)` call:
`self.init(passes: ..., cellKind: chart.cellKind)`.

Rename `stitchesBefore(_:)` to `cellsBefore(_:)` and update its callers.

- [ ] **Step 4: Fix every call site**

Run: `grep -rn "totalStitches\|\.stitches\b\|stitchesBefore" ios/ --include='*.swift'`
Update each hit. `Pace.swift` and `LiveActivityState.swift` are Task 9; the app targets are Task 10.
If the package does not compile until those land, do Tasks 8, 9 and 10 back to back and commit at
the end of Task 9 instead — note it in the commit body rather than leaving the tree broken.

- [ ] **Step 5: Run the tests**

Run (from `ios/`): `mise run core-test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore/
git commit -m "core: WorkSequence counts cells; totalStitches is nil unless a cell is a stitch"
```

---

### Task 9: Swift — `ProgressSummary` and the Live Activity

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Pace.swift:3-22,31,63-66`
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/LiveActivityState.swift:12-27,71,86`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/PaceTests.swift`, `LiveActivityStateTests.swift`

**Interfaces:**
- Consumes: `WorkSequence.totalCells` / `.totalStitches` / `.cellKind` from Task 8.
- Produces: `Session.cells: Int`; `ProgressSummary` with `cellsDone: Int`, `totalCells: Int`, `stitchesDone: Int?`, `totalStitches: Int?`, `stitchesPerHour: Double?`; `WorkActivityInfo.totalCells: Int` **encoded as `totalStitches`**.

- [ ] **Step 1: Write the failing test**

```swift
@Test func summaryWithholdsStitchNumbersForANonStitchKind() throws {
    let seq = try WorkSequence(chart: Fixtures.chart("filet-blocks"))
    let s = Pace.summarize(events: [], cursor: .start, sequence: seq)
    #expect(s.totalCells == seq.totalCells)
    #expect(s.totalStitches == nil)
    #expect(s.stitchesDone == nil)
    #expect(s.stitchesPerHour == nil)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run (from `ios/`): `mise run core-test`
Expected: FAIL — no member `totalCells` on `ProgressSummary`.

- [ ] **Step 3: Rewrite `ProgressSummary`**

```swift
public struct Session: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let cells: Int
    public init(start: Date, end: Date, cells: Int) { self.start = start; self.end = end; self.cells = cells }
    public var seconds: Int { Int(end.timeIntervalSince(start).rounded(.down)) }
}

public struct ProgressSummary: Equatable, Sendable {
    public let percent: Double
    public let cellsDone: Int
    public let totalCells: Int
    public let sessions: [Session]
    public let activeSeconds: Int
    /// Stitch figures, present only when a cell is a stitch (#44).
    public let stitchesDone: Int?
    public let totalStitches: Int?
    public let stitchesPerHour: Double?
    public init(percent: Double, cellsDone: Int, totalCells: Int, sessions: [Session], activeSeconds: Int,
                stitchesDone: Int?, totalStitches: Int?, stitchesPerHour: Double?) {
        self.percent = percent; self.cellsDone = cellsDone; self.totalCells = totalCells
        self.sessions = sessions; self.activeSeconds = activeSeconds
        self.stitchesDone = stitchesDone; self.totalStitches = totalStitches; self.stitchesPerHour = stitchesPerHour
    }
}
```

In `Pace.summarize`, replace the opening two lines and the return:

```swift
        let total = sequence.totalCells
        let done = sequence.cellsBefore(cursor) ?? 0
```

```swift
        let isStitch = sequence.cellKind == .stitch
        return ProgressSummary(
            percent: total > 0 ? round1(100 * Double(done) / Double(total)) : 0,
            cellsDone: done, totalCells: total, sessions: sessions, activeSeconds: active,
            stitchesDone: isStitch ? done : nil,
            totalStitches: isStitch ? total : nil,
            stitchesPerHour: isStitch ? rate : nil
        )
```

and change `sessions.append(Session(start: s, end: e, stitches: ...))` to `cells:`, and
`let advanced = sessions.reduce(0) { $0 + $1.cells }`.

- [ ] **Step 4: Rename the Live Activity property, keeping its wire key**

In `LiveActivityState.swift`:

```swift
public struct WorkActivityInfo: Codable, Hashable, Sendable {
    public let projectID: UUID
    public let title: String
    public let totalRows: Int
    public let totalCells: Int
    public let palette: [ActivitySwatch]
    public let stitch: String?
    public let turningChain: Int?

    // The encoded name stays `totalStitches`: an activity started before an app upgrade is still
    // running in the extension and decodes with the old key. Only the Swift name moves.
    enum CodingKeys: String, CodingKey {
        case projectID, title, totalRows, totalCells = "totalStitches", palette, stitch, turningChain
    }

    public init(projectID: UUID, title: String, totalRows: Int, totalCells: Int, palette: [ActivitySwatch],
                stitch: String? = nil, turningChain: Int? = nil) {
        self.projectID = projectID; self.title = title; self.totalRows = totalRows; self.totalCells = totalCells
        self.palette = palette; self.stitch = stitch; self.turningChain = turningChain
    }
    public func swatch(for code: String) -> ActivitySwatch? { palette.first { $0.code == code } }
}
```

Update `:71` (`let total = sequence.totalStitches`) to `sequence.totalCells` and `:86`
(`totalStitches: sequence.totalStitches`) to `totalCells: sequence.totalCells`.

- [ ] **Step 5: Add the wire-compatibility test**

In `LiveActivityStateTests.swift`:

```swift
@Test func activityInfoStillEncodesTheOldKey() throws {
    let info = WorkActivityInfo(projectID: UUID(), title: "t", totalRows: 2, totalCells: 24, palette: [])
    let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(info)) as! [String: Any]
    #expect(json["totalStitches"] as? Int == 24)
    #expect(json["totalCells"] == nil)
}
```

- [ ] **Step 6: Run the tests**

Run (from `ios/`): `mise run core-test`
Expected: PASS. Update `PaceTests.swift:8-11` and `:36` for the new field names; the decoder at `:11`
maps the progress document's `total_cells` and `cells_done` now, with `total_stitches` optional.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/GraphghanCore/
git commit -m "core: progress summaries count cells; the activity keeps its wire key"
```

---

### Task 10: The app reads its noun from the kind

**Files:**
- Modify: `ios/Graphghan/Projects/ProjectDetailView.swift:26`
- Modify: `ios/Graphghan/Work/OnDeckRule.swift:28`
- Test: `ios/Tests/` (the existing `WorkActivityViewsTests.swift` and any OnDeck tests)

**Interfaces:**
- Consumes: `ProgressSummary.cellsDone/.totalCells`, `Chart.cellKind` from Tasks 6 and 9.
- Produces: `CellKind.noun` / `.nounPlural` in `GraphghanCore` — `stitch`/`stitches`, `block`/`blocks`, `tile`/`tiles`, `motif`/`motifs`, `pair`/`pairs` — and `.label` (`"Stitches"`, `"Blocks"`, …) for a `LabeledContent` title.

- [ ] **Step 1: Add the nouns**

In `Stitch.swift`, beside the enum from Task 6:

```swift
public extension CellKind {
    var noun: String {
        switch self {
        case .stitch: "stitch"
        case .block: "block"
        case .tile: "tile"
        case .motif: "motif"
        case .pair: "pair"
        }
    }
    var nounPlural: String { self == .stitch ? "stitches" : noun + "s" }
    /// Title case, for a row label.
    var label: String { nounPlural.prefix(1).uppercased() + nounPlural.dropFirst() }
}
```

- [ ] **Step 2: Write the failing test**

```swift
@Test func cellKindNouns() {
    #expect(CellKind.stitch.nounPlural == "stitches")
    #expect(CellKind.block.label == "Blocks")
}
```

- [ ] **Step 3: Run it**

Run (from `ios/`): `mise run core-test`
Expected: FAIL first, then PASS after Step 1 is in place.

- [ ] **Step 4: Use the noun in the project detail row**

In `ProjectDetailView.swift:26`, replace the hard-coded label and the now-optional fields:

```swift
                    LabeledContent(chart.cellKind.label, value: "\(summary.cellsDone.formatted()) of \(summary.totalCells.formatted())")
```

The `Pace` row below it is already conditional on `if let rate = summary.stitchesPerHour`, so it
disappears for a non-stitch chart with no edit. Confirm `chart` is in scope at that line; if only
`sequence` is, use `sequence.cellKind`.

- [ ] **Step 5: Name the unit on the on-deck line, for non-stitch charts only**

In `OnDeckRule.swift:28`, today's line is `"then \(next.count) \(e.name)"` and must stay
byte-identical for a stitch chart — it is in the build testers are looking at right now:

```swift
            let noun = chart.cellKind == .stitch ? "" : " \(chart.cellKind.nounPlural)"
            return OnDeck(text: "then \(next.count) \(e.name)\(noun)", hex: e.hex)
```

- [ ] **Step 6: Run the app tests**

Run (from `ios/`): `mise run test`
Expected: PASS. Fix the `WorkActivityInfo(...)` constructions in `ios/Tests/WorkActivityViewsTests.swift:29,31` to use `totalCells:`.

- [ ] **Step 7: Commit**

```bash
git add ios/
git commit -m "work: labels name what a cell is instead of assuming a stitch"
```

---

### Task 11: The site stops saying "stitches" about cells

**Files:**
- Modify: `site/src/app/pattern.js:31,100`
- Test: `site/tests/` (follow the existing test style there), plus `tests/test_js_parity.py`

**Interfaces:**
- Consumes: the `cell.kind` key in the chart document.
- Produces: a `cellNoun(chart)` helper in `pattern.js` returning `"stitches"`, `"blocks"`, `"tiles"`, `"motifs"` or `"pairs"`.

- [ ] **Step 1: Add the helper and use it**

In `site/src/app/pattern.js`, near the top of the module:

```js
const CELL_NOUNS = { stitch: 'stitches', block: 'blocks', tile: 'tiles', motif: 'motifs', pair: 'pairs' };
const cellNoun = (C) => CELL_NOUNS[(C && C.cell && C.cell.kind) || 'stitch'] || 'stitches';
```

At `:31`, replace `'stitches × rows'` with a template using the noun, and at `:100` replace
`` `Every row totals ${chart.W} stitches` `` likewise. `C` is the chart object already in scope at
both sites (`C.variant` is read at `:33`); confirm the variable name before editing.

- [ ] **Step 2: Rebuild the site**

Run: `uv run python site/build.py`
Expected: `site/dist/` regenerates. `site/dist` is not tracked by git, so nothing is staged from it.

- [ ] **Step 3: Run the site and parity tests**

Run: `uv run pytest tests/test_js_parity.py site/tests -q`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add site/src/app/pattern.js site/tests
git commit -m "site: name the cell unit instead of always saying stitches"
```

---

### Task 12: Say it in the format doc and close the genre gap

**Files:**
- Modify: `docs/chart-format.md` (§Design, a new §Cells, §Chart id)
- Modify: `docs/research/genres/README.md` (the matrix row for filet)
- Modify: `docs/research/genres/filet.md` (the verdict line)

**Interfaces:**
- Consumes: everything above.
- Produces: the normative text every reader implements against.

- [ ] **Step 1: State the assumption in §Design**

In `docs/chart-format.md`, after the existing paragraph beginning "Nobody should be able to work a
chart that cannot be crocheted as written", add:

```markdown
One cell is one stitch unless the chart says otherwise. That is a real restriction, not a
simplification: the academic survey classifies this object as a "crochet graph" and limits the genre
to patterns "that are flat and whose arrangement of stitches matches a grid" (Seitz et al., Onward!
2022). Genres where a cell is a block, a tile, a motif or a stitch pair say so in `chart.cell`, and a
reader that does not implement the stated kind MUST withhold every stitch-derived number rather than
compute it wrongly. The chart still opens and is still worked: it is the arithmetic that is
withheld, not the pattern.
```

- [ ] **Step 2: Add §Cells**

After §"Palette and cells", add a new subsection carrying the table from spec §4.1 and the
withholding table from spec §4.3. Copy both verbatim from
`docs/superpowers/specs/2026-09-14-cell-cardinality-design.md`, adjusting only the cross-references
so they point at this document's own sections.

- [ ] **Step 3: Update §Chart id**

Replace the canonical sentence with:

```markdown
`chart.id` is `"sha256:" + hex(sha256(canonical))` where `canonical` is the UTF-8 JSON of
`{"codes": [palette codes in order], "rows": rows, "technique": technique}` plus `"passes"` when the
document has them and plus `"cell"` when the document has it and it is an object, with keys sorted,
no whitespace (`,` and `:` separators only) and non-ASCII kept as-is.
```

Leave the rest of the section, including the "renaming a color is not a new chart" sentence, as is.

- [ ] **Step 4: Move filet out of "silently wrong"**

In `docs/research/genres/README.md`, change the filet row's verdict from **silently wrong** to
**refuses** with a note that it opens and works while the stitch numbers are withheld, and update
the sentence below the table that reads "The single 'silently wrong' is filet" — there is now no
"silently wrong" row, which is the point. Cite
`docs/superpowers/specs/2026-09-14-cell-cardinality-design.md`.

In `docs/research/genres/filet.md`, update the verdict line at the top and the "Immediate fix"
section to record that the fix shipped, naming `chart.cell` and the `filet-blocks` fixture.

- [ ] **Step 5: Verify nothing else claims a cell is a stitch**

Run: `grep -rn "one cell is one stitch\|w \* h\|stitches = w" docs/ src/ site/src`
Expected: the only hits are the new normative text. Fix any stale prose the grep finds.

- [ ] **Step 6: Run everything**

Run: `uv run pytest -q && mise run lint`
Run (from `ios/`): `mise run core-test && mise run test`
Expected: PASS

- [ ] **Step 7: Commit and open the PR**

```bash
git add docs/
git commit -m "docs: one cell is one stitch unless the chart says otherwise"
```

Then open the PR with `Closes #44` **omitted** — part 1 only; the issue stays open for part 2 (spec
§5). Reference the spec and this plan in the body, and note that #55's `else:` shape is applied in
Task 2's validator block so that issue can close alongside.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §4.1 schema, enum, absent-means-stitch | 2 |
| §4.2 `cell` in `chart.id`, presence-and-type guard | 1 (Python), 7 (Swift) |
| §4.3 withholding table — stats | 3 |
| §4.3 withholding table — progress | 4 |
| §4.3 Swift rename, `WorkActivityInfo` wire key, `ProgressSummary` | 8, 9 |
| §4.3 two UI labels | 10 |
| §4.4 validator refuses a bad `cell`; `write_dist` cannot emit contradictory stats | 2, 3 |
| §4.4 no `pattern.toml` surface | (deliberately no task) |
| §4.5 docs | 12 |
| §4.6 fixtures and the genre-matrix move | 5, 12 |
| §4.7 every existing id unchanged | 1, Step 1 test |

No spec section is unimplemented. The site labels (§4.3's closing paragraph) are Task 11.

**Placeholder scan:** Three steps name a local helper the plan cannot know the spelling of —
`Fixtures.chart(_:)` (Tasks 6-9), `_grid()` (Task 3) and `_doc_with_events()` (Task 4). Each is
accompanied by the `grep` that finds the real name and an instruction to reuse the module's existing
helper rather than invent one. That is a lookup, not a placeholder; nothing is left to the
implementer's taste.

**Type consistency:** `cell_kind` (Python) / `cellKind` (Swift) are used consistently from their
defining tasks onward. `totalCells`/`totalStitches` keep the same types across Tasks 8, 9 and 10
(`Int` and `Int?` respectively). `Pass.stitches` → `Pass.cells` and `stitchesBefore` → `cellsBefore`
are renamed once in Task 8 and used under the new names in Task 9. `Session.stitches` →
`Session.cells` is renamed in Task 9 and matches the Python `sessions[].cells` from Task 4.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-14-cell-cardinality.md`.
