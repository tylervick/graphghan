# Gauge Unit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Derive a finished size only when the gauge's counting unit and the grid's cell cardinality name the same thing, and withhold it otherwise — turning `gauge.unit` from a declared-but-ignored field into the one that gives C2C a correct size.

**Architecture:** One predicate, `size_derives`, implemented identically in Python, Swift and JS from a single two-entry table (`stitch` ↔ `stitches`, `tile` ↔ `tiles`). Everything that divides the grid by the gauge consults it first. A withheld size is `None`/`nil`/`null` and an absent key — never zero, never a placeholder. Both source fields default and their defaults pair, so every existing chart keeps the size it has today.

**Tech Stack:** Python 3 (`uv run pytest`), Swift 6 (`mise run core-test`, `mise run test` in `ios/`), vanilla JS for the site, JSON Schema Draft 2020-12.

**Spec:** `docs/superpowers/specs/2026-09-14-gauge-unit-design.md`

## Global Constraints

- The pairing is exactly two entries: `gauge.unit: "stitches"` ↔ `chart.cell.kind: "stitch"`, and `gauge.unit: "tiles"` ↔ `chart.cell.kind: "tile"`. Every other combination — `repeats`, `rounds`, or any mismatch — withholds.
- Both fields default and **their defaults pair**: absent `gauge.unit` means `"stitches"`, absent `chart.cell` means `"stitch"`. **Every existing fixture and pattern must keep byte-identical finished sizes and `stats.size_in` values.** Task 6 pins this with a test.
- `unit` is plural, `kind` is singular. The mapping is a table, never string equality.
- A withheld size is absence: `None` in Python, `nil` in Swift, `null` in JS, and the `stats.size_in` key omitted entirely. Never `0`, never `[0, 0]`, never "—".
- A unit/kind mismatch is **withheld, never refused**. `validate_document` gains nothing and `schema/chart.schema.json` is not touched — `gauge.unit`'s enum already exists.
- `cell_aspect` / `cellAspect` is NOT gated. It is `stitches / rows`, a ratio of two numbers in the same unit, so the unit cancels.
- No new authoring surface. `pattern.toml`'s `[stitch.<key>].unit` already authors this (`pattern.py:94-97` → `export.py:197`).
- Python: `uv run pytest -q` from the repo root (currently 217). Swift package: `mise run core-test` from `ios/` (currently 86). App: `mise run test` from `ios/`. Lint: `mise run lint`.
- Commit after every task, conventional-commit subjects in the repo's style (`format:`, `core:`, `site:`, `docs:`).

---

### Task 1: The pairing predicate and a withheld `finished_size`

**Files:**
- Modify: `src/graphghan/chartdoc.py` (add the table and `size_derives` near `CELL_KINDS` at :25; change `finished_size` at :121-127)
- Test: `tests/test_chartdoc.py` (extend `test_derived_sizes` at :284)

