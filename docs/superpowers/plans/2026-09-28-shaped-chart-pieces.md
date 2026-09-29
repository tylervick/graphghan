# Shaped Chart Pieces (chart schema 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chart can be shaped: one palette colour marked `"stitch": false` sits only at the ends of rows, readers leave it out of the working order and every count, and Orca's front panel imports on the phone as 9 → 29 → 3 stitches that the Work screen walks without touching the light blue.

**Architecture:** The grid stays a rectangle (the picture). Chart schema 3 adds a no-stitch palette flag, a one-span-per-row rule, a no-stitch entry in the chart id, a foundation rule on pass 1's stitches, and optional per-pass `written` text. Both readers (Python `graphghan.chartdoc`, Swift `GraphghanCore`) implement it against new conformance fixtures; the phone's writer emits schema 3 exactly when #208 marked a background; the app draws no-stitch cells as ground and shows the row's stitch count, its shaping and its printed text.

**Tech Stack:** Python 3 (uv, pytest, jsonschema), Swift 6 / Swift Testing (`GraphghanCore` package, the iOS app target), SwiftUI Canvas, xcodebuild on the iPhone 17 simulator.

**Spec:** `docs/superpowers/specs/2026-09-25-pieces-and-shaped-rows-design.md` — this plan is §8's PR 1 ("Shaped chart pieces"), implementing §5.1 in full, the chart-piece half of §6.3, and the one-chart part of §7 that the importer already has. Read §5.1 before any task.

## Global Constraints