**Interfaces:**
- Consumes: `chartdoc.cell_kind(doc) -> str` (from #44; total, returns `"stitch"` for absent/malformed).
- Produces: `chartdoc.UNIT_FOR_KIND: dict[str, str]`, `chartdoc.size_derives(doc: dict) -> bool`, and `chartdoc.finished_size(doc: dict) -> tuple[float, float, str] | None`. Tasks 2, 3 and 6 consume all three.

- [ ] **Step 1: Write the failing tests**

In `tests/test_chartdoc.py`, after the existing `test_derived_sizes`:

```python
def test_size_derives_when_unit_and_kind_agree():
    d = doc(["4A"], width=4)
    assert chartdoc.size_derives(d)  # both absent: stitches <-> stitch

    d = doc(["4A"], width=4, cell={"kind": "tile"})
    d["gauge"]["unit"] = "tiles"
    assert chartdoc.size_derives(d)


def test_size_withheld_when_unit_and_kind_disagree():
    d = doc(["4A"], width=4, cell={"kind": "tile"})  # tile cells, stitch gauge
    assert not chartdoc.size_derives(d)
    assert chartdoc.finished_size(d) is None

    d = doc(["4A"], width=4)  # stitch cells, tile gauge
    d["gauge"]["unit"] = "tiles"
    assert not chartdoc.size_derives(d)
    assert chartdoc.finished_size(d) is None


def test_size_withheld_for_units_we_cannot_resolve():
    for unit in ("repeats", "rounds"):
        d = doc(["4A"], width=4)
        d["gauge"]["unit"] = unit
        assert not chartdoc.size_derives(d), unit
        assert chartdoc.finished_size(d) is None, unit


def test_tile_gauge_derives_the_c2c_size():
    """5.5 tiles = 4 in over a 22-tile grid is 16 in wide, not whatever 5.5 stitches would give."""
    d = doc(["4A"], width=4, cell={"kind": "tile"})
    d["chart"]["width"], d["chart"]["height"] = 22, 22
    d["gauge"] = {"stitches": 5.5, "rows": 5.5, "over": {"value": 4, "unit": "in"}, "unit": "tiles"}
    assert chartdoc.finished_size(d) == (16.0, 16.0, "in")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest tests/test_chartdoc.py -k "size_derives or withheld or c2c" -v`
Expected: FAIL — `AttributeError: module 'graphghan.chartdoc' has no attribute 'size_derives'`

- [ ] **Step 3: Add the table and the predicate**

In `src/graphghan/chartdoc.py`, immediately after `cell_kind` (which ends around line 32):

```python
# `gauge.unit` says what `gauge.stitches` and `gauge.rows` count; `chart.cell.kind` says what one
# grid cell is. Dividing the grid by the gauge is valid exactly when they name the same thing, so
# these two are the pairs a finished size can be derived from (#48). `repeats` waits on #39 and
# `rounds` on a stated relationship between a round and a cell; both withhold.
UNIT_FOR_KIND = {"stitch": "stitches", "tile": "tiles"}


def size_derives(doc: dict) -> bool:
    gauge = doc.get("gauge")
    unit = gauge.get("unit", "stitches") if isinstance(gauge, dict) else "stitches"
    return UNIT_FOR_KIND.get(cell_kind(doc)) == unit
```

A kind with no entry (`block`, `motif`, `pair`) yields `None`, which never equals a unit string, so it withholds without a special case.

- [ ] **Step 4: Gate `finished_size`**

Replace `finished_size` (currently at :121-127):

```python
def finished_size(doc: dict) -> tuple[float, float, str] | None:
    """Finished width and height at the design gauge, or None when the gauge and the grid do not
    count the same thing (#48). A wrong size is worse than none."""
    if not size_derives(doc):
        return None
    g = doc["gauge"]
    per = g["over"]["value"]
    w = doc["chart"]["width"] / (g["stitches"] / per)
    h = doc["chart"]["height"] / (g["rows"] / per)
    return round(w, 1), round(h, 1), g["over"]["unit"]
```

- [ ] **Step 5: Run the tests**

Run: `uv run pytest tests/test_chartdoc.py -v`
Expected: PASS, including the pre-existing `test_derived_sizes` at :284 unchanged — it uses a document with neither field, whose defaults pair.

- [ ] **Step 6: Run the full suite**

Run: `uv run pytest -q`
Expected: some failures in `tests/test_export.py` and/or `tests/test_cli.py` are acceptable here ONLY if they come from `finished_size` now returning `None`; Tasks 2 and 3 fix those. Record exactly which tests fail and why in your report. If anything else fails, stop and report it.

- [ ] **Step 7: Commit**

```bash
git add src/graphghan/chartdoc.py tests/test_chartdoc.py
git commit -m "format: a finished size derives only when the gauge and the grid agree"
```

---

### Task 2: `stats.size_in` follows the same rule

**Files:**
- Modify: `src/graphghan/export.py` (`stats` signature at :96, the `size_in` entry at :113, and the `chart_json` call site at :228)
- Test: `tests/test_export.py`

**Interfaces:**
- Consumes: `chartdoc.size_derives(doc)` from Task 1.
- Produces: `export.stats(a, codes, kind="stitch", sized=True) -> dict`. `size_in` is emitted only when `sized` is true. Task 6's fixture generator consumes this signature.

**Why a boolean rather than the unit:** `stats` computes `size_in` as `w * gr.SW` by `h * gr.SH` — the *active gauge's per-stitch dimensions* from the `grid` module, not from the document's `gauge` block at all. That is exactly why a tiles chart's `size_in` is wrong today. `stats` has no document to inspect, so the caller resolves the pairing and passes one boolean.

- [ ] **Step 1: Write the failing tests**

In `tests/test_export.py`, beside the existing stats tests:

```python
def test_stats_omits_size_in_when_the_size_does_not_derive():
    s = export.stats(small(), ["A", "B"], sized=False)
    assert "size_in" not in s
    # Everything else the kind allows is still there.
    assert s["cells"] == 15 and s["counts"] == {"A": 12, "B": 3}


def test_stats_emits_size_in_by_default():
    s = export.stats(small(), ["A", "B"])
    assert s["size_in"] == [round(5 / 3.5, 1), 0.8]
```

Note `small()` (`tests/test_export.py:23`) returns a 3x5 `np.uint8` grid and takes no arguments; codes are the literal `["A", "B"]`. The existing `test_stats_sum_and_changes` calls `gr.set_gauge("sc")` first — do the same if your test asserts `size_in` values.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest tests/test_export.py -k size_in -v`
Expected: FAIL — `TypeError: stats() got an unexpected keyword argument 'sized'`

- [ ] **Step 3: Gate `size_in`**

In `src/graphghan/export.py`, change the signature and move `size_in` out of the unconditional block:

```python
def stats(a, codes, kind="stitch", sized=True):
```

Remove `"size_in": [round(w * gr.SW, 1), round(h * gr.SH, 1)],` from the `out = {...}` literal, and add this immediately after that literal, before the `if kind == "stitch":` block:

```python
    if sized:
        # gr.SW/gr.SH are per-STITCH dimensions, so this conversion is only meaningful when the
        # gauge and the grid count the same thing (#48). The caller resolves that pairing.
        out["size_in"] = [round(w * gr.SW, 1), round(h * gr.SH, 1)]
```

- [ ] **Step 4: Thread the pairing at the call site**

In `chart_json` (around :228), the document is assembled as a dict literal whose `"stats"` value is `stats(a, codes)`. The pairing depends on `gauge` and `chart.cell`, both of which that literal builds. Build the document first, then attach stats:

```python
    doc["stats"] = stats(a, codes, chartdoc.cell_kind(doc), chartdoc.size_derives(doc))
```

placed after the `doc = {...}` literal and after the `foundation` block, with `"stats"` removed from the literal itself. Import `chartdoc` if `export.py` does not already — check its existing imports and follow them.

- [ ] **Step 5: Run the tests**

Run: `uv run pytest tests/test_export.py -q`
Expected: PASS. The generator authors no `cell` and no non-stitch `unit`, so `size_derives` is true for every chart it writes and the output is unchanged.

- [ ] **Step 6: Run the full suite**

Run: `uv run pytest -q`
Expected: PASS except any `tests/test_cli.py` failure from Task 1, which Task 3 fixes. Record what remains.

- [ ] **Step 7: Commit**

```bash
git add src/graphghan/export.py tests/test_export.py
git commit -m "format: stats.size_in follows the gauge/grid pairing"
```

---

### Task 3: The options page survives a withheld size

**Files:**
- Modify: `src/graphghan/cli.py:183-195` (`cmd_options`)
- Test: `tests/test_cli.py`

**Interfaces:**
- Consumes: `chartdoc.finished_size(doc) -> tuple | None` from Task 1.
- Produces: nothing other tasks read.

- [ ] **Step 1: Read the two breakages**

`cmd_options` builds an options preview. Two lines in it assume numbers that are now conditional:

- `:188` — `w_in, h_in, _unit = finished_size(doc)` raises `TypeError: cannot unpack non-sequence NoneType` the moment a size is withheld.
- `:185` — `doc["stats"]["stitches"] / per_hr` raises `KeyError` for a non-stitch chart. **That one is a pre-existing escape from #44**, not caused by this plan; it sits on the adjacent line inside the function you are already fixing. Fix both, and say so in your report so a reviewer sees the second was deliberate rather than scope creep.

- [ ] **Step 2: Write the failing test**

Follow `tests/test_cli.py`'s existing style for invoking a command (it calls `main([...])` with a pattern directory). Add a test that a chart whose size does not derive still produces an options page, asserting the command returns 0 and the entry carries no size rather than raising. If the test module has no seam for injecting a non-stitch chart, construct the entry-building path directly and say so in your report.

```python
def test_options_entry_without_a_derived_size(tmp_path):
    """A withheld size must not crash the options page; the entry simply carries no size."""
    # Build a doc whose gauge counts tiles while its cells are stitches, so size_derives is False.
    # Assert the options command completes and the rendered entry omits the size.
```

Write the body against whatever seam `test_cli.py` already uses; do not invent a new harness.

- [ ] **Step 3: Run it to verify it fails**

Run: `uv run pytest tests/test_cli.py -k options -v`
Expected: FAIL with the unpack `TypeError`.

- [ ] **Step 4: Handle both absences**

Replace the two lines:

```python
            stitches = doc["stats"].get("stitches")
            hours = (
                None
                if stitches is None
                else stitches / per_hr
                + sum(doc["stats"]["color_changes_per_row"]["per_row"]) * 3 / 3600
            )
            size = finished_size(doc)
```

and in the `entries.append({...})` literal, replace `"size_in": [w_in, h_in],` with `"size_in": None if size is None else [size[0], size[1]],` and `"hours": round(hours),` with `"hours": None if hours is None else round(hours),`.

Then check `src/graphghan/options_page.py` (the renderer these entries feed) for anything that formats `size_in` or `hours` and make it omit the value rather than print `None`. Report what you found there.

- [ ] **Step 5: Run the tests**

Run: `uv run pytest tests/test_cli.py -q`
Expected: PASS

- [ ] **Step 6: Run the full suite**

Run: `uv run pytest -q`
Expected: PASS — 217 plus your new tests, with nothing left failing from Tasks 1 and 2.

- [ ] **Step 7: Commit**

```bash
git add src/graphghan/cli.py src/graphghan/options_page.py tests/test_cli.py
git commit -m "format: the options page handles a withheld size and stitch count"
```

---

### Task 4: Swift reads the `unit` it already decodes

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Chart.swift` (add `sizeDerives`, change `finishedSize` at :70-75)
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartTests.swift` (`:48` asserts the current non-optional shape)

**Interfaces:**
- Consumes: `Chart.cellKind: CellKind` (from #44), `document.gauge.unit: String?` (already decoded at `ChartDocument.swift:116` and used nowhere).
- Produces: `Chart.sizeDerives: Bool` and `Chart.finishedSize: FinishedSize?`. Task 6's conformance test consumes both.

- [ ] **Step 1: Write the failing tests**

In `ChartTests.swift`:

```swift
@Test func sizeDerivesWhenUnitAndKindAgree() throws {
    let chart = try Self.chart("craigh-na-dun")  // neither field present: the defaults pair
    #expect(chart.sizeDerives)
    #expect(chart.finishedSize?.width == 54)
}

@Test func sizeIsWithheldWhenUnitAndKindDisagree() throws {
    // filet-blocks declares cell.kind "block" with a stitch gauge — no pairing, no size.
    let chart = try Self.chart("filet-blocks")
    #expect(!chart.sizeDerives)
    #expect(chart.finishedSize == nil)
}
```

`Self.chart(_:)` is the static loader at `ChartTests.swift:6` (`try Chart.load(Fixtures.data("\(name).chart.json"))`). There is no `Fixtures.chart(_:)`.

- [ ] **Step 2: Run to verify failure**

Run (from `ios/`): `mise run core-test`
Expected: FAIL — no member `sizeDerives`.

- [ ] **Step 3: Add the predicate and make the size optional**

In `Chart.swift`, beside `cellAspect`:

```swift
    /// `gauge.unit` says what the gauge counts; `cellKind` says what one grid cell is. Dividing the
    /// grid by the gauge is valid exactly when they name the same thing (#48). Mirrors
    /// graphghan.chartdoc.size_derives.
    public var sizeDerives: Bool {
        let unit = document.gauge.unit ?? "stitches"
        switch cellKind {
        case .stitch: return unit == "stitches"
        case .tile: return unit == "tiles"
        case .block, .motif, .pair: return false
        }
    }

    /// Finished size at the design gauge, or nil when the gauge and the grid do not count the same
    /// thing. A wrong size is worse than none.
    public var finishedSize: FinishedSize? {
        guard sizeDerives else { return nil }
        let g = document.gauge
        let w = Double(width) / (g.stitches / g.over.value)
        let h = Double(height) / (g.rows / g.over.value)
        return FinishedSize(width: (w * 10).rounded() / 10, height: (h * 10).rounded() / 10, unit: g.over.unit)
    }
```

Switch exhaustively over `CellKind` rather than using `default:` — a sixth kind should fail to compile here and force a decision, not silently withhold.

- [ ] **Step 4: Update the existing assertion**

`ChartTests.swift:48` reads `chart.finishedSize.width == 54 && ...`. Make it optional-aware, keeping the same expected numbers (54, 46, "in").

- [ ] **Step 5: Fix any other call site**

Run: `grep -rn "finishedSize" ios --include='*.swift'`
Expected: only `Chart.swift` and the tests. The app reads the site manifest's `size`, not this property (that path is #61). Report anything else the grep finds.

- [ ] **Step 6: Run the tests**

Run (from `ios/`): `mise run core-test`, then `mise run test`
Expected: PASS both.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/GraphghanCore/
git commit -m "core: finishedSize is nil when the gauge and the grid disagree"
```

---

### Task 5: The site stops showing a wrong size and a wrong gauge noun

**Files:**
- Modify: `site/src/app/data.js` (`finishedSize` at :63; add `sizeDerives` beside `cellKind`/`cellNoun` at :78-89)
- Modify: `site/src/app/pattern.js:26-33` (the `unit` symbol, the Finished spec, the Gauge spec)
- Test: `tests/test_js_parity.py`

**Interfaces:**
- Consumes: `cellKind(chart)` from `data.js` (added in #44; takes the **chart** object, not the document).
- Produces: `sizeDerives(doc) -> boolean` and `finishedSize(doc) -> {w, h, unit} | null`, both exported from `data.js`.

- [ ] **Step 1: Add the predicate and return null**

In `site/src/app/data.js`, beside the existing `CELL_KIND_NOUNS`/`cellKind`/`cellNoun`:

```js
const UNIT_FOR_KIND = { stitch: 'stitches', tile: 'tiles' };
export function sizeDerives(doc) {
  const unit = (doc.gauge && doc.gauge.unit) || 'stitches';
  return UNIT_FOR_KIND[cellKind(doc.chart)] === unit;
}
```

and gate the existing `finishedSize`:

```js
export function finishedSize(doc) {
  if (!sizeDerives(doc)) return null;
  const g = doc.gauge, per = g.over.value;
  return { w: +(doc.chart.width / (g.stitches / per)).toFixed(1), h: +(doc.chart.height / (g.rows / per)).toFixed(1), unit: g.over.unit };
}
```

- [ ] **Step 2: Fix the two consumers in `pattern.js`**

Two problems at `:26-33`, both caused by the same change:

1. `const unit = size.unit === 'in' ? '″' : ' cm';` dereferences `size`, which can now be null — and that `unit` symbol is *also* used by the Gauge spec two lines down, so a null size would break a row that has nothing to do with the finished size. Derive the symbol from `G.over.unit` directly instead:

```js
  const size = finishedSize(doc);
  const unit = G.over.unit === 'in' ? '″' : ' cm';
```

2. The specs array hardcodes `st` in the Gauge row — `` `${G.stitches} st × ${G.rows} rows` `` — which is wrong for a tiles gauge. Use the gauge's own unit, and drop the Finished entry when the size is null:

```js
  const gaugeNoun = (G.unit || 'stitches') === 'stitches' ? 'st' : (G.unit || 'stitches');
  const specs = [['Chart', `${chart.W} × ${chart.H}`, `${cellNoun(C)} × rows`]];
  if (size) specs.push(['Finished', `${size.w}${unit} × ${size.h}${unit}`, 'at design gauge']);
  specs.push(['Colors', String(doc.palette.length), G.yarn_weight || ''],
    ['Stitch', G.stitch || '', `1 cell = 1 ${cellKind(C)}`], ['Hook', G.hook || '', ''],
    ['Gauge', `${G.stitches} ${gaugeNoun} × ${G.rows} rows`, `= ${G.over.value}${unit} blocked`],
    ['Version', P.version, C.variant || '']);
```

Keep the row order otherwise unchanged, and keep `'st'` for a stitches gauge so today's page is byte-identical.

- [ ] **Step 3: Add a parity test**

In `tests/test_js_parity.py`, following the Node-harness pattern that file already uses for `sequence` and `cellNoun`, add a test asserting that for every fixture in `fixtures/chart-format/`, JS `finishedSize(doc)` agrees with Python `chartdoc.finished_size(doc)` — both null/None together, and equal numbers otherwise.

- [ ] **Step 4: Rebuild and run**

Run: `uv run python site/build.py`
Run: `uv run pytest tests/test_js_parity.py site/tests -q`
Expected: PASS. `site/dist/` is not tracked by git, so nothing from it is staged.

- [ ] **Step 5: Run the full suite**

Run: `uv run pytest -q`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add site/src/app/data.js site/src/app/pattern.js tests/test_js_parity.py
git commit -m "site: no finished size when the gauge and the grid disagree"
```

---

### Task 6: A tiles fixture, and proof that no existing size moved

**Files:**
- Create: `fixtures/chart-format/tiles-gauge.chart.json`, `fixtures/chart-format/tiles-gauge.sequence.json`
- Modify: `fixtures/chart-format/generate.py`, `fixtures/chart-format/README.md`
- Modify: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/FixturesTests.swift` (the hardcoded fixture-name list)
- Test: `tests/test_conformance.py`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: the fixture name `tiles-gauge`, which the Swift conformance tests pick up automatically via `Fixtures.chartNames`.

- [ ] **Step 1: Add the fixture to the generator**

`generate.py`'s `chart(pid, title, palette, rows, technique, passes=None, layers=None, cell=None)` helper gained a `cell` parameter in #44. Add a `gauge=None` parameter that overrides the module's `GAUGE` constant when given, then add a `tiles-gauge` fixture: a small C2C-shaped grid, `cell={"kind": "tile"}`, and a gauge of `{"stitches": 5.5, "rows": 5.5, "over": {"value": 4, "unit": "in"}, "unit": "tiles"}` — the "5.5 tiles = 4 in" figure from `docs/research/genres/c2c.md`.

Hand-write its `.sequence.json` as an independent expectation, per the module docstring's stated rule for small fixtures. Do NOT generate it from `chartdoc.sequence`.

- [ ] **Step 2: Add `tiles-gauge` to the Swift fixture-name list**

`FixturesTests.swift:6-9` hardcodes the expected fixture set. It currently lists eight names; add `"tiles-gauge"` in alphabetical order. **Skipping this leaves the Swift suite red** — it is the same trap a previous branch hit when it added `filet-blocks`.

- [ ] **Step 3: Run the generator**

Run: `uv run python fixtures/chart-format/generate.py`
Expected: the two new files appear. Commit exactly what it produces; `test_fixtures_are_fresh` byte-compares.

- [ ] **Step 4: Write the conformance tests**

In `tests/test_conformance.py`:

```python
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


@pytest.mark.parametrize("name", CHART_NAMES)
def test_no_existing_finished_size_moved(name):
    """Global constraint: both fields default and their defaults pair, so every chart that carries
    neither keeps the size it had before #48."""
    chart = json.loads((FIX / f"{name}.chart.json").read_text(encoding="utf-8"))
    if "cell" in chart["chart"] or chart["gauge"].get("unit"):
        pytest.skip("declares a pairing; covered by the tests above")
    assert chartdoc.finished_size(chart) is not None
```

Use whatever the module already names its fixture-name list; `CHART_NAMES` above stands for it — check the top of `test_conformance.py` before writing.

- [ ] **Step 5: Document the fixture**

Add a line to `fixtures/chart-format/README.md` saying what `tiles-gauge` pins: a chart whose gauge and cells both count tiles, so the finished size derives — and that removing its `cell` declaration withholds it.

- [ ] **Step 6: Run everything**

Run: `uv run pytest -q`
Run (from `ios/`): `mise run core-test`
Expected: PASS both.

- [ ] **Step 7: Commit**

```bash
git add fixtures/chart-format/ tests/test_conformance.py ios/Packages/GraphghanCore/Tests/
git commit -m "format: tiles-gauge conformance fixture, a size that derives from tiles"
```

---

### Task 7: Say it in the format doc

**Files:**
- Modify: `docs/chart-format.md` (§Gauge around :140-144; the `stats.size_in` row in §Cells at :120)

**Interfaces:**
- Consumes: everything above.
- Produces: the normative text other implementations build against.

- [ ] **Step 1: Rewrite the §Gauge sentence about `unit`**

The section currently says `unit` says what `stitches` and `rows` count and that "a reader that does not understand the unit derives no finished size (#48; neither reader in this repo checks the unit yet, and nothing authors one)". Both parenthetical claims are now false — the readers check it, and `pattern.toml` authors it. Replace with text stating the actual rule:

```markdown
`unit` says what `stitches` and `rows` count — `stitches` (default), `tiles`, `repeats` or
`rounds`. A finished size is derived only when `unit` and `chart.cell.kind` name the same thing:
`stitches` with `stitch`, or `tiles` with `tile`. Both fields default and their defaults pair, so a
chart that states neither is sized as stitches over stitches, as it always was. Any other
combination — a mismatch, or `repeats` (#39) and `rounds`, whose relationship to a grid cell is not
stated — derives no finished size, and readers MUST omit it rather than compute one. `stats.size_in`
follows the same rule.
```

- [ ] **Step 2: Update the `stats.size_in` row in §Cells**

That row currently reads "emitted | emitted — governed by `gauge.unit` (#48), not by this". This phase *is* that #48. Change it to say the value follows the gauge/cell pairing described in §Gauge, and is absent when the size does not derive.

- [ ] **Step 3: Check for other stale prose**

Run: `grep -rn "finished size\|size_in\|derives no" docs/chart-format.md`
Fix any remaining sentence that claims a size is always derivable. Report what you found.

- [ ] **Step 4: Run everything**

Run: `uv run pytest -q && mise run lint`
Run (from `ios/`): `mise run core-test && mise run test`
Expected: PASS

- [ ] **Step 5: Commit and open the PR**

```bash
git add docs/chart-format.md
git commit -m "docs: a finished size needs the gauge and the grid to agree"
```

Open the PR against `main` with `Closes #48` in the body, referencing the spec and this plan.

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §3.1 the pairing table, defaults pair | 1, pinned by 6 |
| §3.2 `finished_size` → None | 1 |
| §3.2 `stats.size_in` absent | 2 |
| §3.2 `Chart.finishedSize` → nil | 4 |
| §3.2 `finishedSize` → null, Finished row omitted | 5 |
| §3.2 `cell_aspect` untouched | (no task — deliberately unchanged; Task 1 leaves it alone) |
| §3.3 `cli.py` consumer | 3 |
| §3.3 `pattern.js` consumer | 5 |
| §3.3 Swift has no app call site | 4, Step 5 verifies |
| §3.4 no validation and no schema change | (no task — deliberately absent) |
| §3.5 fixtures, mismatch case, compatibility test, parity | 6, and 5 Step 3 for parity |
| §4 deferred `repeats`/`rounds` | 7's normative text; issues filed separately |

Two spec items deliberately have no task: `cell_aspect` stays as-is, and §3.4 adds nothing. Both are stated so an executor does not go looking.

**Placeholder scan:** Task 3's Step 2 and Task 6's Step 4 name a local test seam the plan cannot know the spelling of (`test_cli.py`'s command harness, `test_conformance.py`'s fixture-name list). Each says to check the file first and follow its existing style rather than invent one — a lookup, not a placeholder. Task 3 Step 4 also asks the implementer to inspect `options_page.py` and report; that is genuine discovery, not a deferred decision.

**Type consistency:** `size_derives` (Python) / `sizeDerives` (Swift, JS) name the same predicate throughout. `finished_size` returns `tuple | None`, `finishedSize` returns `FinishedSize?` and `{w,h,unit} | null` — consistently optional from their defining tasks onward. `UNIT_FOR_KIND` holds the same two entries in Python and JS; Swift spells it as an exhaustive switch so a new kind fails to compile.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-15-gauge-unit.md`.