- Every existing chart, bundle and fixture reads unchanged and hashes the same (spec §10). A schema-2 chart's id, sequence, stats and manifest numbers must not move: every pre-existing test stays green without edits, except `ManifestWriterTests.aNoStitchColourIsWrittenAndNotCounted` (Task 4), whose "the id ignores it" assertion this spec deliberately reverses.
- "A writer emits schema 3 exactly when the palette has a no-stitch entry, and schema 2 otherwise" (spec §5.1).
- "At most one entry per chart may" carry `"stitch": false`; writers "also keep `use: "no stitch"` beside it" (spec §5.1).
- A schema-2 chart carrying only `use: "no stitch"` stays a rectangle: the label is a label (spec §5.1).
- The Python writes no schema-3 charts outside `fixtures/chart-format/generate.py` (spec §3.1, #214). `manifest.py` and `pdf.py` are not touched.
- Deployment target stays iOS 17; CI runs Xcode 26.2 while the mini has Xcode 27, so use no API newer than what the file already uses.
- Changing the format starts with a fixture (`docs/chart-format.md` §Conformance): Task 2's fixtures land before Task 3's Swift.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. If a commit leaves unstaged files around, commit with `HK_STASH=none git commit …` (the hk pre-commit stash fails on partial commits).
- App tests: `mise run test` from `ios/` (about five minutes). For a failing run add `-collect-test-diagnostics never`; `-only-testing:` takes the suite (`GraphghanTests/WorkScreenTests`), not a function. A second simulator, "iPhone 17 B", exists for a parallel run.

## Review Focus

1. **A chart worked from the top** (`technique.start: "top"`): the foundation must be checked against the top row's stitches, not the bottom's. Pinned in Task 1 (`test_foundation_reads_pass_1_at_the_top_when_start_is_top`) and Task 3 (`foundationReadsPassOneAtTheTop`).
2. **Explicit `passes` that list the no-stitch colour**: refused, in both readers, never worked as stitches. Pinned in Task 1 (`test_explicit_passes_may_not_list_the_no_stitch_colour`) and Task 3 (`explicitPassesMayNotListTheNoStitchColour`).
3. **`"stitch": false` on a schema-2 document**: an old reader would count it, so writers must not write it and readers refuse it. Pinned in Task 1 (`test_stitch_false_needs_schema_3`) and Task 3 (`stitchFalseNeedsSchema3`).
4. **The turn marker on a shaped row**: the boundary bar must stand at the span's end, where the maker turns, in both directions and in ribbon style, not at the chart's edge. Pinned in Task 5 (`BandLayoutTests.boundaryStandsAtTheStitchedSpansEnd`).
5. **Done never lands on a no-stitch cell**: walking a shaped row with Done goes from the last stitched run to the boundary to the next row's first stitched run. Pinned in Task 3 (`WorkEngineTests.doneWalksOnlyStitchedCells`).

---

### Task 1: Python reader — schema 3 rules, sequence, shaping

**Files:**
- Modify: `src/graphghan/chartdoc.py`
- Test: `tests/test_chartdoc.py`

**Interfaces:**
- Produces:
  - `chartdoc.no_stitch_code(doc: dict) -> str | None`
  - `chartdoc.chart_id(codes, rows, technique, passes=None, cell=None, no_stitch: str | None = None) -> str` (new trailing keyword)
  - `chartdoc.stitched_span(runs: list[dict]) -> tuple[int, int] | None` — `(lo, hi)` grid columns, `hi` exclusive
  - `chartdoc.shaping(passes: list[dict]) -> list[dict | None]` — per pass `{"start": int, "end": int}` or `None` (pass 1, or no `x0`/direction)
  - `chartdoc.sequence(doc)` leaves out runs of the no-stitch code (derived passes only)
  - `chartdoc.validate_document(doc)` gains the schema-3 problems below

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_chartdoc.py`:

```python
# ---- chart schema 3: shaped rows (spec 2026-09-25 §5.1) ----

SHAPED_ROWS = ["2N3A2N", "1N2A1B3A", "3A1B3A", "1N5A1N", "2N3A2N"]


def shaped(rows=None, schema=3, no_stitch=("N",), technique=None, passes=None, **extra):
    """A 7-wide shaped chart: A and B are yarns, N the ground no one stitches."""
    rows = list(rows or SHAPED_ROWS)
    technique = technique or dict(chartdoc.TECHNIQUE_ROWS)
    palette = [
        {"code": c, "name": c, "hex": h}
        for c, h in (("A", "#112233"), ("B", "#ffffff"), ("N", "#a4dade"))
    ]
    for p in palette:
        if p["code"] in no_stitch:
            p["stitch"] = False
            p["use"] = "no stitch"
    ns = no_stitch[0] if no_stitch else None
    d = {
        "schema": schema,
        "pattern": {"id": "s", "title": "S", "version": "0.0.1"},
        "chart": {
            "id": chartdoc.chart_id(["A", "B", "N"], rows, technique, passes, None, ns),
            "width": 7,
            "height": len(rows),
        },
        "palette": palette,
        "rows": rows,
        "gauge": {"stitches": 14, "rows": 16, "over": {"value": 4, "unit": "in"}, "stitch": "sc"},
        "technique": technique,
    }
    if passes is not None:
        d["passes"] = passes
    d.update(extra)
    return d


def test_a_shaped_chart_validates():
    assert chartdoc.validate_document(shaped()) == []
    assert chartdoc.no_stitch_code(shaped()) == "N"


def test_sequence_leaves_out_the_no_stitch_cells():
    passes = chartdoc.sequence(shaped())
    assert passes[0]["runs"] == [{"code": "A", "count": 3, "x0": 2}]
    assert passes[2]["runs"] == [
        {"code": "A", "count": 3, "x0": 4},
        {"code": "B", "count": 1, "x0": 3},
        {"code": "A", "count": 3, "x0": 0},
    ]
    assert sum(r["count"] for p in passes for r in p["runs"]) == 24


def test_shaping_names_each_edge_in_reading_direction():
    assert chartdoc.shaping(chartdoc.sequence(shaped())) == [
        None,
        {"start": 1, "end": 1},
        {"start": 1, "end": 1},
        {"start": -1, "end": 0},
        {"start": -2, "end": -1},
    ]


def test_shaping_is_none_without_grid_columns():
    passes = [{"label": "R1", "direction": "ltr", "runs": [{"code": "A", "count": 3}]}] * 2
    assert chartdoc.shaping(passes) == [None, None]


def test_chart_id_includes_the_no_stitch_code():
    t = dict(chartdoc.TECHNIQUE_ROWS)
    assert chartdoc.chart_id(["A", "N"], ["1N1A"], t) != chartdoc.chart_id(["A", "N"], ["1N1A"], t, no_stitch="N")
    assert chartdoc.chart_id(["A", "N"], ["1N1A"], t) == chartdoc.chart_id(["A", "N"], ["1N1A"], t, None, None, None)


def test_a_no_stitch_cell_between_stitches_is_refused():
    rows = list(SHAPED_ROWS)
    rows[0] = "1A1N5A"
    assert any("between stitches" in p for p in chartdoc.validate_document(shaped(rows)))


def test_a_row_of_only_no_stitch_is_refused():
    rows = list(SHAPED_ROWS)
    rows[0] = "7N"
    assert any("no stitches" in p for p in chartdoc.validate_document(shaped(rows)))


def test_two_no_stitch_colours_are_refused():
    assert any("at most one" in p for p in chartdoc.validate_document(shaped(no_stitch=("B", "N"))))


def test_stitch_false_needs_schema_3():
    assert any("schema 3" in p for p in chartdoc.validate_document(shaped(schema=2)))


def test_a_use_label_alone_leaves_a_schema_2_chart_rectangular():
    d = shaped(schema=2, no_stitch=())
    d["palette"][2]["use"] = "no stitch"
    assert chartdoc.validate_document(d) == []
    assert sum(r["count"] for p in chartdoc.sequence(d) for r in p["runs"]) == 35


def test_foundation_counts_pass_1s_stitches_not_the_width():
    assert chartdoc.validate_document(shaped(foundation={"chain": 4, "first_stitch_in": 2})) == []
    problems = chartdoc.validate_document(shaped(foundation={"chain": 3, "first_stitch_in": 2}))
    assert any("foundation" in p for p in problems), problems


def test_foundation_reads_pass_1_at_the_top_when_start_is_top():
    rows = ["1N5A1N", "3A1B3A", "2N3A2N"]
    top = dict(chartdoc.TECHNIQUE_ROWS, start="top")
    assert any(
        "foundation" in p
        for p in chartdoc.validate_document(shaped(rows, technique=top, foundation={"chain": 5, "first_stitch_in": 2}))
    )
    assert chartdoc.validate_document(shaped(rows, technique=top, foundation={"chain": 6, "first_stitch_in": 2})) == []
    assert chartdoc.validate_document(shaped(rows, foundation={"chain": 4, "first_stitch_in": 2})) == []


def test_explicit_passes_may_not_list_the_no_stitch_colour():
    passes = [{"label": "Row 1", "grid_row": 4, "runs": [{"code": "N", "count": 2, "x0": 0}]}]
    problems = chartdoc.validate_document(shaped(technique={"type": "none"}, passes=passes))
    assert any("no-stitch colour" in p for p in problems), problems


def test_written_has_one_entry_per_pass():
    ok = shaped(written=["R1", "R2", "R3", "R4", "R5"])
    assert chartdoc.validate_document(ok) == []
    assert any("written has 1" in p for p in chartdoc.validate_document(shaped(written=["R1"])))
    assert any("list of strings" in p for p in chartdoc.validate_document(shaped(written="R1")))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest tests/test_chartdoc.py -q -k "shaped or shaping or no_stitch or stitch_false or use_label or foundation_counts or pass_1 or explicit_passes_may or written"`
Expected: FAIL — `TypeError: chart_id() takes from 3 to 5 positional arguments but 6 were given` in the `shaped` helper, and `AttributeError: module 'graphghan.chartdoc' has no attribute 'no_stitch_code'`.

- [ ] **Step 3: Implement**

In `src/graphghan/chartdoc.py`:

1. Update the module docstring's first line to `"""Chart documents, schemas 2 and 3: run strings, chart ids, technique sequencing, validation, derived sizes.`

2. Add after `size_derives`:

```python
def no_stitch_code(doc: dict) -> str | None:
    """The palette code marked `"stitch": false` (schema 3): a shaped piece's ground, kept in the
    palette so the grid stays the picture, and worked by nobody. The first when a document marks
    more than one, which validate_document refuses."""
    for p in doc.get("palette") or []:
        if isinstance(p, dict) and p.get("stitch") is False:
            return p.get("code")
    return None
```

3. Replace `chart_id` with:

```python
def chart_id(
    codes: list[str],
    rows: list[str],
    technique: dict,
    passes: list[dict] | None = None,
    cell: dict | None = None,
    no_stitch: str | None = None,
) -> str:
    obj = {"codes": list(codes), "rows": list(rows), "technique": technique}
    if passes is not None:
        obj["passes"] = passes
    if isinstance(cell, dict):  # presence-and-type, exactly as `passes` is guarded at the call site
        obj["cell"] = cell
    if no_stitch is not None:  # it changes the sequence, so it changes the id (spec §5.1)
        obj["no_stitch"] = no_stitch
    return "sha256:" + hashlib.sha256(_canonical(obj)).hexdigest()
```

4. In `sequence`, compute `ns = no_stitch_code(doc)` just after `rows = doc["rows"]`, and change the run loop to skip it while still advancing `x`:

```python
        runs, x = [], 0
        for code, n in parse_runs(rows[y]):
            if code != ns:  # a shaped piece's ground is no stitch: nothing to work (spec §5.1)
                runs.append({"code": code, "count": n, "x0": x})
            x += n
```

5. Add after `sequence`:

```python
def stitched_span(runs: list[dict]) -> tuple[int, int] | None:
    """The grid columns a pass's runs cover, `(lo, hi)` with `hi` exclusive; None without `x0`."""
    if not runs or any(r.get("x0") is None for r in runs):
        return None
    return min(r["x0"] for r in runs), max(r["x0"] + r["count"] for r in runs)


def shaping(passes: list[dict]) -> list[dict | None]:
    """Per pass, the cells gained (positive) or lost (negative) at each edge against the pass
    before, named in the pass's own reading direction: `start` is the right edge of an `rtl` pass
    and the left of an `ltr` one (spec §5.1). Derived, never stored. None for pass 1 and wherever
    a pass has no grid columns or no direction."""
    out: list[dict | None] = []
    for k, p in enumerate(passes):
        cur = stitched_span(p["runs"])
        prev = stitched_span(passes[k - 1]["runs"]) if k else None
        d = p.get("direction")
        if cur is None or prev is None or d not in ("rtl", "ltr"):
            out.append(None)
            continue
        left, right = prev[0] - cur[0], cur[1] - prev[1]
        out.append({"start": left, "end": right} if d == "ltr" else {"start": right, "end": left})
    return out
```

6. In `validate_document`, after the palette loop (before `width = ...`), add:

```python
    marked = [p.get("code") for p in palette if isinstance(p, dict) and p.get("stitch") is False]
    ns = marked[0] if marked else None
    if len(marked) > 1:
        problems.append(f'palette marks {len(marked)} colours "stitch": false; at most one may be')
    if ns is not None and doc.get("schema") != 3:
        # A schema-2 reader would count these cells as stitches: writers MUST NOT, readers refuse.
        problems.append(f'palette code {ns!r} is "stitch": false, which needs schema 3, not {doc.get("schema")!r}')
```

7. In the `for y, s in enumerate(rows)` loop, after the `if total != width` check, add:

```python
        if ns is not None:
            cells_y = [c for c, n in parse_runs(s) for _ in range(n)]
            stitched = [x for x, c in enumerate(cells_y) if c != ns]
            if not stitched:
                problems.append(f"row {y} has no stitches: every cell is the no-stitch colour {ns!r}")
            elif stitched[-1] - stitched[0] + 1 != len(stitched):
                problems.append(f"row {y} has a no-stitch cell between stitches (one stitched span per row)")
```

8. In the explicit-passes loop, right after the unknown-code check (`if r.get("code") not in known: ... continue`), add:

```python
                if ns is not None and r.get("code") == ns:
                    problems.append(f"passes[{i}].runs[{j}] is the no-stitch colour; passes list stitched runs only")
                    continue
```

9. Replace the foundation block's `needed = width + into - 1` computation and message with:

```python
            first = _pass_1_stitches(doc, width, ns)
            needed = first + into - 1
            if chain < needed:  # row 1 could not be worked: refuse, never warn (#50)
                problems.append(
                    f"foundation.chain {chain} is shorter than the {needed} chains row 1 needs "
                    f"({first} stitches in row 1 + first_stitch_in {into} - 1)"
                )
```

and add this helper above `validate_document`:

```python
def _pass_1_stitches(doc: dict, width: int, ns: str | None) -> int:
    """Stitches in the grid row pass 1 works: the chart's width unless the chart is shaped. The
    bottom row unless `technique.start` says otherwise, as `sequence` derives it."""
    rows = doc.get("rows") or []
    if ns is None or not rows:
        return width
    t = doc.get("technique") or {}
    s = rows[len(rows) - 1] if t.get("start", "bottom") == "bottom" else rows[0]
    if not isinstance(s, str) or not ROW_RE.match(s):
        return width
    return sum(n for code, n in parse_runs(s) if code != ns)
```

10. Before the `expected = chart_id(...)` call, add the `written` check:

```python
    written = doc.get("written")
    if written is not None:
        n_passes = len(passes) if isinstance(passes, list) else len(rows)
        if not isinstance(written, list) or not all(isinstance(w, str) for w in written):
            problems.append("written is not a list of strings")
        elif len(written) != n_passes:
            problems.append(f"written has {len(written)} entries, the chart has {n_passes} passes")
```

and pass `ns` to the id: `expected = chart_id(codes, rows, doc.get("technique") or {}, passes if isinstance(passes, list) else None, cell, ns)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run pytest tests/test_chartdoc.py tests/test_conformance.py -q`
Expected: PASS (all; the conformance suite proves no schema-2 fixture moved).

- [ ] **Step 5: Commit**

```bash
git add src/graphghan/chartdoc.py tests/test_chartdoc.py
git commit -m "chartdoc: schema 3 shaped rows — no-stitch colour, one span per row, shaping (#37)"
```

---

### Task 2: Python stats, JSON Schema, conformance fixtures, format doc

**Files:**
- Modify: `src/graphghan/export.py` (`stats`)
- Modify: `schema/chart.schema.json`
- Modify: `fixtures/chart-format/generate.py`, `fixtures/chart-format/README.md`
- Create (generated): `fixtures/chart-format/shaped-basic.chart.json`, `shaped-basic.sequence.json`, `shaped-basic.shaping.json`, `progress-shaped.progress.json`, `progress-shaped.progress.expected.json`
- Modify: `docs/chart-format.md`
- Test: `tests/test_conformance.py`, `tests/test_export.py`

**Interfaces:**
- Consumes: Task 1's `chart_id(..., no_stitch=)`, `sequence`, `shaping`, `no_stitch_code`.
- Produces: `export.stats(a, codes, kind="stitch", sized=True, no_stitch: int | None = None)` (palette index); the fixture files above, which Task 3 reads from Swift. `shaped-basic.shaping.json` is `{"shaping": [null | {"start": int, "end": int}, …]}`, one per pass.

- [ ] **Step 1: Write the failing tests**

In `tests/test_conformance.py`:

- Add `"shaped-basic"` to the set in `test_fixture_set_matches_spec`.
- Add `"shaped-basic": (2.0, 1.2, "in"),` to `FINISHED_SIZES_BEFORE_48` (7 cells at 14 per 4 in, 5 rows at 16 per 4 in: the bounding box, as spec §5.1's numbers table says).
- Append:

```python
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
```

In `tests/test_export.py`, append:

```python
def test_stats_leave_out_the_no_stitch_colour():
    import numpy as np

    from graphghan.export import stats

    a = np.array([[2, 0, 0, 2], [0, 1, 0, 0]], dtype=np.uint8)  # 2 is the ground
    st = stats(a, ["A", "B", "N"], no_stitch=2)
    assert st["cells"] == 6 and st["stitches"] == 6
    assert st["counts"] == {"A": 5, "B": 1}
    assert st["single_stitch_runs"] == {"A": 1, "B": 1}  # row 1: A1 B1 A2
    assert st["color_changes_per_row"]["per_row"] == [0, 2]
    assert stats(a, ["A", "B", "N"])["cells"] == 8  # without the flag, unchanged
```

Row 0's stitched runs are `A2` (no singles); row 1's are `A1 B1 A2`: one single A, one single B.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest tests/test_conformance.py tests/test_export.py -q`
Expected: FAIL — `test_fixture_set_matches_spec` (no `shaped-basic`), `FileNotFoundError` for `shaped-basic.chart.json`, `TypeError: stats() got an unexpected keyword argument 'no_stitch'`.

- [ ] **Step 3: Implement `export.stats`**

Replace `stats` in `src/graphghan/export.py` with:

```python
def stats(a, codes, kind="stitch", sized=True, no_stitch=None):
    """`no_stitch` is the palette index of a shaped piece's ground (chart schema 3): its cells are
    in the grid but are no stitch and no yarn, so every count below leaves them out. None keeps
    every number exactly as before."""
    h, w = a.shape
    counts = {codes[i]: int((a == i).sum()) for i in range(len(codes)) if i != no_stitch}
    runs = [[(c, n) for c, n in row if c != no_stitch] for row in rle_rows(a)]
    singles = {c: 0 for i, c in enumerate(codes) if i != no_stitch}
    per_row = []
    for row in runs:
        per_row.append(max(0, len(row) - 1))
        for c, n in row:
            if n == 1:
                singles[codes[c]] += 1
    cells = int(w * h) if no_stitch is None else int((a != no_stitch).sum())
    cell_sqin = gr.SW * gr.SH
    yards = {
        code: n * cell_sqin * 1.1 * 1.2 for code, n in counts.items()
    }  # 1.1 yd/sq in worsted sc, +20% tails
    out = {
        "cells": cells,
        # gr.SW/gr.SH are per-STITCH dimensions, so this conversion is only meaningful when the
        # gauge and the grid count the same thing (#48). The caller resolves that pairing. Kept
        # in this original key position (rather than appended) so a sized chart's stats are
        # byte-identical to before `sized` existed. A shaped chart's size is its bounding box.
        **({"size_in": [round(w * gr.SW, 1), round(h * gr.SH, 1)]} if sized else {}),
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
        out["stitches"] = cells
        out["yards_est"] = {k: int(round(v)) for k, v in yards.items()}
        out["skeins_364yd"] = {k: round(v / 364, 1) for k, v in yards.items()}
    return out
```

(`max(0, len(row) - 1)` equals `len(row) - 1` for every non-empty row, so schema-2 stats are unchanged.)

- [ ] **Step 4: Implement the JSON Schema changes**

In `schema/chart.schema.json`:
- `"title": "Graphghan chart document, schema 2 or 3"`.
- `"schema": { "enum": [2, 3] }`.
- In `properties`, after `"instructions"`, add `"written": { "type": "array", "items": { "type": "string" } },`.
- In `$defs.paletteItem.properties`, after `"use"`, add `"stitch": { "type": "boolean" },`.

- [ ] **Step 5: Implement the fixtures**

In `fixtures/chart-format/generate.py`:

1. Change the `chart()` helper signature and body so it can mark a no-stitch code:

```python
def chart(pid, title, palette, rows, technique, passes=None, layers=None, cell=None, gauge=None, no_stitch=None):
    codes = [c for c, _ in palette]
    width = sum(int(n) for n, _ in re.findall(r"(\d+)([A-Za-z]{1,3})", rows[0]))
    chart_block = {
        "id": chart_id(codes, rows, technique, passes, cell, no_stitch),
        …unchanged…
    }
    …
    doc = {
        "schema": 3 if no_stitch is not None else 2,
        …unchanged…
        "palette": [_palette_entry(c, h, no_stitch) for c, h in palette],
        …unchanged…
    }
```

with, above it:

```python
def _palette_entry(code, hex_, no_stitch):
    entry = {"code": code, "name": f"Color {code}", "hex": hex_}
    if code == no_stitch:  # schema 3: the ground of a shaped piece (spec 2026-09-25 §5.1)
        entry["stitch"] = False
        entry["use"] = "no stitch"
    return entry
```

2. Add after the tiles fixture constants:

```python
# The shaped-basic fixture (chart schema 3, spec 2026-09-25 §5.1, #37): Orca's shape at toy size.
# N is the ground no one stitches. Pass 1 is 3 stitches, grows one at each edge twice, loses one
# at the start of pass 4 (an asymmetric row), and narrows to 3 on pass 5 -- so the shaping file
# pins +, -, 0 and a two-cell change, in both reading directions.
SHAPED_PALETTE = [("A", "#112233"), ("B", "#ffffff"), ("N", "#a4dade")]
SHAPED_ROWS = ["2N3A2N", "1N2A1B3A", "3A1B3A", "1N5A1N", "2N3A2N"]
SHAPED_WRITTEN = [
    "R 1: ch 4, from the second chain from the hook, 3 sc [3]",
    "R 2: ch 1, turn, 1 inc, 1 sc, 1 inc [5]",
    "R 3: ch 1, turn, 1 inc, 1 sc, (B) 1 sc, (A) 1 sc, 1 inc [7]",
    "R 4: ch 1, turn, 1 dec, 1 sc, (B) 1 sc, (A) 3 sc [6]",
    "R 5: sl st across 2, ch 1, 3 sc, leave 1 unworked [3]",
]
# Hand-written expected sequence and shaping, worked out from SHAPED_ROWS as the other fixtures are.
SHAPED_SEQ = [
    p("Row 1", "RS", "rtl", 4, [run("A", 3, 2)]),
    p("Row 2", "WS", "ltr", 3, [run("A", 5, 1)]),
    p("Row 3", "RS", "rtl", 2, [run("A", 3, 4), run("B", 1, 3), run("A", 3, 0)]),
    p("Row 4", "WS", "ltr", 1, [run("A", 2, 1), run("B", 1, 3), run("A", 3, 4)]),
    p("Row 5", "RS", "rtl", 0, [run("A", 3, 2)]),
]
SHAPED_SHAPING = [
    None,
    {"start": 1, "end": 1},
    {"start": 1, "end": 1},
    {"start": -1, "end": 0},
    {"start": -2, "end": -1},
]


def shaped_basic_chart() -> dict:
    codes = [c for c, _ in SHAPED_PALETTE]
    doc = chart("shaped-basic", "Shaped basic", SHAPED_PALETTE, SHAPED_ROWS, ROWS_T, no_stitch="N")
    doc["foundation"] = {"chain": 4, "first_stitch_in": 2}
    doc["written"] = SHAPED_WRITTEN
    a = decode_rows(SHAPED_ROWS, codes)
    doc["stats"] = chart_stats(a, codes, sized=size_derives(doc), no_stitch=codes.index("N"))
    return doc
```

3. Add a progress fixture after `PROGRESS_STITCH_EXPECTED`:

```python
# A cursor on the shaped chart: 3 + 5 cells of passes 1-2 and pass 3's first run of 3 are done,
# of 24 stitched cells -- the ground never enters the denominator.
PROGRESS_SHAPED_EVENTS = [
    ev("2026-09-12T18:00:00Z", 2, 0),
    ev("2026-09-12T18:05:00Z", 3, 0),
    ev("2026-09-12T18:10:00Z", 3, 1),
]
PROGRESS_SHAPED_EXPECTED = {
    "percent": 45.8,
    "cells_done": 11,
    "total_cells": 24,
    "stitches_done": 11,
    "total_stitches": 24,
    "sessions": [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:10:00Z", "cells": 11, "stitches": 11},
    ],
    "active_seconds": 600,
    "stitches_per_hour": 66.0,
}
```

and in `progress_fixtures`, before the `return`:

```python
    shaped_chart = charts["shaped-basic"][0]
    shaped_doc = {
        "schema": 1,
        "pattern_id": "shaped-basic",
        "chart_id": shaped_chart["chart"]["id"],
        "pattern_version": "1.0.0",
        "cursor": {"row": 3, "run": 1},
        "started": "2026-09-12T18:00:00Z",
        "finished": None,
        "events": PROGRESS_SHAPED_EVENTS,
        "ext": {"fixture": {"chart": "shaped-basic"}},
    }
```

adding `"progress-shaped": (shaped_doc, PROGRESS_SHAPED_EXPECTED),` to the returned dict.

4. In `fixtures()`, add `"shaped-basic": (shaped_basic_chart(), {"passes": SHAPED_SEQ}),` before `"craigh-na-dun"`.

5. In `main`, after the chart loop, add:

```python
    (out_dir / "shaped-basic.shaping.json").write_text(dump({"shaping": SHAPED_SHAPING}), encoding="utf-8")
```

6. Run `uv run python fixtures/chart-format/generate.py`.

7. In `fixtures/chart-format/README.md`, add after the `progress-stitch` paragraph:

```markdown
`shaped-basic` pins chart schema 3 (spec 2026-09-25 §5.1, #37): palette code `N` is
`"stitch": false`, the ground of a shaped piece. It stays in the grid so the grid is the picture,
and every reader leaves it out of the working order, the counts and the foundation rule: pass 1 is
3 stitches at `x0` 2 on a 7-wide chart. `shaped-basic.shaping.json` pins the shaping derived for
each pass (`{"start", "end"}` in the pass's reading direction, `null` for pass 1).
`progress-shaped` pins that the ground never enters `total_cells`.
```

and add a line to the reader expectations list: `- reproduce `shaped-basic.shaping.json` from the sequence it derives.`

- [ ] **Step 6: Update `docs/chart-format.md`**

1. Change the version line to: `Version: chart schemas 2 and 3, progress schema 1, pattern manifest schema 1.`
2. Add a new section after `### Cells` (before `### Gauge`):

```markdown
### Shaped rows (schema 3)

A shaped piece (a bag panel that grows from 9 stitches to 29 and back to 3) keeps its grid as the
picture: every row still sums to `chart.width`, and `width × height` is the bounding box. One
palette entry may carry `"stitch": false`; its cells are the ground nobody works. Writers keep
`use: "no stitch"` beside it as the human label.

- **At most one** palette entry is `"stitch": false`.
- **One stitched span per row.** No-stitch cells form at most a prefix and a suffix of a row; the
  cells between are one non-empty unbroken span. A no-stitch cell between stitches, or a row of
  only no-stitch cells, cannot be worked as written: writers MUST NOT write it, readers MUST
  refuse it (#210 is the case of a row with a gap).
- **Explicit `passes`** list stitched runs only; a run of the no-stitch code is invalid.
- **Sequencing** leaves the no-stitch runs out; `x0` stays the grid column.
- **Shaping is derived, never stored.** For pass *k* > 1 compare its stitched span with pass
  *k − 1*'s in grid columns; name each edge in pass *k*'s reading direction (start is the right
  edge of an `rtl` pass, the left of an `ltr` one). The change is a signed cell count: "+1 at
  start, +1 at end". How a stitch is added or removed is not in the chart (#216).
- **Numbers** that counted the rectangle count stitched cells: `stats.cells`, `stats.stitches`,
  `total_cells`, `counts`, `yards_est`, `skeins_364yd`, `color_changes_per_row`,
  `single_stitch_runs`, and the manifest's `colors` and `stitches`. `stats.size_in` and the
  manifest `size` stay the bounding box. The foundation rule reads the stitches of the grid row
  pass 1 works: `chain ≥ stitches(pass 1) + first_stitch_in − 1`.
- **`written`**, optional at either schema: an array of strings, one per pass in pass order, the
  pattern's own row instruction. Readers show it beside the pass; it is not in the chart id. Its
  length MUST equal the pass count.

A writer emits schema 3 exactly when the palette has a no-stitch entry, and schema 2 otherwise,
so a rectangle is byte-identical to what it always was. `"stitch": false` in a schema 2 document
is refused: a schema 2 reader would count those cells. A schema 2 chart whose palette says only
`use: "no stitch"` is a rectangle; the label is a label.
```

3. In `### Palette and cells`, change the row-sum bullet's last sentence to add: `(schema 3 adds a no-stitch colour; see §Shaped rows).`
4. In `### Chart id`, after `plus "cell" when the document has it and it is an object`, insert `, plus "no_stitch" (the code) when the palette has a "stitch": false entry`.
5. In `### Foundation`, change `one with fewer than width + first_stitch_in - 1` to `one with fewer than the stitches of pass 1 (the width, unless the chart is shaped) + first_stitch_in - 1`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `uv run pytest -q`
Expected: PASS, including `test_fixtures_are_fresh`, `test_sequence_matches_expected[shaped-basic]`, `test_progress_fixture_validates_and_summarizes[progress-shaped]`, and every pre-existing test untouched.

- [ ] **Step 8: Commit**

```bash
git add src/graphghan/export.py schema/chart.schema.json fixtures/chart-format docs/chart-format.md tests/test_conformance.py tests/test_export.py
git commit -m "format: chart schema 3 in the spec, the JSON Schema and the conformance fixtures (#37)"
```

---

### Task 3: Swift reader — decode, validate, sequence, shaping

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ChartDocument.swift`, `ChartID.swift`, `Chart.swift`, `WorkSequence.swift`
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Shaping.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartTests.swift`, `WorkSequenceTests.swift`, `PaceTests.swift`, `FixturesTests.swift`, `WorkEngineTests.swift`

**Interfaces:**
- Consumes: Task 2's fixtures (`shaped-basic.chart.json`, `.sequence.json`, `.shaping.json`, `progress-shaped.*`).
- Produces:
  - `ChartDocument.PaletteEntry.stitch: Bool?`; `ChartDocument.written: [String]?`
  - `ChartID.compute(codes:rows:technique:passes:cell:noStitch:)` — `noStitch: String? = nil`
  - `ChartError` cases `.noStitchNeedsSchema3`, `.tooManyNoStitch(Int)`, `.noStitchInsideRow(Int)`, `.rowWithoutStitches(Int)`, `.writtenCount(got: Int, expected: Int)`
  - `Chart.noStitchIndex: Int?`, `Chart.isShaped: Bool`, `Chart.isStitched(colorIndex: Int) -> Bool`, `Chart.written: [String]?`
  - `public struct Shaping: Equatable, Sendable { start: Int; end: Int; sentence: String? }`
  - `WorkSequence.shaping(at row: Int) -> Shaping?`

- [ ] **Step 1: Write the failing tests**

`FixturesTests.fixtureSetMatchesSpec`: add `"shaped-basic"` to the set. `PaceTests.matchesTheProgressFixture`: change the arguments to `["progress-basic", "progress-stitch", "progress-shaped"]`.

Append to `ChartTests`:

```swift
    // ---- chart schema 3: shaped rows (spec 2026-09-25 §5.1) ----

    static let shapedRows = ["2N3A2N", "1N2A1B3A", "3A1B3A", "1N5A1N", "2N3A2N"]

    /// A 7-wide shaped chart: A and B are yarns, N the ground; `noStitch` lists the codes marked
    /// `"stitch": false`, `extra` is raw JSON members appended to the document.
    static func shaped(rows: [String] = shapedRows, schema: Int = 3, noStitch: [String] = ["N"], start: String = "bottom",
                       passes: String? = nil, extra: String = "") throws -> Data {
        let codes = ["A", "B", "N"]
        let technique: JSONValue = .object(["type": .string(passes == nil ? "rows" : "none"), "start": .string(start)])
        let passesValue = try passes.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        let id = ChartID.compute(codes: codes, rows: rows, technique: technique, passes: passesValue, noStitch: noStitch.first)
        let palette = codes.enumerated().map { i, c in
            #"{"code":"\#(c)","name":"n\#(i)","hex":"\#(String(format: "#%06x", i * 0x111111))"\#(noStitch.contains(c) ? #","stitch":false"# : "")}"#
        }.joined(separator: ",")
        return Data(#"""
        {"schema":\#(schema),"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\#(id)","width":7,"height":\#(rows.count)},
         "palette":[\#(palette)],"rows":[\#(rows.map { "\"\($0)\"" }.joined(separator: ","))],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"}},"technique":\#(CanonicalJSON.encode(technique))\#(passes.map { ",\"passes\":\($0)" } ?? "")\#(extra)}
        """#.utf8)
    }

    @Test func aShapedChartLoads() throws {
        let chart = try Chart.load(Self.shaped())
        #expect(chart.noStitchIndex == 2 && chart.isShaped)
        #expect(chart.isStitched(colorIndex: 0) && !chart.isStitched(colorIndex: 2))
        #expect(try !Self.chart("minimal-rows").isShaped)
    }

    @Test func aNoStitchCellBetweenStitchesIsRefused() throws {
        var rows = Self.shapedRows
        rows[0] = "1A1N5A"
        #expect(throws: ChartError.noStitchInsideRow(0)) { try Chart.load(Self.shaped(rows: rows)) }
    }

    @Test func aRowOfOnlyNoStitchIsRefused() throws {
        var rows = Self.shapedRows
        rows[0] = "7N"
        #expect(throws: ChartError.rowWithoutStitches(0)) { try Chart.load(Self.shaped(rows: rows)) }
    }

    @Test func twoNoStitchColoursAreRefused() throws {
        #expect(throws: ChartError.tooManyNoStitch(2)) { try Chart.load(Self.shaped(noStitch: ["B", "N"])) }
    }

    @Test func stitchFalseNeedsSchema3() throws {
        #expect(throws: ChartError.noStitchNeedsSchema3) { try Chart.load(Self.shaped(schema: 2)) }
    }

    @Test func foundationCountsPassOnesStitches() throws {
        _ = try Chart.load(Self.shaped(extra: #","foundation":{"chain":4,"first_stitch_in":2}"#))
        #expect(throws: ChartError.foundationTooShort(chain: 3, needed: 4)) {
            try Chart.load(Self.shaped(extra: #","foundation":{"chain":3,"first_stitch_in":2}"#))
        }
    }

    @Test func foundationReadsPassOneAtTheTop() throws {
        let rows = ["1N5A1N", "3A1B3A", "2N3A2N"]
        #expect(throws: ChartError.foundationTooShort(chain: 5, needed: 6)) {
            try Chart.load(Self.shaped(rows: rows, start: "top", extra: #","foundation":{"chain":5,"first_stitch_in":2}"#))
        }
        _ = try Chart.load(Self.shaped(rows: rows, start: "top", extra: #","foundation":{"chain":6,"first_stitch_in":2}"#))
        _ = try Chart.load(Self.shaped(rows: rows, extra: #","foundation":{"chain":4,"first_stitch_in":2}"#))
    }

    @Test func writtenHasOneEntryPerPass() throws {
        let chart = try Chart.load(Self.shaped(extra: #","written":["R1","R2","R3","R4","R5"]"#))
        #expect(chart.written?.count == 5)
        #expect(throws: ChartError.writtenCount(got: 1, expected: 5)) { try Chart.load(Self.shaped(extra: #","written":["R1"]"#)) }
    }

    @Test func theIDIncludesTheNoStitchCode() {
        let t: JSONValue = .object(["type": .string("rows")])
        #expect(ChartID.compute(codes: ["A", "N"], rows: ["1N1A"], technique: t, passes: nil)
                != ChartID.compute(codes: ["A", "N"], rows: ["1N1A"], technique: t, passes: nil, noStitch: "N"))
    }
```

Append to `WorkSequenceTests`:

```swift
    @Test func aShapedSequenceLeavesOutTheGround() throws {
        let seq = try Self.sequence("shaped-basic")
        #expect(seq.passes[0].runs == [Run(code: "A", count: 3, x0: 2)])
        #expect(seq.totalCells == 24 && seq.totalStitches == 24)
    }

    @Test func shapingMatchesTheFixture() throws {
        struct Edge: Decodable { let start: Int; let end: Int }
        struct Expected: Decodable { let shaping: [Edge?] }
        let expected = try JSONDecoder().decode(Expected.self, from: Fixtures.data("shaped-basic.shaping.json"))
        let seq = try Self.sequence("shaped-basic")
        #expect(expected.shaping.count == seq.passes.count)
        for (i, want) in expected.shaping.enumerated() {
            #expect(seq.shaping(at: i + 1) == want.map { Shaping(start: $0.start, end: $0.end) }, "row \(i + 1)")
        }
    }

    @Test func shapingSentence() {
        #expect(Shaping(start: 1, end: 1).sentence == "+1 at start, +1 at end")
        #expect(Shaping(start: -1, end: 0).sentence == "\u{2212}1 at start")
        #expect(Shaping(start: 0, end: -2).sentence == "\u{2212}2 at end")
        #expect(Shaping(start: 0, end: 0).sentence == nil)
    }

    @Test func explicitPassesMayNotListTheNoStitchColour() throws {
        let passes = #"[{"label":"Row 1","grid_row":4,"runs":[{"code":"N","count":2,"x0":0}]}]"#
        let chart = try Chart.load(ChartTests.shaped(passes: passes))
        #expect(throws: SequenceError.self) { try WorkSequence(chart: chart) }
    }
```

Append to `WorkEngineTests` (Review Focus 5):

```swift
    /// A shaped row is walked on its stitches only: Done goes run to run, then to the boundary,
    /// then to the next row's first stitched run, and never to a cell of the ground.
    @Test func doneWalksOnlyStitchedCells() throws {
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("shaped-basic.chart.json")))
        var cursor = Cursor.start
        var visited: [Int] = []   // x0 of every run the cursor stands on
        while !WorkEngine.isFinished(cursor, in: seq) {
            let pass = try #require(seq.pass(at: cursor.row))
            if cursor.run < pass.runs.count { visited.append(try #require(pass.runs[cursor.run].x0)) }
            cursor = try #require(WorkEngine.apply(.advance, to: cursor, in: seq, step: .wholeRun)).cursor
        }
        #expect(visited == [2, 1, 4, 3, 0, 1, 3, 4, 2])
    }
```

(`WorkEngine.apply(_:to:in:step:perRepetition:)` returns a `WorkStep?` whose `cursor` is the new position; `.wholeRun` makes one Done a whole run.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet`
Expected: FAIL to compile — `extra argument 'noStitch' in call`, `cannot find 'Shaping' in scope`, `type 'ChartError' has no member 'noStitchInsideRow'`.

- [ ] **Step 3: Implement**

`ChartDocument.swift`:
- `PaletteEntry`: add `public let stitch: Bool?` after `symbol` with the doc comment `/// \`false\` marks a shaped piece's ground (schema 3); absent means a yarn.`
- Top level: add `public let written: [String]?` after `foundation`, with `/// The pattern's own row text, one per pass (schema 3 §Shaped rows); not in the id.`; add `written` to `CodingKeys`; in `init(from:)` add `written = try c.decodeIfPresent([String].self, forKey: .written)`.
- Change the type's doc comment `(schema 2)` to `(schema 2 or 3)`.

`ChartID.swift`: add the parameter and member:

```swift
    public static func compute(codes: [String], rows: [String], technique: JSONValue,
                               passes: JSONValue?, cell: JSONValue? = nil, noStitch: String? = nil) -> String {
        …existing object…
        if let noStitch { object["no_stitch"] = .string(noStitch) }   // it changes the sequence (spec §5.1)
        …unchanged…
    }
```

and extend its doc comment: `…and (when a palette colour is "stitch": false) that code.`

`Chart.swift`:
1. Add to `ChartError`:

```swift
    /// `"stitch": false` in a schema 2 document: a schema 2 reader would count the ground (spec §5.1).
    case noStitchNeedsSchema3
    /// More than one palette colour is `"stitch": false`.
    case tooManyNoStitch(Int)
    /// A no-stitch cell between stitches of a grid row: one stitched span per row.
    case noStitchInsideRow(Int)
    /// A grid row with no stitches at all.
    case rowWithoutStitches(Int)
    /// `written` must have one entry per pass.
    case writtenCount(got: Int, expected: Int)
```

2. Add stored/computed members to `Chart`:

```swift
    /// The palette index of a shaped piece's ground (`"stitch": false`, schema 3), or nil.
    public let noStitchIndex: Int?
    /// The chart has a ground nobody stitches: its rows are shaped.
    public var isShaped: Bool { noStitchIndex != nil }
    /// Whether cells of this palette index are worked.
    public func isStitched(colorIndex: Int) -> Bool { colorIndex != noStitchIndex }
    /// The pattern's own row text, one per pass, when the chart carries it.
    public var written: [String]? { document.written }
```

3. In `init(document:verifyID:)`:
- Replace `guard document.schema == 2` with `guard document.schema == 2 || document.schema == 3`.
- Delete the foundation block at the top (it moves below).
- After the palette loop, add:

```swift
        let marked = document.palette.filter { $0.stitch == false }.map(\.code)
        guard marked.count <= 1 else { throw ChartError.tooManyNoStitch(marked.count) }
        guard marked.isEmpty || document.schema == 3 else { throw ChartError.noStitchNeedsSchema3 }
        let noStitchIndex = marked.first.flatMap { index[$0] }
```

- In the rows loop, after `guard x == width else …`, add:

```swift
            if let ns = noStitchIndex {
                let stitched = runs.filter { $0.colorIndex != ns }
                guard let first = stitched.first, let last = stitched.last else { throw ChartError.rowWithoutStitches(y) }
                // One stitched span per row: the stitched runs fill it without a gap.
                guard last.x0 + last.count - first.x0 == stitched.reduce(0, { $0 + $1.count }) else { throw ChartError.noStitchInsideRow(y) }
            }
```

- After the rows loop, add:

```swift
        if let foundation = document.foundation {
            // Pass 1 works the bottom row unless the technique starts at the top (WorkSequence),
            // and a shaped row 1 is its stitches, not the chart's width (spec §5.1).
            let y1 = document.techniqueStart == "bottom" ? height - 1 : 0
            let first = noStitchIndex.map { ns in runsByRow[y1].filter { $0.colorIndex != ns }.reduce(0) { $0 + $1.count } } ?? width
            let needed = first + (foundation.firstStitchIn ?? 1) - 1
            guard foundation.chain >= needed else { throw ChartError.foundationTooShort(chain: foundation.chain, needed: needed) }
        }
        if let written = document.written {
            let passes = document.passes?.arrayValue?.count ?? height
            guard written.count == passes else { throw ChartError.writtenCount(got: written.count, expected: passes) }
        }
```

- In the id check, pass `noStitch: marked.first`.
- Assign `self.noStitchIndex = noStitchIndex` with the other assignments.

`WorkSequence.swift`:
- In `init(chart:)`, change the runs line to:

```swift
            // A shaped piece's ground is no stitch: nothing to work (spec §5.1).
            var runs = chart.runsByRow[y].filter { chart.isStitched(colorIndex: $0.colorIndex) }
                .map { Run(code: chart.palette[$0.colorIndex].code, count: $0.count, x0: $0.x0) }
```

- In `explicitPasses`, after the unknown-code guard, add:

```swift
                if let ns = chart.noStitchIndex, chart.colorIndex(of: code) == ns {
                    throw SequenceError.malformedPasses("passes[\(i)].runs[\(j)] is the no-stitch colour")
                }
```

Create `Shaping.swift`:

```swift
import Foundation

/// How a pass's stitched span changed from the pass before, in cells, at each edge named in the
/// pass's own reading direction: `start` is the right edge of a right-to-left pass and the left of
/// a left-to-right one; positive is gained, negative lost (spec 2026-09-25 §5.1). Derived from the
/// grid, never stored: the chart says how many and where, not how. Mirrors graphghan.chartdoc.shaping.
public struct Shaping: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public init(start: Int, end: Int) { self.start = start; self.end = end }

    /// "+1 at start, +1 at end"; an unchanged edge is left out; nil when neither edge changed.
    public var sentence: String? {
        var parts: [String] = []
        if start != 0 { parts.append("\(Self.signed(start)) at start") }
        if end != 0 { parts.append("\(Self.signed(end)) at end") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\u{2212}\(-n)" }
}

extension WorkSequence {
    /// The grid columns a pass's runs cover, `hi` exclusive; nil when a run has no `x0`.
    static func span(_ runs: [Run]) -> (lo: Int, hi: Int)? {
        guard !runs.isEmpty else { return nil }
        var lo = Int.max, hi = Int.min
        for r in runs {
            guard let x0 = r.x0 else { return nil }
            lo = min(lo, x0)
            hi = max(hi, x0 + r.count)
        }
        return (lo, hi)
    }

    /// Pass `row`'s shaping against pass `row - 1`; nil for pass 1 or without grid columns or a direction.
    public func shaping(at row: Int) -> Shaping? {
        guard row >= 2, let p = pass(at: row), let q = pass(at: row - 1), let direction = p.direction,
              let cur = Self.span(p.runs), let prev = Self.span(q.runs) else { return nil }
        let left = prev.lo - cur.lo, right = cur.hi - prev.hi
        return direction == .ltr ? Shaping(start: left, end: right) : Shaping(start: right, end: left)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet`
Expected: PASS — every suite, including `WorkSequenceTests.matchesFixture("shaped-basic")`, `ChartTests.everyFixtureLoads`, `PaceTests.matchesTheProgressFixture("progress-shaped")`.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "GraphghanCore: read chart schema 3 — no-stitch ground, one span per row, shaping (#37)"
```

---

### Task 4: Swift writers — schema 3 out of the phone, manifest numbers, preview alpha

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ChartWriter.swift`, `ManifestWriter.swift`, `ChartPreview.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ManifestWriterTests.swift`, `ChartWriterTests.swift`, `ChartPreviewTests.swift`

**Interfaces:**
- Consumes: Task 3's `ChartID.compute(noStitch:)`, `Chart.noStitchIndex`, `Chart.isStitched(colorIndex:)`.
- Produces:
  - `ChartDraft.written: [String]?` (settable, default nil)
  - `ChartWriter.encode(_:)` writes schema 3, `"stitch": false` and `written` as described
  - `ChartPreview.pixels(_ chart: Chart) -> [UInt8]?` — RGBA premultiplied, top row first; no-stitch cells `0,0,0,0`

- [ ] **Step 1: Write the failing tests**

Replace `ManifestWriterTests.aNoStitchColourIsWrittenAndNotCounted` with (the spec reverses its "the id ignores it" line: `no_stitch` changes the sequence, so it changes the id):

```swift
    /// A shaped piece's background (#205) is written as chart schema 3: `"stitch": false` beside
    /// `use: "no stitch"`, in the id (it changes the sequence), and out of every manifest number.
    @Test func aNoStitchColourIsWrittenAsSchema3AndNotCounted() throws {
        let draft = ChartDraft(pattern: .init(id: "orca", title: "Orca", version: "0.1.0"),
                               palette: [.init(code: "A", name: "light blue", hex: "#a4dade", use: ChartDraft.Palette.noStitch),
                                         .init(code: "B", name: "black", hex: "#000000")],
                               rows: ["1A1B1A", "3B"], width: 3, height: 2, gauge: .init())
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        #expect(chart.document.schema == 3 && chart.noStitchIndex == 0)
        #expect(chart.palette.map(\.use) == ["no stitch", nil] && chart.palette.map(\.stitch) == [false, nil])
        let plain = ChartDraft(pattern: draft.pattern, palette: draft.palette.map { .init(code: $0.code, name: $0.name, hex: $0.hex) },
                               rows: draft.rows, width: 3, height: 2, gauge: .init())
        #expect(ChartWriter.encode(plain).id != id)                                   // the id includes it
        #expect(try Chart.load(ChartWriter.encode(plain).data).document.schema == 2)  // a rectangle stays schema 2
        let bytes = ManifestWriter.encode(id: "orca", title: "Orca", version: "0.1.0", dedication: "", chart: chart, chartID: id,
                                          variant: "final", gaugeKey: "sc", palette: draft.palette)
        let m = try JSONDecoder().decode(PatternManifest.self, from: bytes)
        #expect(m.charts.first?.colors == 1 && m.charts.first?.stitches == 4)
    }
```

Append to `ChartWriterTests`:

```swift
    @Test func writtenRowsRoundTrip() throws {
        var draft = ChartDraft(pattern: .init(id: "t", title: "T", version: "0.1.0"),
                               palette: [.init(code: "A", name: "a", hex: "#000000")], rows: ["2A", "2A"], width: 2, height: 2, gauge: .init())
        draft.written = ["R 1: 2 sc [2]", "R 2: ch 1, turn, 2 sc [2]"]
        let chart = try Chart.load(ChartWriter.encode(draft).data)
        #expect(chart.written == draft.written && chart.document.schema == 2)
    }
```

Append to `ChartPreviewTests`:

```swift
    @Test func theGroundIsTransparent() throws {
        let chart = try Chart.load(Fixtures.data("shaped-basic.chart.json"))
        let px = try #require(ChartPreview.pixels(chart))
        #expect(Array(px[0..<4]) == [0, 0, 0, 0])            // (0, 0) is N, the ground
        #expect(Array(px[8..<12]) == [0x11, 0x22, 0x33, 255]) // (2, 0) is A
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet`
Expected: FAIL — `value of type 'ChartDraft' has no member 'written'`, `type 'ChartPreview' has no member 'pixels'`.

- [ ] **Step 3: Implement**

`ChartWriter.swift`:
- In `ChartDraft`, after `ext`, add:

```swift
    /// The pattern's own row text, one per pass (row 1 first); nil for none. The id ignores it.
    public var written: [String]? = nil
```

- In `encode`:

```swift
        let codes = draft.palette.map(\.code)
        // A background #205 marked is the schema 3 ground: `"stitch": false`, in the id (spec §5.1).
        let noStitch = draft.palette.first { $0.use == ChartDraft.Palette.noStitch }?.code
        let id = ChartID.compute(codes: codes, rows: draft.rows, technique: techniqueRows, passes: nil, noStitch: noStitch)
```

  `"schema": .int(noStitch == nil ? 2 : 3),`; in the palette map add `if p.code == noStitch { e["stitch"] = .bool(false) }`; after `if let ext = draft.ext …` add `if let w = draft.written { doc["written"] = .array(w.map(JSONValue.string)) }`.
- Update the doc comment of `ChartDraft` (`codes, rows, technique and (when present) cell` → `…cell and no-stitch code`).

`ManifestWriter.swift`: replace the first lines of `encode` through `yards` with:

```swift
        // A shaped piece's ground is in the grid but is no stitch (spec §5.1): every number below
        // counts stitched runs, which for a rectangle is every run, as before.
        let stitchedRows = chart.runsByRow.map { $0.filter { chart.isStitched(colorIndex: $0.colorIndex) } }
        let stitches = stitchedRows.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
        let perRow = stitchedRows.map { max(0, $0.count - 1) }
        let mean = perRow.isEmpty ? 0.0 : (Double(perRow.reduce(0, +)) / Double(perRow.count) * 10).rounded() / 10
        let g = chart.document.gauge
        let inches = g.over.unit == "cm" ? g.over.value / 2.54 : g.over.value
        let sw = inches / g.stitches
        let sh = inches / g.rows
        let yards = Int((Double(stitches) * sw * sh * 1.1 * 1.2).rounded())  // 1.1 yd/sq in worsted sc, +20% tails
```

and in the entry replace `"stitches": .int(chart.width * chart.height)` with `"stitches": .int(stitches)`.

`ChartPreview.swift`: extract the pixel loop into a public function and use it from `png`:

```swift
    /// One RGBA pixel per cell, premultiplied, top row first. A shaped piece's ground is clear, so
    /// the preview is the piece's shape (spec §6.3). Nil when a palette hex does not parse.
    public static func pixels(_ chart: Chart) -> [UInt8]? {
        let w = chart.width
        let h = chart.height
        guard w > 0, h > 0, chart.cells.count == w * h else { return nil }
        var rgb: [(UInt8, UInt8, UInt8)] = []
        for entry in chart.palette {
            guard entry.hex.hasPrefix("#"), entry.hex.count == 7, let v = UInt32(entry.hex.dropFirst(), radix: 16) else { return nil }
            rgb.append((UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)))
        }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let index = Int(chart.cells[i])
            guard chart.isStitched(colorIndex: index) else { continue }   // stays 0, 0, 0, 0
            let p = index < rgb.count ? rgb[index] : (0, 0, 0)
            pixels[i * 4] = p.0
            pixels[i * 4 + 1] = p.1
            pixels[i * 4 + 2] = p.2
            pixels[i * 4 + 3] = 255
        }
        return pixels
    }
```

In `png`, replace everything from `let w = chart.width` through the pixel loop with `let w = chart.width; let h = chart.height; guard let pixels = pixels(chart) else { return nil }` (keep the two comment lines about refused hexes above the new guard).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "GraphghanCore: the phone writes a marked background as schema 3; manifest and preview count stitches (#37)"
```

---

### Task 5: App drawing — the band, the whole chart and the library image follow the shape

**Files:**
- Modify: `ios/Graphghan/UI/ChartImage.swift`, `ios/Graphghan/Work/ChartBand.swift`, `ios/Graphghan/Work/BandLayout.swift`
- Test: `ios/Tests/ChartImageTests.swift`, `ios/Tests/BandLayoutTests.swift`, `ios/Tests/ChartBandTests.swift` (+ new reference PNGs under `ios/Tests/__Snapshots__/`)

**Interfaces:**
- Consumes: Task 3's `Chart.isStitched(colorIndex:)`; Task 4's `ChartPreview.pixels(_:)`.
- Produces: nothing new for later tasks; `BandLayout.boundaryX` now stands at the stitched span's end.

- [ ] **Step 1: Write the failing tests**

Append to `ChartImageTests`:

```swift
    @Test func theGroundIsClear() throws {
        let chart = try Chart.load(TestFixtures.data("shaped-basic.chart.json"))
        let image = try #require(ChartImage.make(chart))
        #expect(image.alphaInfo == .premultipliedLast)
        let bytes = try #require(image.dataProvider?.data as Data?)
        #expect(bytes[3] == 0 && bytes[2 * 4 + 3] == 255)   // (0, 0) the ground, (2, 0) a stitch
    }
```

Append to `BandLayoutTests` (Review Focus 4):

```swift
    /// On a shaped row the turn is where the stitches end, not at the chart's edge: shaped-basic's
    /// row 2 (ltr) spans columns 1..<6, row 1 (rtl) columns 2..<5.
    @Test func boundaryStandsAtTheStitchedSpansEnd() throws {
        let chart = try Chart.load(TestFixtures.data("shaped-basic.chart.json"))
        let seq = try WorkSequence(chart: chart)
        func boundary(_ row: Int, _ style: BandStyle) -> CGFloat? {
            let pass = seq.pass(at: row)!
            return BandLayout(width: 366, height: 420, chart: chart, pass: pass, cursor: Cursor(row: row, run: pass.runs.count),
                              segmentLabel: nil, style: style).boundaryX
        }
        #expect(boundary(2, .fabric) == 6 * 8)   // ltr: right end of the span
        #expect(boundary(1, .fabric) == 2 * 8)   // rtl: left end of the span
        #expect(boundary(1, .ribbon) == (7 - 2) * 8)   // mirrored: grid column 2 at content 5
        #expect(boundary(2, .ribbon) == 6 * 8)   // ltr is never mirrored
    }
```

Append to `ChartBandTests`:

```swift
    /// A shaped chart (#37): the ground is drawn as the band's own ground, with no yarn and no
    /// hairlines, so the rows follow the piece's silhouette; the whole view does the same.
    @Test func shaped() throws {
        let chart = try Chart.load(TestFixtures.data("shaped-basic.chart.json"))
        let seq = try WorkSequence(chart: chart)
        for (mode, name) in [(ChartBand.Mode.band, "band-shaped"), (.whole, "band-shaped-whole")] {
            let view = ChartBand(chart: chart, sequence: seq, cursor: Cursor(row: 4, run: 1), segmentLabel: nil, mode: mode,
                                 onAdvance: {}, onJump: { _, _ in }, onToggleMode: {}).background(Color.ground)
            #expect(try Snapshots.assert(view, named: name, size: Self.size))
        }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `ios/`): `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -collect-test-diagnostics never -only-testing:GraphghanTests/ChartImageTests -only-testing:GraphghanTests/BandLayoutTests -only-testing:GraphghanTests/ChartBandTests`
Expected: FAIL — `theGroundIsClear` (alpha is `noneSkipLast`), `boundaryStandsAtTheStitchedSpansEnd` (row 2 gives 56, the chart's edge), and `shaped` records two new references and fails once (a missing reference is recorded and fails by design).

(If the project file is stale because new test files were added, run `mise run generate` first. No new files are added in this task.)

- [ ] **Step 3: Implement**

`ChartImage.swift` — replace `make` with:

```swift
    /// One pixel per cell, RGBA premultiplied, top row first; a shaped piece's ground is clear.
    /// Scale it with nearest-neighbour to keep cells crisp.
    static func make(_ chart: Chart) -> CGImage? {
        guard let bytes = ChartPreview.pixels(chart), let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: chart.width, height: chart.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: chart.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
```

`BandLayout.swift` — in the `cursor.run == pass.runs.count` branch, replace `let endX = edge(ltr ? chart.width : 0)` with:

```swift
            // The turn is where the stitches end: the stitched span's edge, which on a shaped row
            // is inside the chart (spec §6.3); a full row's span is the chart, as before.
            let xs = pass.runs.compactMap { r in r.x0.map { ($0, $0 + r.count) } }
            let lo = xs.map(\.0).min() ?? 0
            let hi = xs.map(\.1).max() ?? chart.width
            let endX = edge(ltr ? hi : lo)
```

`ChartBand.swift`:
- Replace `drawRow`'s body after the guard with:

```swift
        // A shaped piece's ground is the band's own ground: no yarn, no hairlines (spec §6.3).
        let runs = chart.runsByRow[gridRow].filter { chart.isStitched(colorIndex: $0.colorIndex) }
        for run in runs {
            let rect = layout.runRect(x0: run.x0, count: run.count, top: top, height: height).offsetBy(dx: -offset, dy: 0)
            context.fill(Path(rect), with: .color(fill(run.colorIndex).opacity(opacity)))
        }
        guard let lo = runs.map(\.x0).min(), let hi = runs.map({ $0.x0 + $0.count }).max() else { return }
        // cell hairlines across the stitched span, then the span's bottom hairline
        for x in lo...hi {
            let px = layout.edge(x) - offset
            context.fill(Path(CGRect(x: px - 0.25, y: top, width: 0.5, height: height)), with: .color(Color.ink.opacity(0.10 * opacity)))
        }
        let a = layout.edge(lo), b = layout.edge(hi)
        context.fill(Path(CGRect(x: min(a, b) - offset, y: top + height - 0.25, width: abs(b - a), height: 0.5)), with: .color(Color.ink.opacity(0.15 * opacity)))
```

  (`layout.edge` replaces the old `CGFloat(x) * cell`, which also makes the hairlines honour ribbon mirroring. For a full row `lo...hi` is `0...chart.width` and `edge(x)` is `x * cell` in fabric style, so rectangles draw exactly as before; in ribbon style the hairlines were symmetric across the full width, so they land on the same pixels.)
- In `drawWhole`, change `for run in chart.runsByRow[gy] {` to `for run in chart.runsByRow[gy] where chart.isStitched(colorIndex: run.colorIndex) {`.

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command twice (the first run after recording passes compare).
Expected: PASS. Open `ios/Tests/__Snapshots__/band-shaped.png` and `band-shaped-whole.png` and confirm by eye: row 4's current row shows cells only in columns 1-6, the ground shows no hairlines, and the whole view is the piece's silhouette. Then run `mise run test` from `ios/` for the whole app suite: every existing snapshot (Craigh na Dun, rectangles) must pass compare unchanged.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/UI/ChartImage.swift ios/Graphghan/Work/ChartBand.swift ios/Graphghan/Work/BandLayout.swift ios/Tests/ChartImageTests.swift ios/Tests/BandLayoutTests.swift ios/Tests/ChartBandTests.swift ios/Tests/__Snapshots__/band-shaped.png ios/Tests/__Snapshots__/band-shaped-whole.png
git commit -m "ios: the band and the chart image draw a shaped piece's ground as ground (#37)"
```

---

### Task 6: Work screen — the row's stitches, its shaping and its printed text

**Files:**
- Create: `ios/Graphghan/Work/ShapedRowText.swift`, `ios/Tests/ShapedRowTextTests.swift`
- Modify: `ios/Graphghan/Work/WorkScreen.swift`
- Test: `ios/Tests/WorkScreenTests.swift` (+ `ios/Tests/__Snapshots__/work-shaped.png`)

**Interfaces:**
- Consumes: Task 3's `Chart.isShaped`, `Chart.written`, `WorkSequence.shaping(at:)`, `Shaping.sentence`, `WorkSequence.totalStitches`.
- Produces: `enum ShapedRowText { static func caption(chart:sequence:row:) -> String?; static func written(chart:row:) -> String? }`

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/ShapedRowTextTests.swift`:

```swift
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ShapedRowTextTests {
    static let chart = try! Chart.load(TestFixtures.data("shaped-basic.chart.json"))
    static let seq = try! WorkSequence(chart: chart)

    @Test func captionIsTheRowsStitchesAndItsShaping() {
        #expect(ShapedRowText.caption(chart: Self.chart, sequence: Self.seq, row: 1) == "3 sts")
        #expect(ShapedRowText.caption(chart: Self.chart, sequence: Self.seq, row: 2) == "5 sts · +1 at start, +1 at end")
        #expect(ShapedRowText.caption(chart: Self.chart, sequence: Self.seq, row: 4) == "6 sts · \u{2212}1 at start")
        #expect(ShapedRowText.caption(chart: Self.chart, sequence: Self.seq, row: 5) == "3 sts · \u{2212}2 at start, \u{2212}1 at end")
    }

    @Test func aRectangleHasNoCaption() throws {
        let chart = try Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
        #expect(ShapedRowText.caption(chart: chart, sequence: try WorkSequence(chart: chart), row: 42) == nil)
    }

    @Test func writtenIsThePassesOwnText() {
        #expect(ShapedRowText.written(chart: Self.chart, row: 2) == "R 2: ch 1, turn, 1 inc, 1 sc, 1 inc [5]")
        #expect(ShapedRowText.written(chart: Self.chart, row: 6) == nil)
    }
}
```

Append to `WorkScreenTests`:

```swift
    /// A shaped chart (#37): the header adds the row's stitches and its shaping, and the pattern's
    /// own row text sits under the panel.
    @Test func shaped() throws {
        let chart = try Chart.load(TestFixtures.data("shaped-basic.chart.json"))
        let seq = try WorkSequence(chart: chart)
        let view = WorkScreen(chart: chart, sequence: seq, cursor: Cursor(row: 4, run: 0), step: .ten, perRepetition: true,
                              onDone: {}, onBack: {}, onClose: {}, onJump: {}, onJumpWithinRow: { _, _ in }, onSetStep: { _ in }, onSetPerRepetition: { _ in })
        #expect(try Snapshots.assert(view, named: "work-shaped", size: Self.phone))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run (from `ios/`): `mise run generate` (a new test file), then `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -collect-test-diagnostics never -only-testing:GraphghanTests/ShapedRowTextTests -only-testing:GraphghanTests/WorkScreenTests`
Expected: FAIL to compile — `cannot find 'ShapedRowText' in scope`.

- [ ] **Step 3: Implement**

Create `ios/Graphghan/Work/ShapedRowText.swift`:

```swift
import GraphghanCore

/// What the Work screen says about a shaped row beyond its runs (spec 2026-09-25 §6.3): how many
/// stitches it has and how it changed from the row before, and the pattern's own words for it.
enum ShapedRowText {
    /// "5 sts · +1 at start, +1 at end". Nil for a rectangle, whose every row is the chart's width
    /// and whose screen stays exactly as it was.
    static func caption(chart: Chart, sequence: WorkSequence, row: Int) -> String? {
        guard chart.isShaped, let pass = sequence.pass(at: row) else { return nil }
        let count = "\(pass.cells) \(sequence.totalStitches == nil ? "cells" : "sts")"
        return [count, sequence.shaping(at: row)?.sentence].compactMap { $0 }.joined(separator: " · ")
    }

    /// The pattern's printed text for pass `row`, when the chart carries `written`.
    static func written(chart: Chart, row: Int) -> String? {
        guard let written = chart.written, row >= 1, row <= written.count else { return nil }
        return written[row - 1]
    }
}
```

In `WorkScreen.swift`:
- In `header`, after the side-text `Text(...)` inside `if let pass`, add:

```swift
                    if !finished, let caption = ShapedRowText.caption(chart: chart, sequence: sequence, row: cursor.row) {
                        Text(caption).font(Font.Heather.caption).foregroundStyle(Color.heather)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
```

- Add a view property:

```swift
    /// The pattern's own words for the row, under the panel (spec §6.3): how the shaping is made.
    @ViewBuilder private var writtenLine: some View {
        if !finished, let text = ShapedRowText.written(chart: chart, row: cursor.row) {
            Text(text).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                .lineLimit(3).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
    }
```

- In `body`, insert `writtenLine` after `panel(c)` in both layouts: compact `VStack(spacing: 14) { header; panel(c); writtenLine; Spacer(minLength: 0); bar(c) }` and regular `VStack(spacing: 14) { header; panel(c); writtenLine; band(c); bar(c) }`.

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 test command twice (the new snapshot records then compares). Look at `ios/Tests/__Snapshots__/work-shaped.png`: the header reads "Row 4 of 5", then the side line, then "6 sts · −1 at start" in Heather; the row's text "R 4: ch 1, turn, 1 dec, …" sits under the panel. Then run `mise run test` from `ios/`: every existing `work-*` snapshot must pass compare unchanged (they are Craigh na Dun, which has no caption and no `written`).

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/ShapedRowText.swift ios/Graphghan/Work/WorkScreen.swift ios/Tests/ShapedRowTextTests.swift ios/Tests/WorkScreenTests.swift ios/Tests/__Snapshots__/work-shaped.png ios/Graphghan.xcodeproj
git commit -m "ios: the Work screen says a shaped row's stitches, its shaping and the pattern's words (#37)"
```

(Add `ios/Graphghan.xcodeproj` only if `mise run generate` changed it and the repo tracks it; check with `git status`.)

---

### Task 7: The importer — Orca's front panel arrives as a shaped piece with its rows' text

**Files:**
- Modify: `ios/Graphghan/Services/PDFImporter.swift`
- Test: `ios/Tests/PDFImportTests.swift`, `ios/Tests/PDFImportRealTests.swift`

**Interfaces:**
- Consumes: Task 4's `ChartDraft.written` and schema-3 writer; `RowText.rowNumbers(of:)`, `RowSection.blocks` (ProseReaderKit, public).
- Produces: `PDFImporter.writtenRows(_ section: RowSection?, height: Int) -> [String]?` (static).

Schema 3 itself needs no importer change: `GridChart.draft` already marks the background (#208) and Task 4's writer turns that mark into schema 3. This task pins that on Orca and fills `written` from the section `readGrid` already pairs with the chart (`RowText.section(fitting:in:)`); spec §7.2 generalises the pairing to every chart in PR 3.

- [ ] **Step 1: Write the failing tests**

Append to `PDFImportTests`:

```swift
    /// The chart's own rows become its `written` text only when they print rows 1...height once
    /// each, in order, one to a block; anything else would misalign a row with its text.
    @Test func writtenRowsNeedEveryRowOnceInOrder() {
        let page = "R 1 [←]: (Black) ch 4, 3 sc [3]\nR 2 [→]: (Black) ch 1, turn, 1 inc, 1 sc, 1 inc [5]\nR 3 [←]: (White) ch 1, turn, 5 sc [5]"
        let section = RowText.sections(in: [page]).first
        #expect(PDFImporter.writtenRows(section, height: 3)?.count == 3)
        #expect(PDFImporter.writtenRows(section, height: 3)?.first?.hasPrefix("R 1") == true)
        #expect(PDFImporter.writtenRows(section, height: 4) == nil)
        let ranged = RowText.sections(in: ["R 1: (Black) ch 4, 3 sc [3]\nR 2 - R 3: (Black) ch 1, turn, 3 sc [3]"]).first
        #expect(PDFImporter.writtenRows(ranged, height: 3) == nil)
        #expect(PDFImporter.writtenRows(nil, height: 3) == nil)
    }
```

(If `RowText.sections` splits this synthetic page differently from what the assertion expects, print `RowText.blocks(in: page)` in the test once, and adjust the page text to the head format the existing `aChartPageCountsTheSetsOfRowsItLeftOut` test uses; do not change the rule.)

Append to `PDFImportRealTests`:

```swift
    /// Orca's front panel is a shaped piece (#37): chart schema 3, 9 stitches at row 1 from grid
    /// column 6, 29 at the widest, 3 at row 77, 1805 stitches in all (the Python's grid read of
    /// page 9 region 1), and its own 77 written rows as the chart's `written` text.
    @Test func orcaIsAShapedPiece() async throws {
        let file = "EN_OrcaCrossbodyBagPDFPattern.pdf"
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/\(file)")
        guard let data = try? Data(contentsOf: url) else {
            print("SKIP real fixture \(file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = PDFImporter(charts: ChartLibrary(directory: try temporaryDirectory()), local: LocalPatternStore(directory: try temporaryDirectory()),
                                   rowReader: nil, modelUnavailable: nil)
        let reading = try await importer.read(data, fileName: file)
        let chart = reading.bundle.charts[0].chart
        #expect(chart.document.schema == 3 && chart.isShaped && reading.colours == 3)
        let seq = try WorkSequence(chart: chart)
        #expect(seq.passes.count == 77)
        #expect(seq.passes[0].cells == 9 && seq.passes[0].runs.compactMap(\.x0).min() == 6)
        #expect(seq.passes.map(\.cells).max() == 29 && seq.passes[76].cells == 3)
        #expect(seq.totalCells == 1805)
        #expect(reading.bundle.manifest.charts[0].stitches == 1805)
        #expect(chart.written?.count == 77)
        #expect(chart.written?.first?.hasPrefix("R 1") == true)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Make sure the Orca PDF is present (`ls fixtures/import/real/EN_OrcaCrossbodyBagPDFPattern.pdf`; if not: `mkdir -p fixtures/import/real && cp -n ~/orca/workspaces/graphghan/row-check-on-a-device-foundation-models-answers/fixtures/import/real/* fixtures/import/real/`).

Run (from `ios/`): `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -collect-test-diagnostics never -only-testing:GraphghanTests/PDFImportTests -only-testing:GraphghanTests/PDFImportRealTests`
Expected: FAIL to compile — `type 'PDFImporter' has no member 'writtenRows'`.

- [ ] **Step 3: Implement**

In `PDFImporter.swift`, add near `readGrid`:

```swift
    /// The chart's own written rows as its `written` text (spec 2026-09-25 §5.1): one printed row
    /// per pass, row 1 first. Only when the section prints every row 1...height once, in order,
    /// one row to a block; a range, a gap or a row printed twice leaves `written` out rather than
    /// set a row beside another row's words.
    static func writtenRows(_ section: RowSection?, height: Int) -> [String]? {
        guard let section, section.blocks.count == height else { return nil }
        for (i, block) in section.blocks.enumerated() where RowText.rowNumbers(of: block.text) != [i + 1] { return nil }
        return section.blocks.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
```

In `readGrid`, change `let draft: ChartDraft` to `var draft: ChartDraft`, and after `let own = RowText.section(fitting: best.region.rows, in: texts)` add:

```swift
        // The pattern's own words for each row go with the chart, so the Work screen can say how
        // a shaped row's stitches are added or taken away (#37).
        draft.written = Self.writtenRows(own, height: best.region.rows)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the Step 2 command.
Expected: PASS. If `orcaIsAShapedPiece` fails **only** on the two `written` lines, the front panel's section does not print one row to a block under PDFKit's text: stop, print `own?.blocks.count` and the first three block texts, and report them rather than loosening the rule. Then run `mise run test`: `aShapedChartsBackgroundIsNoStitch`, `aRealPDFSaysWhatItLeftOut` and the Orca check tests must stay green (the grid's cells are unchanged; only the document's schema, id and `written` are new).

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Services/PDFImporter.swift ios/Tests/PDFImportTests.swift ios/Tests/PDFImportRealTests.swift
git commit -m "ios: Orca's front panel imports as a shaped piece with its rows' own text (#37, #205)"
```

---

### Task 8: Verify everything and open the PR

**Files:** none new.

- [ ] **Step 1: Run every suite**

From the repo root: `uv run pytest -q` and `mise run lint`. From `ios/`: `mise run core-test`, `mise run prose-test`, `mise run test`.
Expected: all pass; lint clean. If `mise run lint` reformats Python, re-run the Python tests and commit the formatting separately.

- [ ] **Step 2: Check the invariants by hand**

- `git diff origin/main --stat -- fixtures/ | grep -v shaped` shows only `generate.py` and `README.md` changed among pre-existing fixture files (no existing `*.json` fixture moved).
- `git diff origin/main -- fixtures/bundle` is empty.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin HEAD
gh pr create --title "Shaped chart pieces: chart schema 3 (#37)" --body-file - <<'EOF'
Closes #205. Refs #37 and #206: the first of the three PRs in `docs/superpowers/specs/2026-09-25-pieces-and-shaped-rows-design.md` §8. Both issues stay open for the pieces and importer PRs.

## What changes

- **Format, chart schema 3** (`docs/chart-format.md` §Shaped rows, `schema/chart.schema.json`, new conformance fixtures `shaped-basic` and `progress-shaped`):
  - One palette colour may be `"stitch": false`, and only at the ends of rows.
  - Readers leave that colour out of the working order, stats, progress and the foundation rule.
  - Shaping ("+1 at start") is derived from each row's stitched span.
  - `no_stitch` is part of the chart id.
  - Optional `written` holds the pattern's own row text.
  - Writers emit schema 3 only when that colour exists, so every existing chart and bundle is byte-identical.
- **Python** (`chartdoc`, `export.stats`) and **Swift** (`GraphghanCore`) both read schema 3 against the same fixtures.
- **The phone:**
  - A background that #208 marked is written as schema 3.
  - The Work screen's strip, the whole-chart view and the library image draw the ground as ground.
  - The turn marker stands where the stitches end.
  - The header says "6 sts · −1 at start", and the pattern's row text sits under the panel.
- **Orca** imports as 9 → 29 → 3 stitches (1805 in all), 3 colours, with its 77 written rows.

## Tests

<fill in from Step 1's output: the counts per suite, and the snapshots added (band-shaped, band-shaped-whole, work-shaped)>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

Replace the `<fill in …>` line with the real numbers before running the command.

- [ ] **Step 4: See it to green**

Watch CI and CodeRabbit with a bounded watcher: at most 20 minutes, polling `gh pr checks <n>` every 30 seconds and stopping once no check is pending. Address every valid CodeRabbit finding. When a stale "changes requested" review's findings are confirmed fixed and the re-review is rate limited, dismiss it with a message naming the fixing commit.
