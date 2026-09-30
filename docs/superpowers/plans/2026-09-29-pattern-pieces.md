# Pattern Pieces (manifest 2, written rows, progress 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pattern can be made of pieces: charts and written-only pieces plus assembly steps, held in a manifest-2 bundle; starting it makes one project whose pieces each keep their own cursor, worked on the Work screen (a new written-piece screen for rows that are not a grid), with progress told as "Front panel · Row 42 of 77 · 3 of 8 pieces".

**Architecture:** Three new format documents land first, in the Python reference and in conformance fixtures: the written-rows document (schema 1), the pattern manifest schema 2 (`pieces`, `assembly`) and the progress document schema 2. `GraphghanCore` reads all three: `RowsDocument` and `WrittenSequence` walk a written piece row by row, `PatternBundle` reads a pieced bundle, `ProjectPace` summarises a pieced project. In the app, a pieced `Project` keeps one `PieceProgress` per started piece copy and mirrors the **current** piece into its existing `chartID`/cursor fields, so every chart-piece path (Work screen, Live Activity, intents, summaries) keeps working unchanged; only a written current piece takes new paths. Written-rows documents are stored content-addressed in a `RowsLibrary`, as charts are in `ChartLibrary`.

**Tech Stack:** Python 3 (uv, pytest, jsonschema), Swift 6 / Swift Testing (`GraphghanCore`, the iOS app), SwiftData, SwiftUI, App Intents, xcodebuild on the iPhone 17 simulator.

**Spec:** `docs/superpowers/specs/2026-09-25-pieces-and-shaped-rows-design.md` — this plan is §8's PR 2 ("Pieces"): §5.2, §5.3, §5.4, §5.5 (bundle half), §6.1, §6.2, §6.4, §6.5, §9's pieces fixtures. PR 1 (#221, chart schema 3) is merged. The importer (§7) is PR 3 and is **not** in this plan.

## Global Constraints

- Every existing chart, bundle, fixture and project reads unchanged: a manifest without `pieces` is one piece, the default chart (spec §5.3); "Progress schema 1 stays valid for a single-chart project" (spec §5.4); "A single-chart project is unchanged: `currentPiece` nil, its existing cursor fields the only piece" (spec §6.1). No existing test's expected value changes; additive entries to fixture enumerations are fine.
- "Writers write schema 1 when there are no pieces, so every site pattern and committed bundle is unchanged" (spec §5.3). The Python writes no pieced pattern outside fixture generators (#214).
- Written-rows `id` is `"sha256:" + hex(sha256(canonical))` over `{"rows": [each entry's from, to, text, count, code, repeat]}` with the chart id's serialisation rules (sorted keys, no whitespace, non-ASCII kept); an absent optional key is left out of its entry, never written as null (spec §5.2, ruled here).
- "`from`/`to` tile 1..N in order with no gap and no overlap … The **last** entry may be open-ended: `"repeat": "until desired length"` … and no `to`. Only the last." (spec §5.2).
- "A pass is one row: an entry from 27 to 86 is 60 passes, each labelled `R 27 - 86 (k of 60)`" (spec §5.2).
- A written piece's cursor is `{row, run: 0}`, `stitch` never written; "Done on its last row finishes it"; events keep schema 1's shape plus `piece` and `copy`, "always with `run: 0`" on a written piece (spec §5.4).
- "No project percent (§3.4)"; `percent` shown in lists, intents and the Live Activity is the current piece's (spec §6.5).
- Additive SwiftData only: new `@Model` types and defaulted fields, no `VersionedSchema` (spec §6.1).
- A bundle "never carries the source PDF"; assembly pages read "page 15 of the original PDF" where the PDF is absent — in this PR it is always absent (keeping the PDF is PR 3) (spec §5.5).
- Deployment target iOS 17; CI runs Xcode 26.2 while the mini has Xcode 27: no API newer than what neighbouring files use. `Shared/` compiles into the widget too: nothing app-only there.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`; commit with `HK_STASH=none git commit …` if the hk pre-commit stash fails on a partial commit.
- App tests: from `ios/`, `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -collect-test-diagnostics never -only-testing:GraphghanTests/<Suite>`; whole suite `mise run test` (~2 min). New Swift files in the app or its tests need `mise run generate` (XcodeGen; `ios/*.xcodeproj` is gitignored). A missing snapshot reference is recorded and fails once by design; never use record mode. "iPhone 17 B" is a second simulator for a parallel run.

## Review Focus

1. **A written piece's last row, then Back.** Done on the last row finishes the piece; Back from there must un-finish it and stay on the last row, not skip a row. Pinned in Task 5 (`WrittenEngineTests.backAfterFinishingStaysOnTheLastRow`) and Task 8 (`ProjectServicePiecesTests.backUnfinishesAPiece`).
2. **Switching pieces mid-row.** Leaving the front panel at row 42 run 3 for the side panel, then coming back, must land on row 42 run 3 — never the side panel's row. Pinned in Task 8 (`ProjectServicePiecesTests.eachPieceKeepsItsOwnCursor`).
3. **An open-ended piece has no total anywhere.** No "of N", no percent, no progress bar, no estimated finish — in the project screen, the Projects row, Shortcuts and the Work screen. Pinned in Task 5 (`WrittenSequenceTests.openEndedHasNoTotal`), Task 8 (`progressLineForAnOpenPiece`), Task 10 (`written-work-open` snapshot).
4. **Opening an old single-chart project after the update.** It must look and behave exactly as before: no piece list, same row line, same Live Activity. Pinned in Task 7 (`ProjectModelTests.aProjectWithoutPiecesIsUnchanged`) and Task 11 (`snapshotOfASingleChartProjectIsUnchanged`).
5. **A bundle whose rows file does not match its `rows_id`, or names a chart it doesn't carry.** Refused with a sentence, nothing half-saved. Pinned in Task 6 (`PatternBundleTests.aRowsFileWithTheWrongIDIsRefused`, `aPieceNamingAMissingChartIsRefused`).

---

### Task 1: Python — the written-rows document

**Files:**
- Create: `src/graphghan/rowsdoc.py`, `schema/rows.schema.json`, `tests/test_rowsdoc.py`

**Interfaces:**
- Produces:
  - `rowsdoc.rows_id(entries: list[dict]) -> str`
  - `rowsdoc.validate_rows_document(doc: dict) -> list[str]`
  - `rowsdoc.total_rows(doc: dict) -> int | None` (None when open-ended)
  - `rowsdoc.total_stitches(doc: dict) -> int | None` (None unless closed and every entry has `count`)
  - `rowsdoc.stitches_before(doc: dict, row: int) -> int | None` (stitches in rows `1 .. row-1`; None unless every entry has `count`)
  - `rowsdoc.pass_at(doc: dict, row: int) -> dict | None` → `{"label", "text", "count", "code", "entry"}`; None beyond a closed end or below 1
  - `ROWS_SCHEMA = 1`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_rowsdoc.py`:

```python
import json
from pathlib import Path

from jsonschema import Draft202012Validator

from graphghan import rowsdoc

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "schema" / "rows.schema.json").read_text(encoding="utf-8"))

ENTRIES = [
    {"label": "R 1", "from": 1, "to": 1, "code": "A", "count": 6, "text": "(Black) ch 7, 6 sc [6]"},
    {"label": "R 2 - R 26", "from": 2, "to": 26, "count": 6, "text": "ch 1, turn, 6 sc [6]"},
    {"label": "R 27 - 86", "from": 27, "to": 86, "code": "B", "count": 6, "text": "(White) ch 1, turn, 6 sc [6]"},
]


def doc(entries=None, **extra):
    entries = entries if entries is not None else [dict(e) for e in ENTRIES]
    d = {
        "schema": 1,
        "id": rowsdoc.rows_id(entries),
        "piece": {"title": "Side panel"},
        "palette": [{"code": "A", "name": "Black", "hex": "#201b18"}, {"code": "B", "name": "White", "hex": "#ffffff"}],
        "rows": entries,
    }
    d.update(extra)
    return d


def test_a_closed_document_validates():
    assert rowsdoc.validate_rows_document(doc()) == []
    assert Draft202012Validator(SCHEMA).is_valid(doc())


def test_id_leaves_out_titles_and_absent_keys():
    a = doc()
    b = doc(piece={"title": "Something else"}, notes=[{"title": "", "text": "x"}])
    assert a["id"] == b["id"]
    # an absent key is left out, never null: the same entry with "code": None is a different id
    withnull = [dict(ENTRIES[1], code=None)]
    assert rowsdoc.rows_id([ENTRIES[1]]) != rowsdoc.rows_id(withnull)


def test_totals():
    assert rowsdoc.total_rows(doc()) == 86
    assert rowsdoc.total_stitches(doc()) == 86 * 6
    assert rowsdoc.stitches_before(doc(), 27) == 26 * 6


def test_pass_labels_count_within_a_range():
    d = doc()
    assert rowsdoc.pass_at(d, 1) == {"label": "R 1", "text": "(Black) ch 7, 6 sc [6]", "count": 6, "code": "A", "entry": 0}
    assert rowsdoc.pass_at(d, 31)["label"] == "R 27 - 86 (5 of 60)"
    assert rowsdoc.pass_at(d, 87) is None and rowsdoc.pass_at(d, 0) is None


def test_open_ended_last_entry():
    entries = [
        {"label": "1.", "from": 1, "to": 1, "count": 6, "text": "ch 7, 6 sc"},
        {"label": "3.", "from": 2, "repeat": "until desired length", "count": 6, "text": "ch 1, turn, 6 sc"},
    ]
    d = doc(entries)
    assert rowsdoc.validate_rows_document(d) == []
    assert rowsdoc.total_rows(d) is None and rowsdoc.total_stitches(d) is None
    assert rowsdoc.pass_at(d, 57)["label"] == "3. (56)"


def test_a_gap_is_refused_by_row_number():
    entries = [dict(ENTRIES[0]), dict(ENTRIES[2])]
    problems = rowsdoc.validate_rows_document(doc(entries))
    assert any("row 2" in p for p in problems), problems


def test_an_open_entry_that_is_not_last_is_refused():
    entries = [dict(ENTRIES[0], to=None, repeat="until desired length"), dict(ENTRIES[1])]
    entries[0].pop("to")
    assert any("only the last" in p for p in rowsdoc.validate_rows_document(doc(entries)))


def test_an_entry_without_to_or_repeat_is_refused():
    entries = [dict(ENTRIES[0])]
    entries[0].pop("to")
    assert any("no `to`" in p for p in rowsdoc.validate_rows_document(doc(entries)))


def test_an_unknown_code_is_refused():
    entries = [dict(ENTRIES[0], code="Z")]
    assert any("'Z'" in p for p in rowsdoc.validate_rows_document(doc(entries)))


def test_a_wrong_id_is_refused():
    d = doc()
    d["id"] = "sha256:" + "0" * 64
    assert any("id" in p for p in rowsdoc.validate_rows_document(d))


def test_counts_are_optional_and_withhold_stitches():
    entries = [dict(ENTRIES[0]), dict(ENTRIES[1])]
    entries[1].pop("count")
    d = doc(entries)
    assert rowsdoc.validate_rows_document(d) == []
    assert rowsdoc.total_stitches(d) is None and rowsdoc.stitches_before(d, 3) is None
```

- [ ] **Step 2: Run to verify it fails**

Run: `uv run pytest tests/test_rowsdoc.py -q`
Expected: FAIL — `ImportError: cannot import name 'rowsdoc'` (and the schema file is missing).

- [ ] **Step 3: Implement**

Create `src/graphghan/rowsdoc.py`:

```python
"""Written-rows documents, schema 1: a piece that is not a grid (spec 2026-09-25 §5.2).

Each entry is one printed line: rows `from`..`to` share its text; the last may be open-ended
("repeat until desired length"). Plain dicts in, plain dicts out, like chartdoc.
"""

from __future__ import annotations

import hashlib
import json

from .chartdoc import CODE_RE

ROWS_SCHEMA = 1
_ID_KEYS = ("from", "to", "text", "count", "code", "repeat")


def _canonical(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def rows_id(entries: list[dict]) -> str:
    """The document's id: its rows, not its titles. An absent key stays absent, never null."""
    rows = [{k: e[k] for k in _ID_KEYS if k in e} for e in entries]
    return "sha256:" + hashlib.sha256(_canonical({"rows": rows})).hexdigest()


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def validate_rows_document(doc: dict) -> list[str]:
    """What the JSON Schema cannot say: the rows tile 1..N, only the last is open, codes exist, the id."""
    problems: list[str] = []
    if doc.get("schema") != ROWS_SCHEMA:
        problems.append(f"schema {doc.get('schema')!r} is not {ROWS_SCHEMA}")
    entries = doc.get("rows")
    if not isinstance(entries, list) or not entries:
        return problems + ["rows is empty"]
    codes = {p.get("code") for p in doc.get("palette") or [] if isinstance(p, dict)}
    expected = 1
    for i, e in enumerate(entries):
        if not isinstance(e, dict):
            problems.append(f"rows[{i}] is not an object")
            return problems
        start, end = e.get("from"), e.get("to")
        if not _is_int(start) or start != expected:
            problems.append(f"rows[{i}] starts at {start!r}; row {expected} is missing or printed twice")
            return problems
        if end is None:
            if "repeat" not in e:
                problems.append(f"rows[{i}] has no `to` and no `repeat`")
            elif i != len(entries) - 1:
                problems.append(f"rows[{i}] is open-ended; only the last entry may be")
            expected = None
        elif not _is_int(end) or end < start:
            problems.append(f"rows[{i}].to {end!r} is before its `from` {start}")
            return problems
        else:
            expected = end + 1
        if "count" in e and (not _is_int(e["count"]) or e["count"] < 1):
            problems.append(f"rows[{i}].count {e['count']!r} is not a positive integer")
        if "code" in e and (not isinstance(e["code"], str) or not CODE_RE.match(e["code"]) or e["code"] not in codes):
            problems.append(f"rows[{i}] uses code {e.get('code')!r}, which is not in the palette")
        if expected is None:
            break
    if doc.get("id") != rows_id(entries):
        problems.append(f"id {doc.get('id')!r} does not match the rows ({rows_id(entries)})")
    return problems


def total_rows(doc: dict) -> int | None:
    last = doc["rows"][-1]
    return last.get("to")


def _all_counted(doc: dict) -> bool:
    return all("count" in e for e in doc["rows"])


def total_stitches(doc: dict) -> int | None:
    if total_rows(doc) is None or not _all_counted(doc):
        return None
    return sum(e["count"] * (e["to"] - e["from"] + 1) for e in doc["rows"])


def stitches_before(doc: dict, row: int) -> int | None:
    """Stitches in rows 1 .. row-1, when every entry states its count."""
    if not _all_counted(doc):
        return None
    total = 0
    for e in doc["rows"]:
        last = e.get("to", row - 1)
        n = max(0, min(last, row - 1) - e["from"] + 1)
        total += n * e["count"]
    return total


def pass_at(doc: dict, row: int) -> dict | None:
    """Row `row` as the Work screen shows it: the entry's text, labelled with its place in a range."""
    if row < 1:
        return None
    for i, e in enumerate(doc["rows"]):
        end = e.get("to")
        if row < e["from"] or (end is not None and row > end):
            continue
        k = row - e["from"] + 1
        if end is None:
            label = f"{e['label']} ({k})"
        elif end == e["from"]:
            label = e["label"]
        else:
            label = f"{e['label']} ({k} of {end - e['from'] + 1})"
        return {"label": label, "text": e["text"], "count": e.get("count"), "code": e.get("code"), "entry": i}
    return None
```

Create `schema/rows.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://graphghan.milo.cat/schema/rows.schema.json",
  "title": "Graphghan written-rows document, schema 1",
  "description": "A piece worked from written rows, not a grid. See docs/chart-format.md §Written-rows document.",
  "type": "object",
  "required": ["schema", "id", "piece", "rows"],
  "properties": {
    "schema": { "const": 1 },
    "id": { "type": "string", "pattern": "^sha256:[0-9a-f]{64}$" },
    "piece": { "type": "object", "required": ["title"], "properties": { "title": { "type": "string" } } },
    "palette": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["code", "name", "hex"],
        "properties": {
          "code": { "type": "string", "pattern": "^[A-Za-z]{1,3}$" },
          "name": { "type": "string" },
          "hex": { "type": "string", "pattern": "^#[0-9A-Fa-f]{6}$" }
        }
      }
    },
    "rows": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["label", "from", "text"],
        "properties": {
          "label": { "type": "string" },
          "from": { "type": "integer", "minimum": 1 },
          "to": { "type": "integer", "minimum": 1 },
          "text": { "type": "string" },
          "count": { "type": "integer", "minimum": 1 },
          "code": { "type": "string", "pattern": "^[A-Za-z]{1,3}$" },
          "repeat": { "type": "string", "minLength": 1 }
        }
      }
    },
    "source": { "type": "object", "properties": { "pages": { "type": "array", "items": { "type": "integer", "minimum": 1 } } } },
    "notes": {
      "type": "array",
      "items": { "type": "object", "required": ["title", "text"], "properties": { "title": { "type": "string" }, "text": { "type": "string" } } }
    }
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `uv run pytest tests/test_rowsdoc.py -q` → PASS; then `uv run pytest -q` → all pass.

- [ ] **Step 5: Commit**

```bash
git add src/graphghan/rowsdoc.py schema/rows.schema.json tests/test_rowsdoc.py
git commit -m "format: the written-rows document, schema 1 (#206)"
```

---

### Task 2: Python — manifest schema 2 and progress schema 2

**Files:**
- Create: `src/graphghan/manifestdoc.py`, `schema/manifest.schema.json`, `tests/test_manifestdoc.py`, `tests/test_progress_project.py`
- Modify: `src/graphghan/progress.py`, `schema/progress.schema.json`

**Interfaces:**
- Consumes: Task 1's `rowsdoc.total_rows`, `total_stitches`, `stitches_before`; `chartdoc.sequence`, `chartdoc.cell_kind`; `progress.cells_before`, `progress.total_cells`.
- Produces:
  - `manifestdoc.validate_manifest(doc: dict) -> list[str]`
  - `manifestdoc.pieces(doc: dict) -> list[dict]` — each `{"id", "title", "make", "chart" | "rows", "rows_id"?, "pages"}`; for a manifest without `pieces`, one piece `{"id": "chart", "title": <pattern title>, "make": 1, "chart": <default chart id>, "pages": []}`
  - `progress.summarize_project(doc: dict, manifest: dict, docs: dict[str, dict], gap_seconds=GAP_SECONDS) -> dict` where `docs` maps a chart id or rows id to that chart or rows document
  - `schema/progress.schema.json` accepts schema 1 (unchanged) or schema 2

- [ ] **Step 1: Write the failing tests**

Create `tests/test_manifestdoc.py`:

```python
import json
from pathlib import Path

from jsonschema import Draft202012Validator

from graphghan import manifestdoc

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "schema" / "manifest.schema.json").read_text(encoding="utf-8"))
CHART = "sha256:" + "a" * 64
ROWS = "sha256:" + "b" * 64


def chart_entry(default=True):
    return {"id": CHART, "variant": "final", "gauge_key": "sc", "default": default, "path": "charts/final-sc/chart.json",
            "preview": "charts/final-sc/preview.png", "width": 7, "height": 5, "stitch": "sc", "colors": 2,
            "stitches": 24, "changes_per_row": {"mean": 0.8, "max": 2}, "yards_est": 1}


def manifest(**extra):
    m = {"schema": 2, "id": "bag", "title": "Bag", "version": "0.1.0", "dedication": "", "quote": "", "author": "",
         "license": "", "preview": "preview.png", "palette": [], "charts": [chart_entry()],
         "pieces": [{"id": "panel", "title": "Panel", "make": 1, "chart": CHART, "pages": [9]},
                    {"id": "strip", "title": "Strip", "make": 2, "rows": "pieces/strip.rows.json", "rows_id": ROWS}],
         "assembly": [{"title": "Sew up", "pages": [3]}], "updated": "1980-01-01T00:00:00Z"}
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
```

Create `tests/test_progress_project.py` (the fixture-level expectation is Task 4's; these are the unit rules):

```python
from graphghan import progress, rowsdoc

ROWS = [
    {"label": "R 1", "from": 1, "to": 1, "count": 6, "text": "a"},
    {"label": "R 2 - R 4", "from": 2, "to": 4, "count": 6, "text": "b"},
]
RDOC = {"schema": 1, "id": rowsdoc.rows_id(ROWS), "piece": {"title": "Strip"}, "rows": ROWS}
MANIFEST = {"schema": 2, "id": "bag", "title": "Bag", "version": "1", "charts": [],
            "pieces": [{"id": "strip", "title": "Strip", "make": 2, "rows": "pieces/strip.rows.json", "rows_id": RDOC["id"]}],
            "assembly": [{"title": "Sew up"}]}


def doc(pieces, events, assembly_done=()):
    return {"schema": 2, "pattern_id": "bag", "pieces": pieces, "current": {"piece": "strip", "copy": 1},
            "assembly_done": list(assembly_done), "events": events}


def ev(t, row, kind="advance", piece="strip", copy=1):
    return {"t": t, "piece": piece, "copy": copy, "row": row, "run": 0, "kind": kind}


def test_a_written_piece_counts_rows_done_before_the_cursor():
    d = doc([{"piece": "strip", "copy": 1, "doc_id": RDOC["id"], "cursor": {"row": 3, "run": 0}, "finished": None}], [])
    s = progress.summarize_project(d, MANIFEST, {RDOC["id"]: RDOC})
    assert s["pieces"][0] == {"piece": "strip", "copy": 1, "kind": "rows", "rows_done": 2, "total_rows": 4,
                              "percent": 50.0, "stitches_done": 12, "total_stitches": 24, "finished": False}
    assert (s["pieces_done"], s["pieces_total"], s["assembly_done"], s["assembly_total"]) == (0, 2, 0, 1)


def test_the_finishing_advance_counts_the_last_row():
    events = [ev("2026-09-12T18:00:00Z", 2), ev("2026-09-12T18:01:00Z", 4, "jump"), ev("2026-09-12T18:02:00Z", 4)]
    d = doc([{"piece": "strip", "copy": 1, "doc_id": RDOC["id"], "cursor": {"row": 4, "run": 0},
              "finished": "2026-09-12T18:02:00Z"}], events)
    s = progress.summarize_project(d, MANIFEST, {RDOC["id"]: RDOC})
    assert s["pieces"][0]["rows_done"] == 4 and s["pieces"][0]["finished"] is True
    assert s["sessions"] == [{"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:02:00Z", "cells": 0, "rows": 4}]
    assert s["pieces_done"] == 1
    assert s["stitches_per_hour"] is None  # written rows get no pace figure
```

- [ ] **Step 2: Run to verify they fail**

Run: `uv run pytest tests/test_manifestdoc.py tests/test_progress_project.py -q`
Expected: FAIL — `ImportError: cannot import name 'manifestdoc'`; `AttributeError: module 'graphghan.progress' has no attribute 'summarize_project'`.

- [ ] **Step 3: Implement `manifestdoc`**

Create `src/graphghan/manifestdoc.py`:

```python
"""Pattern manifests, schemas 1 and 2 (spec 2026-09-25 §5.3). Schema 2 adds `pieces` and
`assembly`; a manifest without `pieces` is one piece, its default chart."""

from __future__ import annotations

import re

SLUG_RE = re.compile(r"^[a-z0-9-]+$")


def _default_chart(doc: dict) -> dict | None:
    charts = doc.get("charts") or []
    return next((c for c in charts if c.get("default")), charts[0] if charts else None)


def pieces(doc: dict) -> list[dict]:
    """The pieces in the pattern's order, `make` defaulted; one implicit piece for schema 1."""
    if "pieces" not in doc:
        chart = _default_chart(doc)
        return [{"id": "chart", "title": doc.get("title", ""), "make": 1, "chart": chart["id"] if chart else None, "pages": []}]
    out = []
    for p in doc["pieces"]:
        q = {"id": p["id"], "title": p["title"], "make": p.get("make", 1), "pages": p.get("pages", [])}
        if "chart" in p:
            q["chart"] = p["chart"]
        if "rows" in p:
            q["rows"] = p["rows"]
            q["rows_id"] = p.get("rows_id")
        out.append(q)
    return out


def validate_manifest(doc: dict) -> list[str]:
    problems: list[str] = []
    schema = doc.get("schema")
    charts = doc.get("charts") or []
    chart_ids = [c.get("id") for c in charts]
    defaults = [c for c in charts if c.get("default")]
    if charts and len(defaults) != 1:
        problems.append(f"charts has {len(defaults)} default entries; exactly one must be the default")
    if "pieces" not in doc:
        if schema not in (1, 2):
            problems.append(f"schema {schema!r} is not 1 or 2")
        return problems
    if schema != 2:
        problems.append(f"pieces needs schema 2, not {schema!r}")
    ps = doc["pieces"]
    if not isinstance(ps, list) or not ps:
        return problems + ["pieces is empty"]
    seen: set[str] = set()
    named: list[str] = []
    for i, p in enumerate(ps):
        pid = p.get("id")
        if not isinstance(pid, str) or not SLUG_RE.match(pid):
            problems.append(f"pieces[{i}].id {pid!r} is not a slug")
        elif pid in seen:
            problems.append(f"pieces[{i}].id {pid!r} is a duplicate")
        seen.add(pid if isinstance(pid, str) else "")
        make = p.get("make", 1)
        if not isinstance(make, int) or isinstance(make, bool) or make < 1:
            problems.append(f"pieces[{i}].make {make!r} is not an integer >= 1")
        has_chart, has_rows = "chart" in p, "rows" in p
        if has_chart == has_rows:
            problems.append(f"pieces[{i}] must name exactly one of `chart` and `rows`")
        elif has_chart:
            if p["chart"] not in chart_ids:
                problems.append(f"pieces[{i}] names a chart {p['chart']!r} that is not in `charts`")
            named.append(p["chart"])
        elif not isinstance(p.get("rows_id"), str):
            problems.append(f"pieces[{i}] has `rows` but no `rows_id`")
    for c in chart_ids:
        if c not in named:
            problems.append(f"charts lists {c!r}, which no piece names")
    if len(named) != len(set(named)):
        problems.append("two pieces name the same chart; a pieced manifest lists each chart once")
    if defaults and named and defaults[0].get("id") != named[0]:
        problems.append("the default chart must be the first chart piece's chart")
    for i, step in enumerate(doc.get("assembly") or []):
        if not isinstance(step, dict) or not isinstance(step.get("title"), str):
            problems.append(f"assembly[{i}] has no title")
    return problems
```

(`"make"` appears in the refusal needle for `make 0`; `"default"` for the missing default; keep those words in the messages.)

- [ ] **Step 4: Implement `summarize_project`**

Append to `src/graphghan/progress.py` (and add `from . import chartdoc, manifestdoc, rowsdoc` at the top, below the existing imports):

```python
def _key(obj: dict) -> tuple[str, int]:
    return (obj["piece"], obj.get("copy", 1))


def _rows_done(row: int, finished: bool, total: int | None) -> int:
    """Rows worked at a written cursor: the rows before it, or all of them once finished."""
    if finished:
        return total if total is not None else row
    return row - 1


def summarize_project(doc: dict, manifest: dict, docs: dict[str, dict], gap_seconds: int = GAP_SECONDS) -> dict:
    """Progress schema 2 (spec 2026-09-25 §5.4): each started piece copy, the project counts, and
    sessions over every event. `docs` maps a chart id or rows id to that document."""
    by_id = {p["id"]: p for p in manifestdoc.pieces(manifest)}

    def piece_model(pid: str) -> dict:
        p = by_id[pid]
        if "chart" in p:
            chart = docs[p["chart"]]
            return {"kind": "chart", "passes": chartdoc.sequence(chart), "cell": chartdoc.cell_kind(chart)}
        return {"kind": "rows", "doc": docs[p["rows_id"]]}

    models = {pid: piece_model(pid) for pid in {e["piece"] for e in doc["pieces"]}}
    out_pieces = []
    for entry in doc["pieces"]:
        m = models[entry["piece"]]
        finished = entry.get("finished") is not None
        cur = entry["cursor"]
        row = {"piece": entry["piece"], "copy": entry.get("copy", 1), "kind": m["kind"], "finished": finished}
        if m["kind"] == "chart":
            total = total_cells(m["passes"])
            done = cells_before(m["passes"], cur["row"], cur["run"], cur.get("stitch", 0))
            row.update({"percent": round(100.0 * done / total, 1) if total else 0.0, "cells_done": done, "total_cells": total})
            if m["cell"] == "stitch":
                row.update({"stitches_done": done, "total_stitches": total})
        else:
            rd = m["doc"]
            total = rowsdoc.total_rows(rd)
            done = _rows_done(cur["row"], finished, total)
            row["rows_done"] = done
            if total is not None:
                row["total_rows"] = total
                row["percent"] = round(100.0 * done / total, 1) if total else 0.0
            st_total = rowsdoc.total_stitches(rd)
            if st_total is not None:
                row["total_stitches"] = st_total
                row["stitches_done"] = st_total if finished else rowsdoc.stitches_before(rd, cur["row"])
        out_pieces.append(row)

    # Sessions: every event, split by time; each piece's worked amount across the session.
    events = sorted(doc.get("events") or [], key=lambda e: _parse(e["t"]))
    last: dict[tuple[str, int], tuple[int, int, int]] = {}
    sessions, current, prev_t = [], None, None
    for e in events:
        t = _parse(e["t"])
        if current is None or (t - prev_t).total_seconds() > gap_seconds:
            if current is not None:
                sessions.append(current)
            current = {"start": t, "end": t, "from": {}, "to": {}, "finishing": {}}
        k = _key(e)
        before = last.get(k, (1, 0, 0))
        current["from"].setdefault(k, before)
        cursor = (e["row"], e["run"], e.get("stitch", 0))
        # An advance that leaves a written piece's row unchanged is the one that finished it.
        current["finishing"][k] = e["kind"] == "advance" and cursor[0] == before[0] and models[e["piece"]]["kind"] == "rows"
        current["to"][k] = cursor
        current["end"] = t
        last[k] = cursor
        prev_t = t
    if current is not None:
        sessions.append(current)

    out_sessions, active, chart_active, chart_stitches = [], 0, 0, 0
    for s in sessions:
        cells = rows = 0
        touched_chart = False
        for k, start in s["from"].items():
            end = s["to"][k]
            m = models[k[0]]
            if m["kind"] == "chart":
                touched_chart = True
                n = max(0, cells_before(m["passes"], *end) - cells_before(m["passes"], *start))
                cells += n
                if m["cell"] == "stitch":
                    chart_stitches += n
            else:
                total = rowsdoc.total_rows(m["doc"])
                after = _rows_done(end[0], s["finishing"][k], total)
                rows += max(0, after - _rows_done(start[0], False, total))
        secs = int((s["end"] - s["start"]).total_seconds())
        active += secs
        if touched_chart:
            chart_active += secs
        out_sessions.append({"start": _fmt(s["start"]), "end": _fmt(s["end"]), "cells": cells, "rows": rows})

    return {
        "pieces": out_pieces,
        "pieces_done": sum(1 for p in out_pieces if p["finished"]),
        "pieces_total": sum(p["make"] for p in by_id.values()),
        "assembly_done": len(doc.get("assembly_done") or []),
        "assembly_total": len(manifest.get("assembly") or []),
        "sessions": out_sessions,
        "active_seconds": active,
        # Chart stitches only, over the time of the sessions that worked a chart (ruled in the plan).
        "stitches_per_hour": round(chart_stitches / (chart_active / 3600.0), 1) if chart_active else None,
    }
```

Update the module docstring's first line to `"""Progress documents (schemas 1 and 2): cursor math, sessions, and pace. Pure functions over passes."""`.

Import-cycle check: `chartdoc` imports nothing from `progress`; `manifestdoc` and `rowsdoc` import only `chartdoc`. If `progress` is imported by `chartdoc` anywhere (it is not today), move the new imports inside `summarize_project`.

- [ ] **Step 5: Implement the schemas**

Create `schema/manifest.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://graphghan.milo.cat/schema/manifest.schema.json",
  "title": "Graphghan pattern manifest, schema 1 or 2",
  "description": "patterns/<id>/pattern.json and a bundle's root. Schema 2 adds pieces and assembly. See docs/chart-format.md §Pattern manifest.",
  "type": "object",
  "required": ["schema", "id", "title", "version", "charts"],
  "properties": {
    "schema": { "enum": [1, 2] },
    "id": { "type": "string", "pattern": "^[a-z0-9-]+$" },
    "title": { "type": "string", "minLength": 1 },
    "version": { "type": "string" },
    "preview": { "type": "string" },
    "charts": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "variant", "gauge_key", "default", "path", "preview", "width", "height"],
        "properties": {
          "id": { "type": "string", "pattern": "^sha256:[0-9a-f]{64}$" },
          "default": { "type": "boolean" },
          "path": { "type": "string" },
          "preview": { "type": "string" }
        }
      }
    },
    "pieces": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["id", "title"],
        "properties": {
          "id": { "type": "string", "pattern": "^[a-z0-9-]+$" },
          "title": { "type": "string", "minLength": 1 },
          "make": { "type": "integer", "minimum": 1 },
          "chart": { "type": "string", "pattern": "^sha256:[0-9a-f]{64}$" },
          "rows": { "type": "string" },
          "rows_id": { "type": "string", "pattern": "^sha256:[0-9a-f]{64}$" },
          "pages": { "type": "array", "items": { "type": "integer", "minimum": 1 } }
        },
        "oneOf": [ { "required": ["chart"] }, { "required": ["rows", "rows_id"] } ]
      }
    },
    "assembly": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["title"],
        "properties": {
          "title": { "type": "string" },
          "text": { "type": "string" },
          "pages": { "type": "array", "items": { "type": "integer", "minimum": 1 } }
        }
      }
    }
  }
}
```

Replace `schema/progress.schema.json` so schema 1 is exactly as today and schema 2 is added: move today's body into `$defs.v1` (keep its `required`, `properties` and `schema: {"const": 1}`), add `$defs.v2`, and make the root `{"oneOf": [{"$ref": "#/$defs/v1"}, {"$ref": "#/$defs/v2"}]}` with the same `$schema`, `$id`, and `"title": "Graphghan progress document, schema 1 or 2"`. `$defs.v2`:

```json
{
  "type": "object",
  "required": ["schema", "pattern_id", "pieces", "events"],
  "properties": {
    "schema": { "const": 2 },
    "pattern_id": { "type": "string", "pattern": "^[a-z0-9-]+$" },
    "pattern_version": { "type": "string" },
    "pieces": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["piece", "copy", "doc_id", "cursor"],
        "properties": {
          "piece": { "type": "string" },
          "copy": { "type": "integer", "minimum": 1 },
          "doc_id": { "type": "string", "pattern": "^sha256:[0-9a-f]{64}$" },
          "cursor": { "$ref": "#/$defs/cursor" },
          "finished": { "type": ["string", "null"], "format": "date-time" }
        }
      }
    },
    "current": { "type": "object", "required": ["piece", "copy"], "properties": { "piece": { "type": "string" }, "copy": { "type": "integer", "minimum": 1 } } },
    "assembly_done": { "type": "array", "items": { "type": "integer", "minimum": 0 } },
    "started": { "type": "string", "format": "date-time" },
    "finished": { "type": ["string", "null"], "format": "date-time" },
    "events": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["t", "piece", "copy", "row", "run", "kind"],
        "properties": {
          "t": { "type": "string", "format": "date-time" },
          "piece": { "type": "string" },
          "copy": { "type": "integer", "minimum": 1 },
          "row": { "type": "integer", "minimum": 1 },
          "run": { "type": "integer", "minimum": 0 },
          "stitch": { "type": "integer", "minimum": 0 },
          "kind": { "enum": ["advance", "back", "jump"] }
        }
      }
    }
  }
}
```

(The shared `$defs.cursor` stays where it is.)

- [ ] **Step 6: Run to verify**

Run: `uv run pytest tests/test_manifestdoc.py tests/test_progress_project.py tests/test_conformance.py -q` → PASS (the conformance suite proves every schema-1 progress fixture still validates); then `uv run pytest -q`.

- [ ] **Step 7: Commit**

```bash
git add src/graphghan/manifestdoc.py src/graphghan/progress.py schema/manifest.schema.json schema/progress.schema.json tests/test_manifestdoc.py tests/test_progress_project.py
git commit -m "format: manifest schema 2 (pieces, assembly) and progress schema 2 (#206)"
```

---

### Task 3: Conformance fixtures, a pieced bundle, and the format doc

**Files:**
- Modify: `fixtures/chart-format/generate.py`, `fixtures/chart-format/README.md`, `tests/test_conformance.py`, `fixtures/bundle/generate.py`, `fixtures/bundle/README.md`, `tests/test_bundle_fixtures.py`, `src/graphghan/bundle.py`, `docs/chart-format.md`
- Create (generated): `fixtures/chart-format/pieces-basic/` (`pattern.json`, `charts/final-sc/chart.json`, `pieces/strip.rows.json`, `pieces/fin.rows.json`, `pieces/strap.rows.json`, `progress.json`, `progress.expected.json`), three refusal files in `fixtures/chart-format/refused/`, `fixtures/bundle/pieces-basic.graphghan`
- Create (committed once, not regenerated): `fixtures/chart-format/pieces-basic/preview.png`, `fixtures/chart-format/pieces-basic/charts/final-sc/preview.png`

**Interfaces:**
- Consumes: Tasks 1–2; `shaped_basic_chart()` in the chart-format generator (PR 1).
- Produces: the fixture tree Task 5/6 read from Swift; `bundle.zip_files(files: dict[str, bytes]) -> bytes` (the stored, dated zip `to_bundle` already writes, factored out).

The fixture's pieces, in order: `panel` — the shaped-basic chart (chart piece); `strip` — rows, closed, a range, every count; `fin` — rows, closed, `make: 2`, one entry without a count; `strap` — rows, open-ended. Assembly has two steps.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_conformance.py`:

```python
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


def test_refused_manifest_naming_a_missing_chart():
    m = json.loads((FIX / "refused" / "piece-names-missing-chart.pattern.json").read_text(encoding="utf-8"))
    assert Draft202012Validator(MANIFEST_SCHEMA).is_valid(m)
    assert any("not in `charts`" in p for p in manifestdoc.validate_manifest(m))
```

Add `manifestdoc, rowsdoc` to the file's `from graphghan import ...` line. Extend the existing refused-set test (added in PR 1) additively so the refused directory's expected names include `rows-gap.rows.json`, `rows-open-not-last.rows.json` and `piece-names-missing-chart.pattern.json` alongside the five `*.chart.json` files (keep the chart files' own name test as it is; if it globs `*.chart.json` only, add a separate assertion for the full directory listing). Extend `test_fixtures_are_fresh` so it compares the `pieces-basic/` tree byte for byte too, **excluding the two `preview.png` files** (they are committed once, not generated).

In `tests/test_bundle_fixtures.py`, append:

```python
from generate import pieced_bundles  # noqa: E402


def test_the_pieced_bundle_matches_its_fixture_tree():
    for name, data in pieced_bundles(ROOT).items():
        fixture = FIX / name
        assert fixture.exists(), f"missing {name}; run uv run python fixtures/bundle/generate.py"
        assert fixture.read_bytes() == data, f"{name} differs from a fresh build; regenerate it"
```

and change the last line of `test_every_pattern_has_a_matching_bundle_fixture` to `assert {p.name for p in FIX.glob("*.graphghan")} == expected | set(pieced_bundles(ROOT)), "stale bundle fixture with no pattern"` (an additive change to the allowed set).

- [ ] **Step 2: Run to verify they fail**

Run: `uv run pytest tests/test_conformance.py tests/test_bundle_fixtures.py -q`
Expected: FAIL — `FileNotFoundError` for `pieces-basic/pattern.json`; `ImportError: cannot import name 'pieced_bundles'`.

- [ ] **Step 3: Factor the zip writer**

In `src/graphghan/bundle.py`, split `to_bundle`:

```python
def zip_files(files: dict[str, bytes]) -> bytes:
    """A bundle's bytes from its entries: stored, dated 1980-01-01, mode 0644, sorted names."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, date_time=BUNDLE_EPOCH)
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o644 << 16
            info.create_system = 0  # MS-DOS, so the mode above is the only thing that varies
            z.writestr(info, files[name])
    return buf.getvalue()


def to_bundle(pattern_dir: str | Path) -> bytes:
    """The bundle as bytes. Two calls on one pattern give identical output, on any platform."""
    return zip_files(bundle_files(pattern_dir))
```

- [ ] **Step 4: Generate the pieces fixtures**

In `fixtures/chart-format/generate.py` add (after the shaped fixtures; import `rows_id` from `graphghan.rowsdoc` and `finished_size` from `graphghan.chartdoc`):

```python
# The pieces-basic fixture (spec 2026-09-25 §5.2-§5.4, §9): a manifest-2 pattern in Orca's shape
# at toy size. `panel` is the shaped-basic chart; `strip` is written rows with a range and every
# count; `fin` is made twice and one of its entries prints no count; `strap` ends "until desired
# length". The directory is a bundle's tree: fixtures/bundle zips it as it stands.
PIECES_DIR = "pieces-basic"


def rows_doc(title, entries, palette=None, pages=None):
    doc = {"schema": 1, "id": rows_id(entries), "piece": {"title": title}}
    if palette:
        doc["palette"] = palette
    doc["rows"] = entries
    if pages:
        doc["source"] = {"pages": pages}
    return doc


STRIP_ROWS = [
    {"label": "R 1", "from": 1, "to": 1, "code": "A", "count": 6, "text": "(A) ch 7, from the second chain from the hook, 6 sc [6]"},
    {"label": "R 2 - R 4", "from": 2, "to": 4, "count": 6, "text": "ch 1, turn, 6 sc [6]"},
    {"label": "R 5", "from": 5, "to": 5, "code": "B", "count": 6, "text": "(B) ch 1, turn, 6 sc [6]"},
]
FIN_ROWS = [
    {"label": "R 1", "from": 1, "to": 1, "count": 2, "text": "ch 3, from the second chain from the hook, 2 sc [2]"},
    {"label": "R 2 - R 3", "from": 2, "to": 3, "text": "ch 1, turn, 1 inc, 1 sc"},
]
STRAP_ROWS = [
    {"label": "1.", "from": 1, "to": 1, "count": 6, "text": "ch 7, from the second chain from the hook, 6 sc"},
    {"label": "2.", "from": 2, "repeat": "until desired length", "count": 6, "text": "ch 1, turn, 6 sc; repeat until the strap is as long as you want it"},
]
PIECES_PALETTE = [{"code": "A", "name": "Color A", "hex": "#112233"}, {"code": "B", "name": "Color B", "hex": "#ffffff"}]


def pieces_basic() -> dict[str, dict]:
    """relative path -> JSON document, for everything in the pieces-basic tree but the previews."""
    chart = shaped_basic_chart()
    strip = rows_doc("Strip", STRIP_ROWS, PIECES_PALETTE, [3])
    fin = rows_doc("Fin", FIN_ROWS)
    strap = rows_doc("Strap", STRAP_ROWS)
    w, h, unit = finished_size(chart)
    entry = {
        "id": chart["chart"]["id"], "variant": "final", "gauge_key": "sc", "default": True,
        "path": "charts/final-sc/chart.json", "preview": "charts/final-sc/preview.png",
        "width": 7, "height": 5, "size": {"width": w, "height": h, "unit": unit}, "stitch": "sc",
        # Stitched cells and yarn colours only (chart schema 3): the ground is neither.
        "colors": 2, "stitches": 24,
        "changes_per_row": {"mean": chart["stats"]["color_changes_per_row"]["mean"], "max": chart["stats"]["color_changes_per_row"]["max"]},
        "yards_est": int(sum(chart["stats"]["yards_est"].values())),
    }
    manifest = {
        "schema": 2, "id": "pieces-basic", "title": "Pieces basic", "version": "1.0.0", "dedication": "", "quote": "",
        "author": "graphghan fixtures", "license": "MIT", "preview": "preview.png", "palette": PIECES_PALETTE,
        "charts": [entry],
        "pieces": [
            {"id": "panel", "title": "Panel", "make": 1, "chart": entry["id"], "pages": [2]},
            {"id": "strip", "title": "Strip", "make": 1, "rows": "pieces/strip.rows.json", "rows_id": strip["id"], "pages": [3]},
            {"id": "fin", "title": "Fin", "make": 2, "rows": "pieces/fin.rows.json", "rows_id": fin["id"]},
            {"id": "strap", "title": "Strap", "make": 1, "rows": "pieces/strap.rows.json", "rows_id": strap["id"]},
        ],
        "assembly": [
            {"title": "Sew the strip round the panel", "text": "Whip stitch the strip to the panel's edge, right sides out.", "pages": [3]},
            {"title": "Pages 4–5", "pages": [4, 5]},
        ],
        "updated": "1980-01-01T00:00:00Z",
    }
    progress_doc = {
        "schema": 2, "pattern_id": "pieces-basic", "pattern_version": "1.0.0",
        "pieces": [
            {"piece": "panel", "copy": 1, "doc_id": entry["id"], "cursor": {"row": 3, "run": 1}, "finished": None},
            {"piece": "strip", "copy": 1, "doc_id": strip["id"], "cursor": {"row": 5, "run": 0}, "finished": "2026-09-12T19:30:00Z"},
            {"piece": "fin", "copy": 1, "doc_id": fin["id"], "cursor": {"row": 2, "run": 0}, "finished": None},
            {"piece": "strap", "copy": 1, "doc_id": strap["id"], "cursor": {"row": 10, "run": 0}, "finished": None},
        ],
        "current": {"piece": "panel", "copy": 1},
        "assembly_done": [0],
        "started": "2026-09-12T18:00:00Z", "finished": None,
        "events": [
            {"t": "2026-09-12T18:00:00Z", "piece": "panel", "copy": 1, "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T18:05:00Z", "piece": "panel", "copy": 1, "row": 3, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T18:10:00Z", "piece": "panel", "copy": 1, "row": 3, "run": 1, "kind": "advance"},
            {"t": "2026-09-12T19:00:00Z", "piece": "strip", "copy": 1, "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T19:10:00Z", "piece": "strip", "copy": 1, "row": 5, "run": 0, "kind": "jump"},
            {"t": "2026-09-12T19:30:00Z", "piece": "strip", "copy": 1, "row": 5, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T21:00:00Z", "piece": "fin", "copy": 1, "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T21:02:00Z", "piece": "strap", "copy": 1, "row": 10, "run": 0, "kind": "jump"},
        ],
    }
    return {
        "pattern.json": manifest,
        "charts/final-sc/chart.json": chart,
        "pieces/strip.rows.json": strip,
        "pieces/fin.rows.json": fin,
        "pieces/strap.rows.json": strap,
        "progress.json": progress_doc,
        "progress.expected.json": PIECES_EXPECTED,
    }


# Hand-worked from the progress document above (not produced by summarize_project):
# panel 3+5+3 = 11 of 24 cells; strip finished, 5 of 5 rows, 30 stitches; fin row 2 = 1 of 3
# rows, no stitch figures (one entry has no count); strap row 10 = 9 rows, open, no total.
# Sessions: 18:00-18:10 the panel's 11 cells; 19:00-19:30 the strip's 5 rows (the advance at
# 19:30 leaves row 5 unchanged, so it is the finishing advance and row 5 counts); 21:00-21:02 the
# fin's 1 row and the strap's 9. Pace: 11 chart stitches over the 600 s of the session that
# worked a chart.
PIECES_EXPECTED = {
    "pieces": [
        {"piece": "panel", "copy": 1, "kind": "chart", "finished": False, "percent": 45.8, "cells_done": 11,
         "total_cells": 24, "stitches_done": 11, "total_stitches": 24},
        {"piece": "strip", "copy": 1, "kind": "rows", "finished": True, "rows_done": 5, "total_rows": 5,
         "percent": 100.0, "total_stitches": 30, "stitches_done": 30},
        {"piece": "fin", "copy": 1, "kind": "rows", "finished": False, "rows_done": 1, "total_rows": 3, "percent": 33.3},
        {"piece": "strap", "copy": 1, "kind": "rows", "finished": False, "rows_done": 9},
    ],
    "pieces_done": 1,
    "pieces_total": 5,
    "assembly_done": 1,
    "assembly_total": 2,
    "sessions": [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:10:00Z", "cells": 11, "rows": 0},
        {"start": "2026-09-12T19:00:00Z", "end": "2026-09-12T19:30:00Z", "cells": 0, "rows": 5},
        {"start": "2026-09-12T21:00:00Z", "end": "2026-09-12T21:02:00Z", "cells": 0, "rows": 10},
    ],
    "active_seconds": 2520,
    "stitches_per_hour": 66.0,
}
```

Add the three refusals to whatever function writes `refused/` (PR 1 added it): `rows-gap.rows.json` = `rows_doc("Gap", [STRIP_ROWS[0], STRIP_ROWS[2]])` (rows 2-4 missing; id recomputed by `rows_doc`), `rows-open-not-last.rows.json` = `rows_doc("Open", [STRAP_ROWS[1] with "from": 1, STRIP_ROWS[1]])` built as `[dict(STRAP_ROWS[1], **{"from": 1}), STRIP_ROWS[1]]`, and `piece-names-missing-chart.pattern.json` = the pieces-basic manifest with `pieces[0]["chart"]` set to `"sha256:" + "0" * 64`.

In `main`, write every `pieces_basic()` entry under `out_dir / PIECES_DIR / <path>` (creating directories), with `dump`. Create the two committed previews once (never in `main`):

```bash
uv run python - <<'EOF'
from pathlib import Path
from PIL import Image
base = Path("fixtures/chart-format/pieces-basic")
for p in (base / "preview.png", base / "charts/final-sc/preview.png"):
    p.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (7, 5), (0x11, 0x22, 0x33)).save(p)
EOF
```

In `fixtures/bundle/generate.py` add:

```python
from graphghan.bundle import zip_files

CHART_FORMAT = Path(__file__).resolve().parents[1] / "chart-format"


def pieced_bundles(root: Path) -> dict[str, bytes]:
    """Bundles of the hand-built pieced fixtures (the Python writes no pieced pattern, #214): the
    fixture tree zipped as it stands, less the progress files a bundle does not carry."""
    tree = root / "fixtures" / "chart-format" / "pieces-basic"
    files = {
        p.relative_to(tree).as_posix(): p.read_bytes()
        for p in sorted(tree.rglob("*"))
        if p.is_file() and not p.name.startswith("progress")
    }
    return {"pieces-basic.graphghan": zip_files(files)}
```

and in `main`, after the pattern loop, write each `pieced_bundles(ROOT)` entry to `OUT / name`. Note in `fixtures/bundle/README.md` that `pieces-basic.graphghan` is built from `fixtures/chart-format/pieces-basic/`, not from a pattern folder.

Run: `uv run python fixtures/chart-format/generate.py && uv run python fixtures/bundle/generate.py`.

`pattern.json` inside the bundle is the fixture's file bytes (indented JSON), not a compact re-encode: the Swift reader keeps a manifest's bytes as they arrive.

- [ ] **Step 5: Document the format**

In `docs/chart-format.md`:
- Version line: `Version: chart schemas 2 and 3, written-rows schema 1, progress schemas 1 and 2, pattern manifest schemas 1 and 2.`
- Add `## Written-rows document (schema 1)` after the chart document sections, with spec §5.2's example and rules verbatim (entries, tiling, open-ended last entry, pass labels, the id rule with "an absent key is left out, never written as null"), and the derived numbers: `total_rows` is the last `to` (absent when open-ended); `total_stitches` only when closed and every entry has `count`.
- In `## Progress document`, add a `### Schema 2 (pieces)` subsection with spec §5.4's example and rules, plus two rules this plan settles: **rows done** at a written cursor is `row − 1`, or all its rows once the piece is finished (`row` for an open-ended piece); **the finishing advance** — an `advance` event that leaves a written piece's row unchanged — counts that row in its session. `stitches_per_hour` is the chart pieces' stitches over the active seconds of the sessions whose events touched a chart piece.
- In `## Pattern manifest`, add schema 2 (spec §5.3's example and rules), and that `schema/manifest.schema.json` is the first manifest schema.
- In `## Bundle`, add: a pieced bundle also carries every `pieces/*.rows.json` its manifest names, and never the source PDF.
- In `## Conformance`, add: reproduce `pieces-basic/progress.expected.json` from `pieces-basic/progress.json`; refuse `refused/rows-gap.rows.json`, `refused/rows-open-not-last.rows.json` and `refused/piece-names-missing-chart.pattern.json`.

In `fixtures/chart-format/README.md`, add a paragraph on `pieces-basic/` (a bundle's tree: the manifest, the shaped-basic chart as the `panel` piece, three written pieces, a progress-2 document and its hand-worked summary; the two previews are committed, not generated) and the three new refusals.

- [ ] **Step 6: Run to verify**

Run: `uv run pytest -q` → PASS (including freshness of both fixture directories and the bundle drift test). Then `mise run lint`.

- [ ] **Step 7: Commit**

```bash
git add fixtures/chart-format fixtures/bundle src/graphghan/bundle.py tests/test_conformance.py tests/test_bundle_fixtures.py docs/chart-format.md
git commit -m "format: pieces-basic conformance fixtures, a pieced bundle, and the manifest/rows/progress-2 docs (#206)"
```

---

### Task 4: GraphghanCore — decoding the manifest's pieces and assembly

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/SiteModels.swift`, `GraphghanCore.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/SiteModelsTests.swift`, `Fixtures.swift`

**Interfaces:**
- Produces:
  - `public struct ManifestPiece: Decodable, Sendable, Equatable, Hashable, Identifiable { id: String; title: String; make: Int; chart: String?; rows: String?; rowsID: String?; pages: [Int]; var isWritten: Bool }`
  - `public struct AssemblyStep: Decodable, Sendable, Equatable, Hashable { title: String; text: String?; pages: [Int] }`
  - `PatternManifest.pieces: [ManifestPiece]?`, `PatternManifest.assembly: [AssemblyStep]`, `PatternManifest.isPieced: Bool`, `PatternManifest.piecesTotal: Int` (sum of `make`; 1 when not pieced)
  - `GraphghanCore.manifestSchemas: Set<Int> = [1, 2]`, `GraphghanCore.rowsSchema = 1`
  - `Fixtures.piecesDirectory: URL`, `Fixtures.pieces(_ path: String) throws -> Data`

- [ ] **Step 1: Write the failing test**

In `Fixtures.swift` add:

```swift
    /// `fixtures/chart-format/pieces-basic/`: a pieced pattern's tree (manifest 2, a chart, written rows).
    static let piecesDirectory = directory.appendingPathComponent("pieces-basic", isDirectory: true)
    static func pieces(_ path: String) throws -> Data {
        try Data(contentsOf: piecesDirectory.appendingPathComponent(path))
    }
```

Append to `SiteModelsTests`:

```swift
    @Test func aPiecedManifestDecodesItsPiecesAndAssembly() throws {
        let m = try JSONDecoder().decode(PatternManifest.self, from: Fixtures.pieces("pattern.json"))
        #expect(m.schema == 2 && m.isPieced)
        #expect(m.pieces?.map(\.id) == ["panel", "strip", "fin", "strap"])
        #expect(m.pieces?[0].chart == m.charts[0].id && m.pieces?[0].isWritten == false)
        #expect(m.pieces?[1].rows == "pieces/strip.rows.json" && m.pieces?[1].isWritten == true)
        #expect(m.pieces?[2].make == 2 && m.piecesTotal == 5)
        #expect(m.assembly.map(\.title) == ["Sew the strip round the panel", "Pages 4–5"])
        #expect(m.assembly[1].text == nil && m.assembly[1].pages == [4, 5])
    }

    @Test func aManifestWithoutPiecesIsOnePiece() throws {
        let data = try Data(contentsOf: Fixtures.root.appendingPathComponent("fixtures/bundle/craigh-na-dun.graphghan"))
        let m = try PatternBundle.read(data).manifest
        #expect(!m.isPieced && m.pieces == nil && m.assembly.isEmpty && m.piecesTotal == 1)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet --filter SiteModelsTests`
Expected: FAIL to compile — `value of type 'PatternManifest' has no member 'isPieced'`.

- [ ] **Step 3: Implement**

In `SiteModels.swift`, before `PatternManifest`:

```swift
/// One piece of a pieced pattern (manifest schema 2, spec 2026-09-25 §5.3): a chart, or a
/// written-rows document for a piece that is not a grid. Worked `make` times.
public struct ManifestPiece: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let make: Int
    /// A `charts[].id`, for a chart piece.
    public let chart: String?
    /// The rows document's path in the bundle, and its id, for a written piece.
    public let rows: String?
    public let rowsID: String?
    /// Pages of the source PDF this piece comes from.
    public let pages: [Int]
    public var isWritten: Bool { rows != nil }

    enum CodingKeys: String, CodingKey { case id, title, make, chart, rows, pages; case rowsID = "rows_id" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        make = try c.decodeIfPresent(Int.self, forKey: .make) ?? 1
        chart = try c.decodeIfPresent(String.self, forKey: .chart)
        rows = try c.decodeIfPresent(String.self, forKey: .rows)
        rowsID = try c.decodeIfPresent(String.self, forKey: .rowsID)
        pages = try c.decodeIfPresent([Int].self, forKey: .pages) ?? []
    }
}

/// One step of putting the pieces together. A step with only pages points into the source PDF.
public struct AssemblyStep: Decodable, Sendable, Equatable, Hashable {
    public let title: String
    public let text: String?
    public let pages: [Int]
    enum CodingKeys: String, CodingKey { case title, text, pages }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        pages = try c.decodeIfPresent([Int].self, forKey: .pages) ?? []
    }
}
```

In `PatternManifest`, change the doc comment to `(manifest schema 1, or 2 with pieces)` and add after `updated`:

```swift
    /// Manifest schema 2's pieces, in the pattern's order; nil for a manifest without them, which
    /// is one piece: the default chart.
    public let pieces: [ManifestPiece]?
    /// Putting the pieces together; empty when the manifest has none.
    public let assembly: [AssemblyStep]
    public var isPieced: Bool { pieces != nil }
    /// Piece copies to make: the sum of `make`, or 1 for a manifest without pieces.
    public var piecesTotal: Int { pieces?.reduce(0) { $0 + $1.make } ?? 1 }
```

`PatternManifest` is `Decodable` with synthesized conformance today; `assembly` needs a default, so add explicit `CodingKeys` listing every existing key plus `pieces`, `assembly`, and a custom `init(from:)` that decodes every existing field exactly as before (`try c.decode(...)` for each required one) and `pieces = try c.decodeIfPresent([ManifestPiece].self, forKey: .pieces)`, `assembly = try c.decodeIfPresent([AssemblyStep].self, forKey: .assembly) ?? []`. If other code constructs `PatternManifest` with a memberwise initializer (grep `PatternManifest(` in the package and the app, including tests), add a public memberwise `init` with `pieces: [ManifestPiece]? = nil, assembly: [AssemblyStep] = []` defaults so those call sites compile unchanged.

In `GraphghanCore.swift`, add `public static let manifestSchemas: Set<Int> = [1, 2]` and `public static let rowsSchema = 1`, each with a one-line doc comment.

- [ ] **Step 4: Run to verify**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet` → PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "GraphghanCore: decode a manifest's pieces and assembly (#206)"
```

---

### Task 5: GraphghanCore — written rows: document, sequence, engine

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/RowsDocument.swift`, `WrittenSequence.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/RowsDocumentTests.swift`, `WrittenSequenceTests.swift`, `WrittenEngineTests.swift`

**Interfaces:**
- Consumes: `ChartID.prefix`, `CanonicalJSON.encode`, `JSONValue`, `RunString.isValidCode`, `Swatch`, `Cursor`, `WorkAction`, `WorkStep`, `EventKind`.
- Produces:
  - `public struct RowsDocument: Sendable, Equatable { id: String; title: String; palette: [Swatch]; entries: [Entry]; pages: [Int]; notes: [Note]; static func load(_ data: Data) throws -> RowsDocument; static func computeID(_ entries: [Entry]) -> String }`, `RowsDocument.Entry { label: String; from: Int; to: Int?; text: String; count: Int?; code: String?; repeatText: String? }`, `RowsDocument.Note { title: String; text: String }`
  - `public enum RowsError: Error, Equatable { unsupportedSchema(Int); empty; gap(row: Int); openNotLast(entry: Int); noEnd(entry: Int); badRange(entry: Int); badCount(entry: Int); unknownCode(entry: Int, code: String); idMismatch(expected: String, found: String); malformed(String) }`
  - `public struct WrittenPass: Equatable, Sendable { label: String; text: String; count: Int?; code: String?; entry: Int }`
  - `public struct WrittenSequence: Sendable { document: RowsDocument; totalRows: Int?; isOpen: Bool; totalStitches: Int?; func pass(at row: Int) -> WrittenPass?; func rowsDone(at row: Int, finished: Bool) -> Int; func stitchesBefore(row: Int) -> Int? }`
  - `public enum WrittenEngine { static func apply(_ action: WorkAction, to cursor: Cursor, in seq: WrittenSequence) -> WorkStep? }`

- [ ] **Step 1: Write the failing tests**

Create `RowsDocumentTests.swift`:

```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct RowsDocumentTests {
    @Test(arguments: ["pieces/strip.rows.json", "pieces/fin.rows.json", "pieces/strap.rows.json"])
    func everyFixtureRowsDocumentLoads(_ path: String) throws {
        let doc = try RowsDocument.load(Fixtures.pieces(path))
        #expect(doc.id == RowsDocument.computeID(doc.entries))
    }

    @Test func theStripReadsAsPrinted() throws {
        let doc = try RowsDocument.load(Fixtures.pieces("pieces/strip.rows.json"))
        #expect(doc.title == "Strip" && doc.entries.count == 3 && doc.pages == [3])
        #expect(doc.entries[1] == .init(label: "R 2 - R 4", from: 2, to: 4, text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, repeatText: nil))
    }

    @Test func theIDMatchesThePythons() throws {
        // The Python wrote each fixture's id with rowsdoc.rows_id; the Swift id must agree byte for byte.
        let raw = try JSONSerialization.jsonObject(with: Fixtures.pieces("pieces/strap.rows.json")) as! [String: Any]
        let doc = try RowsDocument.load(Fixtures.pieces("pieces/strap.rows.json"))
        #expect(RowsDocument.computeID(doc.entries) == raw["id"] as? String)
    }

    @Test func theRefusalFixturesAreRefused() throws {
        let dir = Fixtures.directory.appendingPathComponent("refused")
        #expect(throws: RowsError.gap(row: 2)) { try RowsDocument.load(Data(contentsOf: dir.appendingPathComponent("rows-gap.rows.json"))) }
        #expect(throws: RowsError.openNotLast(entry: 0)) { try RowsDocument.load(Data(contentsOf: dir.appendingPathComponent("rows-open-not-last.rows.json"))) }
    }
}
```

Create `WrittenSequenceTests.swift`:

```swift
import Testing
@testable import GraphghanCore

@Suite struct WrittenSequenceTests {
    static func seq(_ path: String) throws -> WrittenSequence { WrittenSequence(try RowsDocument.load(Fixtures.pieces(path))) }

    @Test func aRangeIsOnePassPerRow() throws {
        let s = try Self.seq("pieces/strip.rows.json")
        #expect(s.totalRows == 5 && !s.isOpen && s.totalStitches == 30)
        #expect(s.pass(at: 1)?.label == "R 1")
        #expect(s.pass(at: 3) == WrittenPass(label: "R 2 - R 4 (2 of 3)", text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, entry: 1))
        #expect(s.pass(at: 6) == nil && s.pass(at: 0) == nil)
        #expect(s.stitchesBefore(row: 3) == 12)
    }

    /// Review focus 3: an open-ended piece has no total anywhere.
    @Test func openEndedHasNoTotal() throws {
        let s = try Self.seq("pieces/strap.rows.json")
        #expect(s.isOpen && s.totalRows == nil && s.totalStitches == nil)
        #expect(s.pass(at: 57)?.label == "2. (56)")
        #expect(s.rowsDone(at: 10, finished: false) == 9 && s.rowsDone(at: 10, finished: true) == 10)
    }

    @Test func aMissingCountWithholdsStitches() throws {
        let s = try Self.seq("pieces/fin.rows.json")
        #expect(s.totalRows == 3 && s.totalStitches == nil && s.stitchesBefore(row: 2) == nil)
        #expect(s.rowsDone(at: 3, finished: true) == 3)
    }
}
```

Create `WrittenEngineTests.swift`:

```swift
import Testing
@testable import GraphghanCore

@Suite struct WrittenEngineTests {
    static let strip = try! WrittenSequence(RowsDocument.load(Fixtures.pieces("pieces/strip.rows.json")))
    static let strap = try! WrittenSequence(RowsDocument.load(Fixtures.pieces("pieces/strap.rows.json")))

    @Test func advanceMovesOneRow() {
        let step = WrittenEngine.apply(.advance, to: Cursor(row: 2, run: 0), in: Self.strip)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 0), kind: .advance, startedNewRow: true, finished: false))
    }

    @Test func doneOnTheLastRowFinishesAndStays() {
        let step = WrittenEngine.apply(.advance, to: Cursor(row: 5, run: 0), in: Self.strip)
        #expect(step == WorkStep(cursor: Cursor(row: 5, run: 0), kind: .advance, startedNewRow: false, finished: true))
    }

    /// Review focus 1: Back after the finishing Done stays on the last row (the service un-finishes the piece).
    @Test func backAfterFinishingStaysOnTheLastRow() {
        let step = WrittenEngine.apply(.back, to: Cursor(row: 5, run: 0), in: Self.strip, finished: true)
        #expect(step == WorkStep(cursor: Cursor(row: 5, run: 0), kind: .back, startedNewRow: false, finished: false))
        #expect(WrittenEngine.apply(.back, to: Cursor(row: 5, run: 0), in: Self.strip)?.cursor == Cursor(row: 4, run: 0))
        #expect(WrittenEngine.apply(.back, to: Cursor(row: 1, run: 0), in: Self.strip) == nil)
    }

    @Test func jumpStaysInsideAClosedPiece() {
        #expect(WrittenEngine.apply(.jump(row: 4), to: Cursor(row: 1, run: 0), in: Self.strip)?.cursor == Cursor(row: 4, run: 0))
        #expect(WrittenEngine.apply(.jump(row: 9), to: Cursor(row: 1, run: 0), in: Self.strip) == nil)
    }

    @Test func anOpenPieceNeverFinishesOnDone() {
        let step = WrittenEngine.apply(.advance, to: Cursor(row: 400, run: 0), in: Self.strap)
        #expect(step?.cursor == Cursor(row: 401, run: 0) && step?.finished == false)
        #expect(WrittenEngine.apply(.jump(row: 1000), to: Cursor(row: 1, run: 0), in: Self.strap)?.cursor.row == 1000)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet`
Expected: FAIL to compile — `cannot find 'RowsDocument' in scope`.

- [ ] **Step 3: Implement `RowsDocument.swift`**

```swift
import CryptoKit
import Foundation

public enum RowsError: Error, Equatable {
    case unsupportedSchema(Int)
    case empty
    /// Row `row` is missing or printed twice where the entries should tile 1...N.
    case gap(row: Int)
    /// Only the last entry may be open-ended.
    case openNotLast(entry: Int)
    /// An entry with neither `to` nor `repeat`.
    case noEnd(entry: Int)
    case badRange(entry: Int)
    case badCount(entry: Int)
    case unknownCode(entry: Int, code: String)
    case idMismatch(expected: String, found: String)
    case malformed(String)
}

/// A written-rows document (schema 1, spec 2026-09-25 §5.2): a piece that is not a grid. Each
/// entry is one printed line whose rows share its text. Mirrors graphghan.rowsdoc.
public struct RowsDocument: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Decodable {
        public let label: String
        public let from: Int
        public let to: Int?
        public let text: String
        public let count: Int?
        public let code: String?
        public let repeatText: String?
        public init(label: String, from: Int, to: Int?, text: String, count: Int?, code: String?, repeatText: String?) {
            self.label = label; self.from = from; self.to = to; self.text = text; self.count = count; self.code = code; self.repeatText = repeatText
        }
        enum CodingKeys: String, CodingKey { case label, from, to, text, count, code; case repeatText = "repeat" }
    }
    public struct Note: Sendable, Equatable, Decodable { public let title: String; public let text: String }

    public let id: String
    public let title: String
    public let palette: [Swatch]
    public let entries: [Entry]
    public let pages: [Int]
    public let notes: [Note]

    private struct Raw: Decodable {
        struct Piece: Decodable { let title: String }
        struct Source: Decodable { let pages: [Int]? }
        let schema: Int
        let id: String
        let piece: Piece
        let palette: [Swatch]?
        let rows: [Entry]
        let source: Source?
        let notes: [Note]?
    }

    /// Decodes and validates: refuses what cannot be worked as written (gaps, a misplaced open end).
    public static func load(_ data: Data) throws -> RowsDocument {
        let raw: Raw
        do { raw = try JSONDecoder().decode(Raw.self, from: data) } catch { throw RowsError.malformed("\(error)") }
        guard raw.schema == GraphghanCore.rowsSchema else { throw RowsError.unsupportedSchema(raw.schema) }
        guard !raw.rows.isEmpty else { throw RowsError.empty }
        let codes = Set((raw.palette ?? []).map(\.code))
        var expected = 1
        for (i, e) in raw.rows.enumerated() {
            guard e.from == expected else { throw RowsError.gap(row: expected) }
            if let to = e.to {
                guard to >= e.from else { throw RowsError.badRange(entry: i) }
                expected = to + 1
            } else {
                guard e.repeatText != nil else { throw RowsError.noEnd(entry: i) }
                guard i == raw.rows.count - 1 else { throw RowsError.openNotLast(entry: i) }
            }
            if let n = e.count, n < 1 { throw RowsError.badCount(entry: i) }
            if let code = e.code, !RunString.isValidCode(code) || !codes.contains(code) { throw RowsError.unknownCode(entry: i, code: code) }
        }
        let computed = computeID(raw.rows)
        guard computed == raw.id else { throw RowsError.idMismatch(expected: computed, found: raw.id) }
        return RowsDocument(id: raw.id, title: raw.piece.title, palette: raw.palette ?? [], entries: raw.rows,
                            pages: raw.source?.pages ?? [], notes: raw.notes ?? [])
    }

    /// `"sha256:" + hex(sha256(canonical))` over `{"rows": [from, to, text, count, code, repeat]}`:
    /// the rows, not the titles; an absent key stays absent. Mirrors graphghan.rowsdoc.rows_id.
    public static func computeID(_ entries: [Entry]) -> String {
        let rows: [JSONValue] = entries.map { e in
            var o: [String: JSONValue] = ["from": .int(e.from), "text": .string(e.text)]
            if let to = e.to { o["to"] = .int(to) }
            if let n = e.count { o["count"] = .int(n) }
            if let c = e.code { o["code"] = .string(c) }
            if let r = e.repeatText { o["repeat"] = .string(r) }
            return .object(o)
        }
        let canonical = CanonicalJSON.encode(.object(["rows": .array(rows)]))
        return ChartID.prefix + SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
```

(`Swatch` is `Decodable` in SiteModels.swift; `Entry` needs `Decodable` for `Raw`. If `RowsDocument` must be `Equatable` and `Swatch` is not `Equatable`, it is — `Swatch: Decodable, Sendable, Equatable`.)

- [ ] **Step 4: Implement `WrittenSequence.swift`**

```swift
import Foundation

/// One row of a written piece as the Work screen shows it: the entry's text, labelled with its
/// place in a range ("R 27 - 86 (5 of 60)").
public struct WrittenPass: Equatable, Sendable {
    public let label: String
    public let text: String
    public let count: Int?
    public let code: String?
    /// Index of the printed entry this row belongs to.
    public let entry: Int
    public init(label: String, text: String, count: Int?, code: String?, entry: Int) {
        self.label = label; self.text = text; self.count = count; self.code = code; self.entry = entry
    }
}

/// A written piece in working order: one pass per row, no runs, no stitch cursor (spec §6.4).
public struct WrittenSequence: Sendable {
    public let document: RowsDocument
    public init(_ document: RowsDocument) { self.document = document }

    /// The last row, or nil when the last entry is open-ended ("until desired length").
    public var totalRows: Int? { document.entries.last?.to }
    public var isOpen: Bool { totalRows == nil }
    private var allCounted: Bool { document.entries.allSatisfy { $0.count != nil } }
    /// Only for a closed piece whose every entry prints its count; nil otherwise (§Cells rule).
    public var totalStitches: Int? {
        guard !isOpen, allCounted else { return nil }
        return document.entries.reduce(0) { $0 + $1.count! * ($1.to! - $1.from + 1) }
    }

    public func pass(at row: Int) -> WrittenPass? {
        guard row >= 1 else { return nil }
        for (i, e) in document.entries.enumerated() where row >= e.from && (e.to.map { row <= $0 } ?? true) {
            let k = row - e.from + 1
            let label: String
            if let to = e.to { label = to == e.from ? e.label : "\(e.label) (\(k) of \(to - e.from + 1))" }
            else { label = "\(e.label) (\(k))" }
            return WrittenPass(label: label, text: e.text, count: e.count, code: e.code, entry: i)
        }
        return nil
    }

    /// Rows worked at a cursor on `row`: the rows before it, or all of them once finished
    /// (`row` itself for an open-ended piece). Mirrors graphghan.progress._rows_done.
    public func rowsDone(at row: Int, finished: Bool) -> Int {
        finished ? (totalRows ?? row) : row - 1
    }

    /// Stitches in rows 1 ..< `row`, when every entry prints its count.
    public func stitchesBefore(row: Int) -> Int? {
        guard allCounted else { return nil }
        return document.entries.reduce(0) { sum, e in
            let last = min(e.to ?? (row - 1), row - 1)
            return sum + max(0, last - e.from + 1) * e.count!
        }
    }
}

/// Cursor movement on a written piece: whole rows, `run` always 0 (spec §5.4). Done on a closed
/// piece's last row finishes it and stays there; an open-ended piece never finishes on Done.
public enum WrittenEngine {
    /// `finished` says the piece is already finished: Back then un-finishes it in place.
    public static func apply(_ action: WorkAction, to cursor: Cursor, in seq: WrittenSequence, finished: Bool = false) -> WorkStep? {
        let row = cursor.row
        switch action {
        case .advance:
            if let total = seq.totalRows, row >= total {
                guard !finished else { return nil }
                return WorkStep(cursor: Cursor(row: total, run: 0), kind: .advance, startedNewRow: false, finished: true)
            }
            return WorkStep(cursor: Cursor(row: row + 1, run: 0), kind: .advance, startedNewRow: true, finished: false)
        case .back:
            if finished { return WorkStep(cursor: Cursor(row: row, run: 0), kind: .back, startedNewRow: false, finished: false) }
            guard row > 1 else { return nil }
            return WorkStep(cursor: Cursor(row: row - 1, run: 0), kind: .back, startedNewRow: true, finished: false)
        case .jump(let target, _, _):
            guard target >= 1, seq.totalRows.map({ target <= $0 }) ?? true else { return nil }
            return WorkStep(cursor: Cursor(row: target, run: 0), kind: .jump, startedNewRow: target != row, finished: false)
        }
    }
}
```

- [ ] **Step 5: Run to verify**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet` → PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "GraphghanCore: written-rows documents, walked row by row (#206)"
```

---

### Task 6: GraphghanCore — pieced bundles and project progress

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/PatternBundle.swift`, `ProgressDocument.swift`
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ProjectPace.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/PatternBundleTests.swift`, `ProjectPaceTests.swift`

**Interfaces:**
- Consumes: Task 4's `ManifestPiece`, `PatternManifest.pieces`; Task 5's `RowsDocument`, `WrittenSequence`; `Pace.sessionGap`, `WorkSequence`, `ProgressDates`.
- Produces:
  - `public struct BundleRows: Sendable { piece: ManifestPiece; document: RowsDocument; data: Data }`; `PatternBundle.rows: [BundleRows]` (empty for a manifest without pieces)
  - `BundleError` cases `.piecedNeedsSchema2`, `.noPieces`, `.pieceNamesMissingChart(piece: String)`, `.pieceKind(piece: String)`, `.invalidRows(path: String, reason: String)`, `.rowsIDMismatch(path: String, expected: String, found: String)`, each with a sentence in `errorDescription`
  - `public struct PieceKey: Hashable, Sendable, Codable { piece: String; copy: Int }`
  - `public struct PieceProgressRecord: Codable, Equatable, Sendable { piece: String; copy: Int; docID: String; cursor: Cursor; finished: Date? }`
  - `public struct PiecedEventRecord: Codable, Equatable, Sendable { t: Date; piece: String; copy: Int; row: Int; run: Int; stitch: Int; kind: EventKind }`
  - `public struct ProjectProgressDocument: Codable, Equatable, Sendable` (progress schema 2) with `encode() throws -> Data`, `static func decode(_ data: Data) throws -> ProjectProgressDocument`
  - `public enum PieceModel: Sendable { case chart(WorkSequence); case written(WrittenSequence) }`
  - `public struct PieceSummary: Equatable, Sendable { key: PieceKey; isWritten: Bool; finished: Bool; percent: Double?; cellsDone: Int?; totalCells: Int?; rowsDone: Int?; totalRows: Int?; stitchesDone: Int?; totalStitches: Int? }`
  - `public struct ProjectSession: Equatable, Sendable { start: Date; end: Date; cells: Int; rows: Int }`
  - `public struct ProjectSummary: Equatable, Sendable { pieces: [PieceSummary]; piecesDone: Int; piecesTotal: Int; assemblyDone: Int; assemblyTotal: Int; sessions: [ProjectSession]; activeSeconds: Int; stitchesPerHour: Double? }`
  - `public enum ProjectPace { static func summarize(_ doc: ProjectProgressDocument, manifest: PatternManifest, models: [String: PieceModel], gap: TimeInterval = Pace.sessionGap) -> ProjectSummary }` — `models` keyed by piece id; `static func pieceSummary(key: PieceKey, cursor: Cursor, finished: Bool, model: PieceModel) -> PieceSummary`

- [ ] **Step 1: Write the failing tests**

Append to `PatternBundleTests.swift` (it already builds zips with the test target's `ZipBuilder`; reuse it — check its API at the top of `ZipBuilder.swift` and use it exactly as the file's existing tests do):

```swift
    // ---- pieced bundles (manifest schema 2) ----

    static func piecedEntries() throws -> [String: Data] {
        var entries: [String: Data] = [:]
        for path in ["pattern.json", "preview.png", "charts/final-sc/chart.json", "charts/final-sc/preview.png",
                     "pieces/strip.rows.json", "pieces/fin.rows.json", "pieces/strap.rows.json"] {
            entries[path] = try Fixtures.pieces(path)
        }
        return entries
    }

    @Test func theCommittedPiecedBundleReads() throws {
        let bundle = try PatternBundle.read(Fixtures.bundle("pieces-basic"))
        #expect(bundle.manifest.isPieced && bundle.charts.count == 1)
        #expect(bundle.rows.map(\.piece.id) == ["strip", "fin", "strap"])
        #expect(bundle.rows[0].document.title == "Strip")
    }

    /// Review focus 5.
    @Test func aRowsFileWithTheWrongIDIsRefused() throws {
        var entries = try Self.piecedEntries()
        entries["pieces/fin.rows.json"] = entries["pieces/strip.rows.json"]
        let data = try ZipBuilder.zip(entries)   // use the builder's real call shape
        #expect(throws: BundleError.self) { try PatternBundle.read(data) }
        do { _ = try PatternBundle.read(data) } catch let e as BundleError {
            guard case .rowsIDMismatch(let path, _, _) = e else { Issue.record("\(e)"); return }
            #expect(path == "pieces/fin.rows.json")
        }
    }

    /// Review focus 5.
    @Test func aPieceNamingAMissingChartIsRefused() throws {
        var entries = try Self.piecedEntries()
        entries["pattern.json"] = try Data(contentsOf: Fixtures.directory.appendingPathComponent("refused/piece-names-missing-chart.pattern.json"))
        #expect(throws: BundleError.pieceNamesMissingChart(piece: "panel")) { try PatternBundle.read(try ZipBuilder.zip(entries)) }
    }
```

Create `ProjectPaceTests.swift`:

```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ProjectPaceTests {
    struct Expected: Decodable {
        struct Piece: Decodable {
            let piece: String; let copy: Int; let kind: String; let finished: Bool; let percent: Double?
            let cells_done: Int?; let total_cells: Int?; let rows_done: Int?; let total_rows: Int?
            let stitches_done: Int?; let total_stitches: Int?
        }
        struct S: Decodable { let start: String; let end: String; let cells: Int; let rows: Int }
        let pieces: [Piece]; let pieces_done: Int; let pieces_total: Int; let assembly_done: Int; let assembly_total: Int
        let sessions: [S]; let active_seconds: Int; let stitches_per_hour: Double?
    }

    @Test func matchesThePiecesFixture() throws {
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: Fixtures.pieces("pattern.json"))
        var models: [String: PieceModel] = [:]
        for piece in manifest.pieces ?? [] {
            if let rows = piece.rows {
                models[piece.id] = .written(WrittenSequence(try RowsDocument.load(Fixtures.pieces(rows))))
            } else if let path = manifest.charts.first(where: { $0.id == piece.chart })?.path {
                models[piece.id] = .chart(try WorkSequence(chart: Chart.load(Fixtures.pieces(path))))
            }
        }
        let doc = try ProjectProgressDocument.decode(Fixtures.pieces("progress.json"))
        let s = ProjectPace.summarize(doc, manifest: manifest, models: models)
        let e = try JSONDecoder().decode(Expected.self, from: Fixtures.pieces("progress.expected.json"))
        #expect(s.pieces.count == e.pieces.count)
        for (got, want) in zip(s.pieces, e.pieces) {
            #expect(got.key == PieceKey(piece: want.piece, copy: want.copy))
            #expect(got.isWritten == (want.kind == "rows") && got.finished == want.finished)
            #expect(got.percent.map { abs($0 - (want.percent ?? -1)) < 0.001 } ?? (want.percent == nil))
            #expect(got.cellsDone == want.cells_done && got.totalCells == want.total_cells)
            #expect(got.rowsDone == want.rows_done && got.totalRows == want.total_rows)
            #expect(got.stitchesDone == want.stitches_done && got.totalStitches == want.total_stitches)
        }
        #expect(s.piecesDone == e.pieces_done && s.piecesTotal == e.pieces_total)
        #expect(s.assemblyDone == e.assembly_done && s.assemblyTotal == e.assembly_total)
        #expect(s.sessions.map(\.cells) == e.sessions.map(\.cells) && s.sessions.map(\.rows) == e.sessions.map(\.rows))
        #expect(s.sessions.map { ProgressDates.format($0.start) } == e.sessions.map(\.start))
        #expect(s.activeSeconds == e.active_seconds)
        #expect(s.stitchesPerHour.map { abs($0 - (e.stitches_per_hour ?? -1)) < 0.001 } ?? (e.stitches_per_hour == nil))
    }

    @Test func aProgressDocumentRoundTrips() throws {
        let data = try Fixtures.pieces("progress.json")
        let doc = try ProjectProgressDocument.decode(data)
        #expect(try ProjectProgressDocument.decode(doc.encode()) == doc)
        #expect(doc.pieces[3].cursor == Cursor(row: 10, run: 0) && doc.current == PieceKey(piece: "panel", copy: 1))
    }
}
```

In `FixturesTests.swift` nothing changes (the fixture-set test lists top-level `*.chart.json` only).

- [ ] **Step 2: Run to verify they fail**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet`
Expected: FAIL to compile — `value of type 'PatternBundle' has no member 'rows'`, `cannot find 'ProjectPace' in scope`.

- [ ] **Step 3: Implement the pieced bundle**

In `PatternBundle.swift`:
- Add `public let rows: [BundleRows]` to `PatternBundle` (and its initializer, defaulting to `[]` so `PDFImporter.bundle(for:)` and other call sites compile unchanged), and the type:

```swift
/// A written piece's document in a pieced bundle.
public struct BundleRows: Sendable {
    public let piece: ManifestPiece
    public let document: RowsDocument
    public let data: Data
    public init(piece: ManifestPiece, document: RowsDocument, data: Data) { self.piece = piece; self.document = document; self.data = data }
}
```

- In `read`: replace `guard manifest.schema == 1 else …` with `guard GraphghanCore.manifestSchemas.contains(manifest.schema) else { throw BundleError.unsupportedManifestSchema(manifest.schema) }`; if `manifest.pieces != nil` and `manifest.schema != 2` throw `.piecedNeedsSchema2`. Replace `guard !manifest.charts.isEmpty else { throw BundleError.noCharts }` with: when not pieced, as today; when pieced, `guard !(manifest.pieces ?? []).isEmpty else { throw BundleError.noPieces }` (a written-only pattern may have no charts). Before `checkPaths`, validate each piece: exactly one of `chart`/`rows` (`.pieceKind(piece:)`), a chart piece's id present in `manifest.charts` (`.pieceNamesMissingChart(piece:)`), a written piece has `rowsID` (`.pieceKind(piece:)`). Add the rows paths to the `checkPaths` list. After the charts loop, read each written piece's file, `RowsDocument.load` it (`.invalidRows(path:reason:)` on a thrown error, reason via the existing `describe`), and compare `document.id` with `piece.rowsID` (`.rowsIDMismatch`). Pass `rows` to the initializer.
- `errorDescription` sentences (match the file's tone):
  - `.piecedNeedsSchema2`: "This pattern lists its pieces in a format this version of Graphghan doesn't recognise."
  - `.noPieces`: "This pattern says it is made of pieces but lists none."
  - `.pieceNamesMissingChart(let p)`: "The piece “\(p)” names a chart this file doesn't contain."
  - `.pieceKind(let p)`: "The piece “\(p)” is neither a chart nor written rows."
  - `.invalidRows(let path, let reason)`: "The written rows in \(path) can't be used: \(reason)"
  - `.rowsIDMismatch(let path, _, _)`: "The written rows in \(path) don't match what the pattern lists."

- [ ] **Step 4: Implement the progress-2 document and `ProjectPace`**

Append to `ProgressDocument.swift`:

```swift
/// Which copy of which piece: a pieced project's unit of progress (spec 2026-09-25 §5.4).
public struct PieceKey: Hashable, Sendable, Codable {
    public let piece: String
    public let copy: Int
    public init(piece: String, copy: Int) { self.piece = piece; self.copy = copy }
}

public struct PieceProgressRecord: Codable, Equatable, Sendable {
    public let piece: String
    public let copy: Int
    public let docID: String
    public let cursor: Cursor
    public let finished: Date?
    public var key: PieceKey { PieceKey(piece: piece, copy: copy) }
    public init(piece: String, copy: Int, docID: String, cursor: Cursor, finished: Date?) {
        self.piece = piece; self.copy = copy; self.docID = docID; self.cursor = cursor; self.finished = finished
    }
    enum CodingKeys: String, CodingKey { case piece, copy, cursor, finished; case docID = "doc_id" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(piece, forKey: .piece); try c.encode(copy, forKey: .copy); try c.encode(docID, forKey: .docID)
        try c.encode(cursor, forKey: .cursor); try c.encode(finished, forKey: .finished)  // null, not absent
    }
}

public struct PiecedEventRecord: Codable, Equatable, Sendable {
    public let t: Date
    public let piece: String
    public let copy: Int
    public let row: Int
    public let run: Int
    public let stitch: Int
    public let kind: EventKind
    public var key: PieceKey { PieceKey(piece: piece, copy: copy) }
    public var cursor: Cursor { Cursor(row: row, run: run, stitch: stitch) }
    public init(t: Date, piece: String, copy: Int, row: Int, run: Int, stitch: Int = 0, kind: EventKind) {
        self.t = t; self.piece = piece; self.copy = copy; self.row = row; self.run = run; self.stitch = stitch; self.kind = kind
    }
    enum CodingKeys: String, CodingKey { case t, piece, copy, row, run, stitch, kind }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Date.self, forKey: .t); piece = try c.decode(String.self, forKey: .piece); copy = try c.decode(Int.self, forKey: .copy)
        row = try c.decode(Int.self, forKey: .row); run = try c.decode(Int.self, forKey: .run)
        stitch = try c.decodeIfPresent(Int.self, forKey: .stitch) ?? 0; kind = try c.decode(EventKind.self, forKey: .kind)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t); try c.encode(piece, forKey: .piece); try c.encode(copy, forKey: .copy)
        try c.encode(row, forKey: .row); try c.encode(run, forKey: .run)
        if stitch != 0 { try c.encode(stitch, forKey: .stitch) }
        try c.encode(kind, forKey: .kind)
    }
}

/// Progress document, schema 2: a pieced project (spec 2026-09-25 §5.4).
public struct ProjectProgressDocument: Codable, Equatable, Sendable {
    public var schema: Int = 2
    public var patternID: String
    public var patternVersion: String?
    public var pieces: [PieceProgressRecord]
    public var current: PieceKey?
    public var assemblyDone: [Int]
    public var started: Date?
    public var finished: Date?
    public var events: [PiecedEventRecord]
    public init(patternID: String, patternVersion: String?, pieces: [PieceProgressRecord], current: PieceKey?, assemblyDone: [Int],
                started: Date?, finished: Date?, events: [PiecedEventRecord]) {
        self.patternID = patternID; self.patternVersion = patternVersion; self.pieces = pieces; self.current = current
        self.assemblyDone = assemblyDone; self.started = started; self.finished = finished; self.events = events
    }
    enum CodingKeys: String, CodingKey {
        case schema, pieces, current, started, finished, events
        case patternID = "pattern_id", patternVersion = "pattern_version", assemblyDone = "assembly_done"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        patternID = try c.decode(String.self, forKey: .patternID)
        patternVersion = try c.decodeIfPresent(String.self, forKey: .patternVersion)
        pieces = try c.decode([PieceProgressRecord].self, forKey: .pieces)
        current = try c.decodeIfPresent(PieceKey.self, forKey: .current)
        assemblyDone = try c.decodeIfPresent([Int].self, forKey: .assemblyDone) ?? []
        started = try c.decodeIfPresent(Date.self, forKey: .started)
        finished = try c.decodeIfPresent(Date.self, forKey: .finished)
        events = try c.decodeIfPresent([PiecedEventRecord].self, forKey: .events) ?? []
    }
    /// Dates as the schema-1 document writes them (`ProgressDocument.decode`/`encode` show how:
    /// reuse the same decoder/encoder configuration, including `ProgressDates`).
    public static func decode(_ data: Data) throws -> ProjectProgressDocument
    public func encode() throws -> Data
}
```

Implement `decode`/`encode` by copying the date strategy lines from `ProgressDocument.decode`/`encode` in the same file (same `JSONDecoder`/`JSONEncoder` configuration, `sortedKeys` and `withoutEscapingSlashes`), so both documents write dates identically. `PieceProgressRecord.cursor` uses `Cursor`'s `Codable`, which omits `stitch` when 0 — a written piece's cursor encodes as `{"row": n, "run": 0}` as the spec requires.

Create `ProjectPace.swift`:

```swift
import Foundation

public enum PieceModel: Sendable {
    case chart(WorkSequence)
    case written(WrittenSequence)
}

public struct PieceSummary: Equatable, Sendable {
    public let key: PieceKey
    public let isWritten: Bool
    public let finished: Bool
    public let percent: Double?
    public let cellsDone: Int?
    public let totalCells: Int?
    public let rowsDone: Int?
    public let totalRows: Int?
    public let stitchesDone: Int?
    public let totalStitches: Int?
}

public struct ProjectSession: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let cells: Int
    public let rows: Int
}

public struct ProjectSummary: Equatable, Sendable {
    public let pieces: [PieceSummary]
    public let piecesDone: Int
    public let piecesTotal: Int
    public let assemblyDone: Int
    public let assemblyTotal: Int
    public let sessions: [ProjectSession]
    public let activeSeconds: Int
    public let stitchesPerHour: Double?
}

/// A pieced project's numbers (progress schema 2, spec 2026-09-25 §5.4). Mirrors
/// graphghan.progress.summarize_project; no project percent (§3.4).
public enum ProjectPace {
    static func roundTenth(_ x: Double) -> Double { (x * 10).rounded(.toNearestOrEven) / 10 }

    public static func pieceSummary(key: PieceKey, cursor: Cursor, finished: Bool, model: PieceModel) -> PieceSummary {
        switch model {
        case .chart(let seq):
            let total = seq.totalCells
            let done = seq.cellsBefore(cursor) ?? 0
            let stitch = seq.cellKind == .stitch
            return PieceSummary(key: key, isWritten: false, finished: finished,
                                percent: total > 0 ? roundTenth(100 * Double(done) / Double(total)) : 0, cellsDone: done, totalCells: total,
                                rowsDone: nil, totalRows: nil, stitchesDone: stitch ? done : nil, totalStitches: stitch ? total : nil)
        case .written(let seq):
            let done = seq.rowsDone(at: cursor.row, finished: finished)
            let percent = seq.totalRows.map { $0 > 0 ? roundTenth(100 * Double(done) / Double($0)) : 0 }
            let stTotal = seq.totalStitches
            let stDone = stTotal.map { finished ? $0 : (seq.stitchesBefore(row: cursor.row) ?? 0) }
            return PieceSummary(key: key, isWritten: true, finished: finished, percent: percent, cellsDone: nil, totalCells: nil,
                                rowsDone: done, totalRows: seq.totalRows, stitchesDone: stDone, totalStitches: stTotal)
        }
    }

    public static func summarize(_ doc: ProjectProgressDocument, manifest: PatternManifest, models: [String: PieceModel],
                                 gap: TimeInterval = Pace.sessionGap) -> ProjectSummary {
        let pieces = doc.pieces.compactMap { p in
            models[p.piece].map { pieceSummary(key: p.key, cursor: p.cursor, finished: p.finished != nil, model: $0) }
        }
        // Sessions over every event, split by time; each piece's worked amount across the session.
        struct Open { var start: Date; var end: Date; var from: [PieceKey: Cursor]; var to: [PieceKey: Cursor]; var finishing: [PieceKey: Bool] }
        var last: [PieceKey: Cursor] = [:]
        var sessions: [Open] = []
        var current: Open?
        for e in doc.events.sorted(by: { $0.t < $1.t }) {
            if current == nil || e.t.timeIntervalSince(current!.end) > gap {
                if let c = current { sessions.append(c) }
                current = Open(start: e.t, end: e.t, from: [:], to: [:], finishing: [:])
            }
            let before = last[e.key] ?? .start
            if current!.from[e.key] == nil { current!.from[e.key] = before }
            let isWritten: Bool = { if case .written = models[e.piece] { return true } else { return false } }()
            current!.finishing[e.key] = e.kind == .advance && e.row == before.row && isWritten
            current!.to[e.key] = e.cursor
            current!.end = e.t
            last[e.key] = e.cursor
        }
        if let c = current { sessions.append(c) }
        var out: [ProjectSession] = []
        var active = 0, chartActive = 0, chartStitches = 0
        for s in sessions {
            var cells = 0, rows = 0, touchedChart = false
            for (key, from) in s.from {
                let to = s.to[key]!
                switch models[key.piece] {
                case .chart(let seq)?:
                    touchedChart = true
                    let n = max(0, (seq.cellsBefore(to) ?? 0) - (seq.cellsBefore(from) ?? 0))
                    cells += n
                    if seq.cellKind == .stitch { chartStitches += n }
                case .written(let seq)?:
                    rows += max(0, seq.rowsDone(at: to.row, finished: s.finishing[key] ?? false) - seq.rowsDone(at: from.row, finished: false))
                case nil:
                    break
                }
            }
            let secs = Int(s.end.timeIntervalSince(s.start).rounded(.down))
            active += secs
            if touchedChart { chartActive += secs }
            out.append(ProjectSession(start: s.start, end: s.end, cells: cells, rows: rows))
        }
        return ProjectSummary(pieces: pieces, piecesDone: pieces.filter(\.finished).count, piecesTotal: manifest.piecesTotal,
                              assemblyDone: doc.assemblyDone.count, assemblyTotal: manifest.assembly.count, sessions: out,
                              activeSeconds: active,
                              stitchesPerHour: chartActive > 0 ? roundTenth(Double(chartStitches) / (Double(chartActive) / 3600)) : nil)
    }
}
```

Python's `round(x, 1)` is round-half-even on the float; `.toNearestOrEven` on `x * 10` matches it for the fixture's values (as `AppModel.snapshot` already does). If a fixture value disagrees, report it rather than change the fixture.

- [ ] **Step 5: Run to verify**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet` → PASS. Then build the app once (`PatternBundle`'s initializer changed): from `ios/`, `xcodebuild build -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData`.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "GraphghanCore: read pieced bundles; summarise a pieced project (progress 2) (#206)"
```

---

### Task 7: App storage — `PieceProgress`, project fields, `RowsLibrary`, bundle import

**Files:**
- Create: `ios/Graphghan/Storage/PieceProgress.swift`, `ios/Graphghan/Storage/RowsLibrary.swift`, `ios/Tests/RowsLibraryTests.swift`
- Modify: `ios/Graphghan/Storage/Project.swift`, `ProgressEvent.swift`, `Persistence.swift`, `AppGroup.swift`, `ios/Graphghan/Services/BundleImporter.swift`, `ios/Graphghan/AppModel.swift` (construct and pass `RowsLibrary`)
- Test: `ios/Tests/ProjectModelTests.swift`, `ios/Tests/BundleImportTests.swift`, `ios/Tests/TestSupport.swift`

**Interfaces:**
- Consumes: Task 6's `PatternBundle.rows`, `BundleRows`; Task 5's `RowsDocument`.
- Produces:
  - `@Model final class PieceProgress { pieceID: String; copy: Int; docID: String; cursorRow: Int; cursorRun: Int; cursorStitch: Int; finished: Date?; project: Project?; var cursor: Cursor; var key: PieceKey; init(pieceID: String, copy: Int, docID: String) }`
  - `Project` gains `currentPiece: String? = nil`, `currentCopy: Int = 1`, `currentRowsID: String? = nil`, `assemblyDone: [Int] = []`, `piecesTotal: Int = 1`, `assemblyTotal: Int = 0`; computed `isPieced: Bool`, `currentIsWritten: Bool`, `currentKey: PieceKey?`
  - `ProgressEvent` gains `piece: String? = nil`, `copy: Int = 1`
  - `actor RowsLibrary { init(directory: URL); func store(_ data: Data) throws -> RowsDocument; func data(id: String) throws -> Data; func document(id: String) throws -> RowsDocument; func has(id: String) -> Bool; func remove(id: String) throws }`
  - `AppGroup.rowsURL`; `BundleImporter(charts:rows:local:)`; `AppModel.rows: RowsLibrary`
  - `TestFixtures.pieces(_ path: String) throws -> Data`

- [ ] **Step 1: Write the failing tests**

In `TestSupport.swift`, add to `TestFixtures`: `static func pieces(_ path: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent("pieces-basic/\(path)")) }`.

Create `ios/Tests/RowsLibraryTests.swift`:

```swift
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct RowsLibraryTests {
    @Test func storesByIDAndReadsBack() async throws {
        let library = RowsLibrary(directory: try temporaryDirectory())
        let data = try TestFixtures.pieces("pieces/strip.rows.json")
        let stored = try await library.store(data)
        #expect(await library.has(id: stored.id))
        #expect(try await library.document(id: stored.id) == stored)
        #expect(try await library.data(id: stored.id) == data)
    }

    @Test func refusesAnInvalidDocumentAndStoresNothing() async throws {
        let dir = try temporaryDirectory()
        let library = RowsLibrary(directory: dir)
        let bad = try Data(contentsOf: TestFixtures.directory.appendingPathComponent("refused/rows-gap.rows.json"))
        await #expect(throws: RowsError.self) { try await library.store(bad) }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).isEmpty)
    }
}
```

Append to `ProjectModelTests` (it already has an in-memory container helper; use it as its neighbours do):

```swift
    /// Review focus 4: a project made before pieces existed reads as one piece, unchanged.
    @Test @MainActor func aProjectWithoutPiecesIsUnchanged() throws {
        let container = try makeInMemoryContainer()
        let p = Project(patternID: "p", chartID: "sha256:x", chartVariant: "final", chartGaugeKey: "sc", patternVersion: "1", title: "T", started: .now)
        container.mainContext.insert(p)
        try container.mainContext.save()
        #expect(!p.isPieced && !p.currentIsWritten && p.currentKey == nil && p.assemblyDone.isEmpty && p.piecesTotal == 1)
    }

    @Test @MainActor func pieceProgressKeepsItsCursor() throws {
        let container = try makeInMemoryContainer()
        let project = Project(patternID: "p", chartID: "", chartVariant: "", chartGaugeKey: "", patternVersion: "1", title: "T", started: .now)
        let piece = PieceProgress(pieceID: "strip", copy: 2, docID: "sha256:y")
        piece.project = project
        piece.cursor = Cursor(row: 4, run: 0)
        container.mainContext.insert(project)
        container.mainContext.insert(piece)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<PieceProgress>())
        #expect(fetched.count == 1 && fetched[0].cursor == Cursor(row: 4, run: 0) && fetched[0].key == PieceKey(piece: "strip", copy: 2))
    }
```

Append to `BundleImportTests`:

```swift
    @Test func aPiecedBundleStoresItsChartsAndRows() async throws {
        let charts = ChartLibrary(directory: try temporaryDirectory())
        let rows = RowsLibrary(directory: try temporaryDirectory())
        let importer = BundleImporter(charts: charts, rows: rows, local: try makeLocalPatternStore())
        let manifest = try await importer.importBundle(try TestFixtures.bundle("pieces-basic"))
        #expect(manifest.isPieced)
        for piece in manifest.pieces ?? [] {
            if let id = piece.rowsID { #expect(await rows.has(id: id)) }
            if let id = piece.chart { #expect(await charts.hasChart(id: id)) }
        }
    }
```

Update every existing `BundleImporter(charts:local:)` call in the tests to pass `rows: RowsLibrary(directory: try temporaryDirectory())`.

- [ ] **Step 2: Run to verify they fail**

Run (from `ios/`): `mise run generate`, then the xcodebuild test command with `-only-testing:GraphghanTests/RowsLibraryTests -only-testing:GraphghanTests/ProjectModelTests -only-testing:GraphghanTests/BundleImportTests`.
Expected: FAIL to compile — `cannot find 'RowsLibrary' in scope`, `value of type 'Project' has no member 'isPieced'`.

- [ ] **Step 3: Implement**

`PieceProgress.swift`:

```swift
import Foundation
import SwiftData
import GraphghanCore

/// One piece copy's place in a pieced project (spec 2026-09-25 §6.1). The project's own cursor
/// fields mirror the current piece's; this keeps every started copy's.
@Model
final class PieceProgress {
    var pieceID: String
    var copy: Int
    /// The chart id or rows id the cursor walks.
    var docID: String
    var cursorRow: Int = 1
    var cursorRun: Int = 0
    var cursorStitch: Int = 0
    var finished: Date?
    /// Deliberately no inverse array on `Project`, as for `ProgressEvent` (#79).
    var project: Project?

    init(pieceID: String, copy: Int, docID: String) {
        self.pieceID = pieceID; self.copy = copy; self.docID = docID
        self.cursorRow = 1; self.cursorRun = 0; self.cursorStitch = 0; self.finished = nil; self.project = nil
    }

    var cursor: Cursor {
        get { Cursor(row: cursorRow, run: cursorRun, stitch: cursorStitch) }
        set { cursorRow = newValue.row; cursorRun = newValue.run; cursorStitch = newValue.stitch }
    }
    var key: PieceKey { PieceKey(piece: pieceID, copy: copy) }
}
```

`Project.swift` — add after `lastWorked`, each with a comment in the file's style, then the computed properties:

```swift
    /// A pieced project's current piece (manifest schema 2); nil for a single-chart project, whose
    /// cursor fields are its only piece. For a pieced project `chartID` and the cursor fields
    /// mirror the current piece (spec 2026-09-25 §6.1). Defaults keep the migration lightweight.
    var currentPiece: String? = nil
    var currentCopy: Int = 1
    /// The current piece's rows id when it is written, not charted; `chartID` is then "".
    var currentRowsID: String? = nil
    /// Indexes of the assembly steps ticked off.
    var assemblyDone: [Int] = []
    /// Piece copies to make and assembly steps, from the manifest when the project started.
    var piecesTotal: Int = 1
    var assemblyTotal: Int = 0
```

```swift
    var isPieced: Bool { currentPiece != nil }
    var currentIsWritten: Bool { currentRowsID != nil }
    var currentKey: PieceKey? { currentPiece.map { PieceKey(piece: $0, copy: currentCopy) } }
```

`ProgressEvent.swift` — add `var piece: String? = nil` and `var copy: Int = 1` with a comment ("which piece copy of a pieced project; nil for a single-chart project"), and an `init` parameter pair `piece: String? = nil, copy: Int = 1` assigned in the body.

`Persistence.swift`: `static let schema = Schema([Project.self, ProgressEvent.self, PieceProgress.self])`.

`AppGroup.swift`: `static var rowsURL: URL { supportURL.appendingPathComponent("rows", isDirectory: true) }` beside `chartsURL`.

`RowsLibrary.swift`: copy `ChartLibrary.swift`'s structure exactly (same file naming by id, same atomic write, same directory creation), replacing `Chart.load` with `RowsDocument.load`, `hasChart` with `has(id:)`, and `chart(id:)` with `document(id:)`; `store` validates with `RowsDocument.load` before writing and returns the document.

`BundleImporter.swift`: add `let rows: RowsLibrary` and the `rows:` initializer parameter; in `importBundle`, after storing charts: `for r in bundle.rows { _ = try await rows.store(r.data) }`.

`AppModel.swift`: add `let rows: RowsLibrary`, an initializer parameter beside `charts` defaulting in the production call site to `RowsLibrary(directory: AppGroup.rowsURL)`, and pass it to `BundleImporter(charts:rows:local:)` and (in Task 8) `ProjectService`. Update every `AppModel(` call in the tests to pass a temporary `RowsLibrary` if the parameter has no default; give it a default of `RowsLibrary(directory: AppGroup.rowsURL)` only if `charts` has one.

- [ ] **Step 4: Run to verify**

Run the Step 2 command → PASS. Then `mise run test` → PASS (every existing test, including the persistence ones, proves the migration is lightweight).

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: store a pieced project's pieces and written rows (#206)"
```

---

### Task 8: `ProjectService` — starting, switching and working pieces

**Files:**
- Modify: `ios/Graphghan/Services/ProjectService.swift`, `ios/Graphghan/AppModel.swift`
- Create: `ios/Graphghan/Services/PieceWork.swift`, `ios/Tests/ProjectServicePiecesTests.swift`

**Interfaces:**
- Consumes: Task 7's models and `RowsLibrary`; Task 6's `ProjectPace.pieceSummary`, `PieceModel`, `ProjectProgressDocument`; Task 5's `WrittenEngine`, `WrittenSequence`; Task 4's `ManifestPiece`.
- Produces (all on `ProjectService`, `@MainActor` like the rest of it):
  - `enum PieceWork { case chart(Chart, WorkSequence); case written(WrittenSequence) }` with `var model: PieceModel`
  - `struct PieceStatus: Equatable, Identifiable { piece: ManifestPiece; copy: Int; isWritten: Bool; line: String; finished: Bool; isCurrent: Bool; var id: PieceKey }`
  - `func startPiecedProject(manifest: PatternManifest, title: String) async throws -> Project`
  - `func selectPiece(_ key: PieceKey, of project: Project, manifest: PatternManifest) async throws`
  - `func work(for project: Project) async throws -> PieceWork`
  - `func apply(_ action: WorkAction, to project: Project, work: PieceWork) -> WorkStep?`
  - `func finishPiece(_ project: Project) throws` (open-ended written piece)
  - `func setAssemblyStep(_ index: Int, done: Bool, for project: Project) throws`
  - `func pieceProgress(for project: Project) throws -> [PieceProgress]`
  - `func statuses(for project: Project, manifest: PatternManifest) async -> [PieceStatus]`
  - `func nextUnfinished(after project: Project, manifest: PatternManifest) throws -> PieceKey?`
  - `func progressLine(for project: Project, manifest: PatternManifest, work: PieceWork) throws -> String` → `"Front panel · Row 42 of 77 · 3 of 8 pieces"` / `"Strap · Row 57 · 1 of 5 pieces"`
  - `func currentPercent(for project: Project, work: PieceWork) -> Double?` (nil when the current piece is open-ended)
  - `exportDocument(for:)` returns progress 2 for a pieced project via a new `func exportPiecedDocument(for project: Project) throws -> ProjectProgressDocument`

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/ProjectServicePiecesTests.swift`. Build the service exactly as `ProjectServiceTests` does (read its setup helper and copy it), with a `ChartLibrary` and `RowsLibrary` in temporary directories that already hold the pieces-basic chart and rows documents (store them from `TestFixtures.pieces(...)`), and the manifest decoded from `TestFixtures.pieces("pattern.json")`. Tests:

```swift
    @Test func startingAPiecedPatternStartsItsFirstPiece() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        #expect(p.isPieced && p.currentKey == PieceKey(piece: "panel", copy: 1))
        #expect(p.chartID == manifest.charts[0].id && !p.currentIsWritten)
        #expect(p.piecesTotal == 5 && p.assemblyTotal == 2 && p.title == "Pieces basic")
        #expect(try service.pieceProgress(for: p).map(\.key) == [PieceKey(piece: "panel", copy: 1)])
    }

    /// Review focus 2.
    @Test func eachPieceKeepsItsOwnCursor() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        var work = try await service.work(for: p)
        service.apply(.advance, to: p, work: work)   // panel row 1 → row 2 (a one-run row)
        service.apply(.advance, to: p, work: work)
        let panelCursor = p.cursor
        try await service.selectPiece(PieceKey(piece: "strip", copy: 1), of: p, manifest: manifest)
        #expect(p.currentIsWritten && p.cursor == Cursor(row: 1, run: 0) && p.chartID == "")
        work = try await service.work(for: p)
        service.apply(.advance, to: p, work: work)
        #expect(p.cursor == Cursor(row: 2, run: 0))
        try await service.selectPiece(PieceKey(piece: "panel", copy: 1), of: p, manifest: manifest)
        #expect(p.cursor == panelCursor && p.chartID == manifest.charts[0].id)
    }

    @Test func eventsRecordTheirPiece() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        try await service.selectPiece(PieceKey(piece: "fin", copy: 2), of: p, manifest: manifest)
        service.apply(.advance, to: p, work: try await service.work(for: p))
        let doc = try service.exportPiecedDocument(for: p)
        #expect(doc.events.last?.key == PieceKey(piece: "fin", copy: 2) && doc.events.last?.run == 0)
        #expect(doc.current == PieceKey(piece: "fin", copy: 2))
    }

    @Test func doneOnTheLastRowFinishesThePieceNotTheProject() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        try await service.selectPiece(PieceKey(piece: "strip", copy: 1), of: p, manifest: manifest)
        let work = try await service.work(for: p)
        for _ in 0..<5 { service.apply(.advance, to: p, work: work) }
        let strip = try service.pieceProgress(for: p).first { $0.key == PieceKey(piece: "strip", copy: 1) }
        #expect(strip?.finished != nil && !p.isFinished)
        #expect(try service.nextUnfinished(after: p, manifest: manifest) == PieceKey(piece: "panel", copy: 1))
    }

    /// Review focus 1.
    @Test func backUnfinishesAPiece() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        try await service.selectPiece(PieceKey(piece: "strip", copy: 1), of: p, manifest: manifest)
        let work = try await service.work(for: p)
        for _ in 0..<5 { service.apply(.advance, to: p, work: work) }
        service.apply(.back, to: p, work: work)
        let strip = try service.pieceProgress(for: p).first { $0.key == PieceKey(piece: "strip", copy: 1) }
        #expect(strip?.finished == nil && p.cursor == Cursor(row: 5, run: 0))
    }

    @Test func theProjectFinishesWithItsLastPieceAndStep() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        for key in [PieceKey(piece: "strip", copy: 1), PieceKey(piece: "fin", copy: 1), PieceKey(piece: "fin", copy: 2)] {
            try await service.selectPiece(key, of: p, manifest: manifest)
            let work = try await service.work(for: p)
            while !(try service.pieceProgress(for: p).first { $0.key == key }?.finished != nil) { service.apply(.advance, to: p, work: work) }
        }
        try await service.selectPiece(PieceKey(piece: "strap", copy: 1), of: p, manifest: manifest)
        try service.finishPiece(p)
        try await service.selectPiece(PieceKey(piece: "panel", copy: 1), of: p, manifest: manifest)
        let panel = try await service.work(for: p)
        while service.apply(.advance, to: p, work: panel)?.finished != true {}
        #expect(!p.isFinished)                       // assembly still open
        try service.setAssemblyStep(0, done: true, for: p)
        try service.setAssemblyStep(1, done: true, for: p)
        #expect(p.isFinished)
        try service.setAssemblyStep(1, done: false, for: p)
        #expect(!p.isFinished)
    }

    /// Review focus 3.
    @Test func progressLineForAnOpenPiece() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        #expect(try service.progressLine(for: p, manifest: manifest, work: try await service.work(for: p)) == "Panel · Row 1 of 5 · 0 of 5 pieces")
        try await service.selectPiece(PieceKey(piece: "strap", copy: 1), of: p, manifest: manifest)
        let work = try await service.work(for: p)
        #expect(try service.progressLine(for: p, manifest: manifest, work: work) == "Strap · Row 1 · 0 of 5 pieces")
        #expect(service.currentPercent(for: p, work: work) == nil)
    }

    @Test func statusesListEveryCopyInOrder() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        let s = await service.statuses(for: p, manifest: manifest)
        #expect(s.map(\.id) == [PieceKey(piece: "panel", copy: 1), PieceKey(piece: "strip", copy: 1), PieceKey(piece: "fin", copy: 1),
                                PieceKey(piece: "fin", copy: 2), PieceKey(piece: "strap", copy: 1)])
        #expect(s.map(\.line) == ["Row 1 of 5", "5 rows", "3 rows", "3 rows", "Open-ended"])
        #expect(s[0].isCurrent && !s[1].isCurrent)
    }
```

The row lines: a started piece reads "Row r of N" (or "Row r" when open-ended); a piece never started reads "N rows" for a closed written piece, "Open-ended" for an open one, and "N rows" for a chart piece; a finished piece reads "Done". A `make: 2` piece is listed once per copy, titled in the view (Task 9), not here.

- [ ] **Step 2: Run to verify they fail**

Run (from `ios/`): `mise run generate`, then the xcodebuild test command with `-only-testing:GraphghanTests/ProjectServicePiecesTests`.
Expected: FAIL to compile — `value of type 'ProjectService' has no member 'startPiecedProject'`.

- [ ] **Step 3: Implement**

`PieceWork.swift`:

```swift
import GraphghanCore

/// The current piece of a project, ready to work: a chart and its sequence, or written rows.
enum PieceWork {
    case chart(Chart, WorkSequence)
    case written(WrittenSequence)
    var model: PieceModel {
        switch self {
        case .chart(_, let seq): .chart(seq)
        case .written(let seq): .written(seq)
        }
    }
}

/// One piece copy as the project screen lists it (spec 2026-09-25 §6.2).
struct PieceStatus: Equatable, Identifiable {
    let piece: ManifestPiece
    let copy: Int
    let isWritten: Bool
    let line: String
    let finished: Bool
    let isCurrent: Bool
    var id: PieceKey { PieceKey(piece: piece.id, copy: copy) }
}
```

`ProjectService.swift`:
- Add `let rows: RowsLibrary` and the initializer parameter (update `AppModel` and every test that builds a `ProjectService`).
- `startPiecedProject`: guard `let first = manifest.pieces?.first`; store every chart the manifest carries that is not already in `charts` (the bundle import stored them; `patterns.chartData` is only for site patterns, which are never pieced — if a chart is missing, throw `ServiceError.chartUnavailable(id)`); create the `Project` with `chartID: ""`, `chartVariant: ""`, `chartGaugeKey: ""`, `piecesTotal: manifest.piecesTotal`, `assemblyTotal: manifest.assembly.count`; insert it; `try await selectPiece(PieceKey(piece: first.id, copy: 1), of: project, manifest: manifest)`; save; `onProjectsChanged?()`.
- `pieceProgress(for:)`: fetch `PieceProgress` by `#Predicate { $0.project?.id == id }`, sorted by `pieceID` then `copy` (the order does not matter to callers; `statuses` orders by the manifest).
- `selectPiece`: find the `ManifestPiece`; fetch or create its `PieceProgress` (`docID` = `piece.chart ?? piece.rowsID!`), insert and link it when new; set `project.currentPiece/currentCopy`; `project.cursor = progress.cursor`; if written, `project.currentRowsID = piece.rowsID`, `project.chartID = ""`, else `project.currentRowsID = nil`, `project.chartID = piece.chart!`, and set `chartVariant`/`chartGaugeKey` from the manifest's chart entry; save.
- `work(for:)`: written → `.written(WrittenSequence(try await rows.document(id: project.currentRowsID!)))` (map a thrown error to `ServiceError.chartUnavailable(project.currentRowsID!)`); otherwise `.chart(chart, sequence)` from the existing `chart(for:)`/`WorkSequence(chart:)`.
- `apply(_:to:work:)`: `.chart` → the existing `apply(_:to:in:)`; `.written(seq)` → a new private `applyWritten`: `WrittenEngine.apply(action, to: project.cursor, in: seq, finished: currentProgress.finished != nil)`; set `project.cursor`, `lastWorked`; finishing → `currentProgress.finished = t`; a `.back`/`.jump` → `currentProgress.finished = nil`; then the shared bookkeeping below.
- Shared bookkeeping for a pieced project, called from both paths (change the existing `apply` so that, when `project.isPieced`, it does this instead of setting `project.finished` from `step.finished`): mirror `project.cursor` into the current `PieceProgress`; set its `finished` from `step.finished` (and clear it on back/jump away from the end, as the chart path already does for the project); recompute `project.finished` with `updateProjectFinished(_:)`: finished when every piece copy (count `piecesTotal`) has a finished `PieceProgress` **and** `assemblyDone.count == assemblyTotal`, else nil. Record the `ProgressEvent` with `piece: project.currentPiece, copy: project.currentCopy`. A single-chart project (`!project.isPieced`) takes today's code path unchanged.
- `finishPiece`: set the current `PieceProgress.finished = now()`, `updateProjectFinished`, save, `onProjectsChanged?()`.
- `setAssemblyStep`: insert or remove the index in `assemblyDone` (sorted, unique), `updateProjectFinished`, save, `onProjectsChanged?()`.
- `nextUnfinished(after:manifest:)`: walk `manifest.pieces` in order, each copy `1...make`, return the first key whose `PieceProgress` is missing or unfinished and is not the current key.
- `statuses(for:manifest:)`: for each piece and copy in manifest order, the line per the rule above; for a started chart piece `"Row \(cursor.row) of \(sequence.passes.count)"` (load the chart's sequence once per chart id; on failure use `"Chart missing"`), for a started written piece `WrittenSequence.totalRows.map { "Row \(r) of \($0)" } ?? "Row \(r)"`.
- `progressLine`: `"\(pieceTitle) · \(rowPart) · \(done) of \(project.piecesTotal) pieces"` where `rowPart` is `"Row r of N"` (chart: `sequence.passes.count`; written closed: `totalRows`) or `"Row r"` (open), and `done` counts finished `PieceProgress`. Finished project: `"Finished"`.
- `currentPercent`: chart → cells before over total cells, rounded to a tenth as `AppModel.snapshot` does; written closed → `ProjectPace.pieceSummary(...).percent`; open → nil.
- `exportPiecedDocument`: build `ProjectProgressDocument` from the project, its `PieceProgress` (records with `docID`, cursor, finished), `current`, `assemblyDone`, and the events fetched with piece/copy (`PiecedEventRecord`); `exportDocument(for:)` keeps its signature and type for a single-chart project; callers that export (grep `exportDocument(`) branch on `project.isPieced` and encode `exportPiecedDocument` instead.
- `delete(_:)`: also delete the project's `PieceProgress` (`context.delete(model: PieceProgress.self, where: …)`).

In `AppModel`: pass `rows` to `ProjectService`; add `func startPiecedProject(manifest:title:) async throws` mirroring `startProject` (then `tab = .projects`).

- [ ] **Step 4: Run to verify**

Run the Step 2 command → PASS; then `-only-testing:GraphghanTests/ProjectServiceTests` → PASS unchanged; then `mise run test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: start, switch and work the pieces of a pieced project (#206)"
```

---

### Task 9: Starting a pieced pattern and the project screen

**Files:**
- Modify: `ios/Graphghan/Patterns/StartProjectSheet.swift`, `ios/Graphghan/Projects/ProjectDetailView.swift`
- Create: `ios/Graphghan/Projects/PieceListSection.swift`
- Test: `ios/Tests/ProjectDetailViewTests.swift` (+ snapshot `project-pieces.png`)

**Interfaces:**
- Consumes: Task 8's `ProjectService` API; Task 4's `ManifestPiece`, `AssemblyStep`.
- Produces: `struct PieceListSection: View { statuses: [PieceStatus]; assembly: [AssemblyStep]; assemblyDone: [Int]; onSelect: (PieceKey) -> Void; onToggleStep: (Int, Bool) -> Void }` (stateless, snapshot-able); `static func pageText(_ pages: [Int]) -> String`.

- [ ] **Step 1: Write the failing test**

Append to `ProjectDetailViewTests` (it already renders views with `Snapshots.assert`; copy a neighbour's setup):

```swift
    @Test @MainActor func pieceListSnapshot() throws {
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: TestFixtures.pieces("pattern.json"))
        let pieces = manifest.pieces!
        let statuses = [
            PieceStatus(piece: pieces[0], copy: 1, isWritten: false, line: "Row 3 of 5", finished: false, isCurrent: true),
            PieceStatus(piece: pieces[1], copy: 1, isWritten: true, line: "Done", finished: true, isCurrent: false),
            PieceStatus(piece: pieces[2], copy: 1, isWritten: true, line: "Row 2 of 3", finished: false, isCurrent: false),
            PieceStatus(piece: pieces[2], copy: 2, isWritten: true, line: "3 rows", finished: false, isCurrent: false),
            PieceStatus(piece: pieces[3], copy: 1, isWritten: true, line: "Open-ended", finished: false, isCurrent: false),
        ]
        let view = List { PieceListSection(statuses: statuses, assembly: manifest.assembly, assemblyDone: [0], onSelect: { _ in }, onToggleStep: { _, _ in }) }
        #expect(try Snapshots.assert(view, named: "project-pieces", size: CGSize(width: 390, height: 700)))
    }

    @Test func pagesReadAsTheOriginalPDFsPages() {
        #expect(PieceListSection.pageText([15]) == "page 15 of the original PDF")
        #expect(PieceListSection.pageText([4, 5]) == "pages 4–5 of the original PDF")
        #expect(PieceListSection.pageText([3, 7]) == "pages 3, 7 of the original PDF")
        #expect(PieceListSection.pageText([]) == "")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `mise run generate`, then `-only-testing:GraphghanTests/ProjectDetailViewTests`.
Expected: FAIL to compile — `cannot find 'PieceListSection' in scope`.

- [ ] **Step 3: Implement**

`PieceListSection.swift`:

```swift
import SwiftUI
import GraphghanCore

/// A pieced project's pieces in the pattern's order, then its assembly steps (spec 2026-09-25 §6.2).
struct PieceListSection: View {
    let statuses: [PieceStatus]
    let assembly: [AssemblyStep]
    let assemblyDone: [Int]
    let onSelect: (PieceKey) -> Void
    let onToggleStep: (Int, Bool) -> Void

    var body: some View {
        Section("Pieces") {
            ForEach(statuses) { s in
                Button { onSelect(s.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: s.finished ? "checkmark.circle.fill" : (s.isCurrent ? "play.circle.fill" : "circle"))
                            .foregroundStyle(s.finished || s.isCurrent ? Color.heather : Color.ink2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(s)).font(Font.Heather.body).foregroundStyle(Color.ink)
                            Text(s.isWritten ? "Written rows" : "Chart").font(Font.Heather.caption).foregroundStyle(Color.ink2)
                        }
                        Spacer()
                        Text(s.line).font(Font.Heather.caption).foregroundStyle(Color.ink2).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(s.finished ? "Finished" : "Work this piece")
            }
        }
        if !assembly.isEmpty {
            Section("Assembly · \(assemblyDone.count) of \(assembly.count)") {
                ForEach(Array(assembly.enumerated()), id: \.offset) { i, step in
                    Toggle(isOn: Binding(get: { assemblyDone.contains(i) }, set: { onToggleStep(i, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(Font.Heather.body).foregroundStyle(Color.ink)
                            if let text = step.text { Text(text).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                            if !step.pages.isEmpty { Text(Self.pageText(step.pages)).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                        }
                    }
                    .tint(.heather)
                }
            }
        }
    }

    private func title(_ s: PieceStatus) -> String {
        s.piece.make > 1 ? "\(s.piece.title) \(s.copy) of \(s.piece.make)" : s.piece.title
    }

    /// Where the source PDF is not on this phone (always, until the importer keeps it, spec §5.5).
    static func pageText(_ pages: [Int]) -> String {
        guard let first = pages.first else { return "" }
        if pages.count == 1 { return "page \(first) of the original PDF" }
        let consecutive = zip(pages, pages.dropFirst()).allSatisfy { $1 == $0 + 1 }
        let list = consecutive ? "\(first)–\(pages.last!)" : pages.map(String.init).joined(separator: ", ")
        return "pages \(list) of the original PDF"
    }
}
```

`ProjectDetailView.swift`:
- Add `@State private var statuses: [PieceStatus] = []`.
- In `load()`, when `project.isPieced` and the manifest loaded: `statuses = await model.projects.statuses(for: project, manifest: manifest)`; also refresh `statuses` in the existing summary-refresh task (same trigger) for a pieced project.
- In the body, before the existing `if let sequence, let summary` branch, add a pieced branch:

```swift
            if project.isPieced, let manifest {
                PieceListSection(statuses: statuses, assembly: manifest.assembly, assemblyDone: project.assemblyDone,
                                 onSelect: { key in
                                     Task {
                                         try? await model.projects.selectPiece(key, of: project, manifest: manifest)
                                         model.workingProject = project
                                     }
                                 },
                                 onToggleStep: { i, on in try? model.projects.setAssemblyStep(i, done: on, for: project) })
                Section("Notes") { /* the existing notes TextField, moved into a shared private view so both branches use it */ }
                Section { /* the existing Delete button (and Mark finished/unfinished) */ }
            } else if let sequence, let summary {
```

  Factor the existing Notes section and the finish/delete section into two private computed views (`notesSection`, `manageSection`) and use them in both branches — no duplicated view code. The single-chart branch stays exactly as it renders today.
- The `load()` path must not show "Chart missing" for a pieced project whose current piece is written: skip `sequence(for:)` when `project.isPieced`.

`StartProjectSheet.swift`: when `manifest.isPieced`, replace the "Chart" picker section with a "Pieces" section listing each piece's title (and "× make" when > 1), and make Start call `model.startPiecedProject(manifest: manifest, title: title)`; the Start button's `disabled` condition is `starting` alone for a pieced manifest.

- [ ] **Step 4: Run to verify**

Run the Step 2 command twice (the snapshot records, then compares); look at `project-pieces.png` (Read the PNG) and describe it in the report: the Panel row marked current, the Strip marked done, "Fin 1 of 2" / "Fin 2 of 2", "Open-ended" on the Strap, and the Assembly section with one step ticked and "page 3 of the original PDF". Then `mise run test`: every existing `ProjectDetailViewTests` snapshot compares unchanged.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: start a pieced pattern; the project screen lists its pieces and assembly (#206)"
```

---

### Task 10: The written-piece Work screen and finishing

**Files:**
- Create: `ios/Graphghan/Work/WrittenWorkScreen.swift`, `ios/Tests/WrittenWorkScreenTests.swift`
- Modify: `ios/Graphghan/Work/WorkView.swift`

**Interfaces:**
- Consumes: Task 8's `work(for:)`, `apply(_:to:work:)`, `finishPiece`, `nextUnfinished`, `selectPiece`; Task 5's `WrittenSequence`, `WrittenPass`.
- Produces: `struct WrittenWorkScreen: View { title: String; sequence: WrittenSequence; cursor: Cursor; finished: Bool; next: String?; onDone; onBack; onClose; onJump; onFinishPiece; onNext }` (stateless, snapshot-able).

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/WrittenWorkScreenTests.swift`:

```swift
import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WrittenWorkScreenTests {
    static let phone = CGSize(width: 390, height: 844)
    static let strip = try! WrittenSequence(RowsDocument.load(TestFixtures.pieces("pieces/strip.rows.json")))
    static let strap = try! WrittenSequence(RowsDocument.load(TestFixtures.pieces("pieces/strap.rows.json")))

    private func screen(_ seq: WrittenSequence, row: Int, title: String, finished: Bool = false, next: String? = nil) -> some View {
        WrittenWorkScreen(title: title, sequence: seq, cursor: Cursor(row: row, run: 0), finished: finished, next: next,
                          onDone: {}, onBack: {}, onClose: {}, onJump: {}, onFinishPiece: {}, onNext: {})
    }

    @Test func aRowInARange() throws {
        #expect(try Snapshots.assert(screen(Self.strip, row: 3, title: "Strip"), named: "written-work", size: Self.phone))
    }

    /// Review focus 3: no total, no "of", and a Finish piece action.
    @Test func anOpenEndedRow() throws {
        #expect(try Snapshots.assert(screen(Self.strap, row: 57, title: "Strap"), named: "written-work-open", size: Self.phone))
    }

    @Test func aFinishedPieceOffersTheNext() throws {
        #expect(try Snapshots.assert(screen(Self.strip, row: 5, title: "Strip", finished: true, next: "Fin 1 of 2"),
                                     named: "written-work-finished", size: Self.phone))
    }

    @Test func headerText() {
        #expect(WrittenWorkScreen.rowText(row: 31, total: 104) == "Row 31 of 104")
        #expect(WrittenWorkScreen.rowText(row: 57, total: nil) == "Row 57")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `mise run generate`, then `-only-testing:GraphghanTests/WrittenWorkScreenTests`.
Expected: FAIL to compile — `cannot find 'WrittenWorkScreen' in scope`.

- [ ] **Step 3: Implement**

`WrittenWorkScreen.swift` — layout in the Work screen's idiom (read `WorkScreen.swift` first and reuse its fonts, colours, `capsuleGlass`, the Back button and the header's close button exactly):
- Header: close button, `Self.rowText(row:total:)` in `Font.Heather.rowNumber` (tap-and-hold → `onJump`, as the chart screen's header), the piece title under it in `Font.Heather.caption`.
- Body, in a `Card`-like panel on `Color.panel`: the pass's `label` ("R 2 - R 4 (2 of 3)") in `Font.Heather.label`, the `text` large (`Font.Heather.heading`, no line limit, scrolls if long), and when `count` is present a badge "6 sts" in the style of the chart screen's `sc` badge.
- Finished state: the panel reads "\(title) done" and, when `next` is set, a primary button "Next: \(next)" → `onNext`; otherwise a "Close" button → `onClose`.
- Bar: Back capsule and a Done capsule (checkmark) as on the chart screen; for an open-ended sequence add a secondary "Finish piece" button above the bar → `onFinishPiece`. No strip.
- `static func rowText(row: Int, total: Int?) -> String { total.map { "Row \(row) of \($0)" } ?? "Row \(row)" }`.
- Accessibility: the panel is one element whose label is the row text and the pass text; Done's label is "Done, next row".

`WorkView.swift`:
- Add `@State private var work: PieceWork?`, `@State private var manifest: PatternManifest?`, `@State private var pieceFinished = false`, `@State private var nextTitle: String?`.
- In `.task`: when `project.isPieced`, load `manifest = try await model.manifest(for: project.patternID, path: nil)`, then `work = try await model.projects.work(for: project)`; for `.chart(c, s)` also set `chart = c; sequence = s` so the chart path renders as today (and the Live Activity starts as today); for `.written` do **not** start a Live Activity (its state is run-based; #223).
- In `body`, before the chart branch: `if case .written(let seq)? = work { writtenContent(seq) }`.
- `writtenContent`: `WrittenWorkScreen(title: currentTitle, sequence: seq, cursor: cursor, finished: pieceFinished, next: nextTitle, onDone: { performWritten(.advance) }, onBack: { performWritten(.back) }, onClose: { dismiss() }, onJump: { showJump = true }, onFinishPiece: { try? model.projects.finishPiece(project); refreshFinished() }, onNext: { Task { await goToNext() } })`, with the same back-swipe gesture and a `JumpToRowSheet(rowCount: seq.totalRows ?? max(cursor.row + 50, 100), current: cursor.row)` (an open piece allows jumping ahead).
- `performWritten(_ action:)`: `model.projects.apply(action, to: project, work: .written(seq))`, animate `cursor`, then `refreshFinished()`.
- `refreshFinished()`: `pieceFinished` from the current `PieceProgress`; `nextTitle` from `nextUnfinished(after:manifest:)` formatted as the piece title (with "n of make" when `make > 1`).
- `goToNext()`: `selectPiece(next)`, reload `work` (and `chart`/`sequence` for a chart piece), `cursor = project.cursor`, `pieceFinished = false`.
- For a **chart** piece of a pieced project the finished state should offer the next piece too: when `WorkEngine.isFinished(cursor, in: sequence)` and `project.isPieced`, overlay a "Next: \(nextTitle)" button above the bar (same style as the written screen's) that calls `goToNext()`.
- The current piece's title: `manifest?.pieces?.first { $0.id == project.currentPiece }?.title ?? project.title`.

- [ ] **Step 4: Run to verify**

Run the Step 2 command twice (the three snapshots record, then compare). Look at each PNG and describe it in the report: `written-work` shows "Row 3 of 5", "Strip", "R 2 - R 4 (2 of 3)", the row text and "6 sts"; `written-work-open` shows "Row 57" with no "of", "2. (56)", and a "Finish piece" button; `written-work-finished` shows "Strip done" and "Next: Fin 1 of 2". Then `mise run test`: every existing `work-*` snapshot compares unchanged.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: work a written piece row by row, and go on to the next piece (#206)"
```

---

### Task 11: Progress figures, Shortcuts and the Live Activity for pieced projects

**Files:**
- Modify: `ios/Graphghan/Projects/ProjectRow.swift`, `ios/Shared/WorkIntents.swift`, `ios/Graphghan/AppModel.swift`, `ios/Graphghan/Intents/ProjectEntity.swift`, `ios/Graphghan/Intents/WorkIntentDialog.swift`, `ios/Graphghan/Intents/WorkSnippetView.swift`, `ios/Packages/GraphghanCore/Sources/GraphghanCore/LiveActivityState.swift`
- Test: `ios/Tests/AppModelTests.swift`, `ios/Tests/WorkIntentDialogTests.swift`, `ios/Tests/ProjectEntityTests.swift`, `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/LiveActivityStateTests.swift`

**Interfaces:**
- Consumes: Task 8's `progressLine`, `currentPercent`, `work(for:)`, `apply(_:to:work:)`.
- Produces:
  - `ProjectSnapshot.detail: String?` — the pieced progress line; nil for a single-chart project (it is in `Shared/`, so it must stay a plain value)
  - `WorkIntentOutcome.movedWritten(title: String, row: Int, total: Int?, finished: Bool)`
  - `LiveActivityState.info(projectID:chart:sequence:title:)` — `title: String? = nil` overrides `chart.title`

- [ ] **Step 1: Write the failing tests**

In `AppModelTests` add (using its existing in-memory `AppModel` builder; import the pieces-basic bundle through `BundleImporter` first, then `startPiecedProject`):

```swift
    @Test @MainActor func aPiecedSnapshotReadsTheCurrentPiece() async throws {
        let (model, project) = try await Self.piecedProject()   // imports pieces-basic, starts it, Done four times: panel row 3, run 0
        let s = await model.snapshot(for: project)
        #expect(s.detail == "Panel · Row 3 of 5 · 0 of 5 pieces")
        #expect(abs(s.percent - 33.3) < 0.001)   // 8 of 24 cells: rows 1-2 of the panel (3 + 5)
    }

    /// Review focus 4.
    @Test @MainActor func snapshotOfASingleChartProjectIsUnchanged() async throws {
        let (model, project) = try await Self.singleChartProject()   // the existing helper this suite uses
        #expect(await model.snapshot(for: project).detail == nil)
    }

    @Test @MainActor func aShortcutsDoneOnAWrittenPieceMovesOneRow() async throws {
        let (model, project) = try await Self.piecedProject()
        let manifest = try await model.manifest(for: project.patternID, path: nil)
        try await model.projects.selectPiece(PieceKey(piece: "strip", copy: 1), of: project, manifest: manifest)
        let outcome = await model.performIntent(.advance, chosen: project.id)
        #expect(outcome == .movedWritten(title: "Strip", row: 2, total: 5, finished: false))
    }
```

(Each of the panel's first two rows is one run, so four Dones reach row 3, run 0: run, turn, run, turn. The expected percent is `cellsBefore(row 3, run 0) = 3 + 5 = 8` over 24 → 33.3.)

In `WorkIntentDialogTests`:

```swift
    @Test func aWrittenStepSaysThePieceAndRow() {
        #expect(WorkIntentDialog.plain(.movedWritten(title: "Strip", row: 2, total: 5, finished: false)) == "Strip, row 2 of 5.")
        #expect(WorkIntentDialog.plain(.movedWritten(title: "Strap", row: 58, total: nil, finished: false)) == "Strap, row 58.")
        #expect(WorkIntentDialog.plain(.movedWritten(title: "Strip", row: 5, total: 5, finished: true)) == "That's the last row of Strip.")
    }
```

If the test file reads dialog text through another helper (e.g. a `String(localized:)` rendering of `text(for:)`), use that helper instead of `plain` and add `plain` only if no such helper exists: `static func plain(_ outcome: WorkIntentOutcome) -> String` returning the same words `text(for:)` builds.

In `ProjectEntityTests`:

```swift
    @Test func aPiecedEntityShowsItsDetail() {
        let snap = ProjectSnapshot(id: UUID(), title: "Orca", patternTitle: "Orca Crossbody Bag", percent: 54.5, lastWorked: nil,
                                   isFinished: false, detail: "Front panel · Row 42 of 77 · 3 of 8 pieces")
        #expect(ProjectEntity.subtitle(for: snap) == "Front panel · Row 42 of 77 · 3 of 8 pieces")
        let single = ProjectSnapshot(id: UUID(), title: "Blanket", patternTitle: "Craigh na Dun", percent: 12, lastWorked: nil, isFinished: false, detail: nil)
        #expect(ProjectEntity.subtitle(for: single) == "12% · Craigh na Dun")
    }
```

In `LiveActivityStateTests`:

```swift
    @Test func aTitleOverridesTheChartsTitle() throws {
        let chart = try Chart.load(Fixtures.data("shaped-basic.chart.json"))
        let seq = try WorkSequence(chart: chart)
        #expect(LiveActivityState.info(projectID: UUID(), chart: chart, sequence: seq, title: "Pieces basic · Panel").title == "Pieces basic · Panel")
        #expect(LiveActivityState.info(projectID: UUID(), chart: chart, sequence: seq).title == chart.title)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet --filter LiveActivityStateTests`, and from `ios/` the xcodebuild test command with `-only-testing:GraphghanTests/AppModelTests -only-testing:GraphghanTests/WorkIntentDialogTests -only-testing:GraphghanTests/ProjectEntityTests`.
Expected: FAIL to compile — `extra argument 'title' in call`, `extra argument 'detail' in call`, `type 'WorkIntentOutcome' has no member 'movedWritten'`.

- [ ] **Step 3: Implement**

- `LiveActivityState.info`: add `title: String? = nil`; use `title ?? chart.title`.
- `ProjectSnapshot` (Shared): add `let detail: String?` after `isFinished`, with a doc comment ("a pieced project's line, 'Front panel · Row 42 of 77 · 3 of 8 pieces'; nil for a single chart"). Update every `ProjectSnapshot(` initializer call (grep in the app, `Shared/`, the widget and tests) to pass `detail:` — nil where it is built for a single-chart project.
- `WorkIntentOutcome`: add `case movedWritten(title: String, row: Int, total: Int?, finished: Bool)`; if it conforms to `Equatable` through synthesis, the new case keeps that.
- `AppModel.snapshot(for:sequence:)`: for `project.isPieced`, load the manifest (local first, as today) and `work(for:)`; `percent` = `projects.currentPercent(for:work:) ?? 0`; `detail` = `projects.progressLine(for:manifest:work:)`. A single-chart project takes today's code and passes `detail: nil`. `snapshot(for:)` must not call `sequence(for:)` for a pieced project whose current piece is written (it has no chart).
- `AppModel.performIntent`: after resolving the project, if `project.isPieced && project.currentIsWritten`: `work(for:)`, `projects.apply(action, to:work:)`; nil → `.nowhereToGo(action)`; else `.movedWritten(title: <current piece title>, row: step.cursor.row, total: seq.totalRows, finished: step.finished)`. No Live Activity work on this path. The chart-piece path stays today's, but when `project.isPieced` pass `title: "\(patternTitle) · \(pieceTitle)"` wherever `LiveActivityState.info` is built for it (`onApply`, `activityState(for:)`, `adoptActivity`), so the lock screen names the piece.
- `WorkIntentDialog.text(for:)`: `.movedWritten` → `finished ? "That's the last row of \(title)." : total.map { "\(title), row \(row) of \($0)." } ?? "\(title), row \(row)."`. Also replace "The blanket is done." in the chart step's finished text with "That's the last one. It's done." only if no existing test pins the old words; if one does, leave it (and note it in the report).
- `WorkSnippetView`: a `.movedWritten` outcome shows the same sentence as the dialog in the snippet's text style, no band.
- `ProjectEntity`: add `static func subtitle(for snapshot: ProjectSnapshot) -> String` = `snapshot.detail ?? "\(percentText(snapshot.percent)) · \(snapshot.patternTitle)"`, keep the entity's stored properties, add a stored `detail: String?` copied from the snapshot, and build `displayRepresentation` from `subtitle(for:)`'s rule.
- `ProjectRow`: for `project.isPieced`, load `work` and the manifest in the row's task instead of `sequence`; `line` = `progressLine(...)` (or "Finished"); `percent` = `currentPercent(...)` (nil → no progress bar, which `ProjectCardView` already handles); no estimate for a pieced project in this PR (Pace is per chart). A single-chart project renders exactly as today.

- [ ] **Step 4: Run to verify**

Run the Step 2 commands → PASS; then `cd ios/Packages/GraphghanCore && swift test --quiet` and `mise run test` (the widget target builds as part of the scheme: `Shared/` still compiles there).

- [ ] **Step 5: Commit**

```bash
git add ios
git commit -m "ios: a pieced project's line, percent, Shortcuts steps and Live Activity title (#206)"
```

---

### Task 12: Verify everything and open the PR

**Files:** none new.

- [ ] **Step 1: Run every suite**

From the repo root: `uv run pytest -q` and `mise run lint`. From `ios/`: `mise run core-test`, `mise run prose-test`, `mise run test` (capture the exit code: `…; echo "exit $?"` — zsh's `PIPESTATUS` is lowercase).

- [ ] **Step 2: Check the invariants**

- `git diff origin/main --stat -- fixtures/bundle/craigh-na-dun.graphghan fixtures/chart-format/*.chart.json fixtures/chart-format/*.sequence.json fixtures/chart-format/progress-*` is empty (no existing fixture moved).
- `git diff origin/main -- ios/Tests/__Snapshots__ --stat` lists only added PNGs (`project-pieces`, `written-work`, `written-work-open`, `written-work-finished`).

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin HEAD
gh pr create --title "Patterns made of pieces: manifest 2, written rows, progress 2 (#206)" --body-file <file>
```

The body: "Refs #206 and #37 (PR 2 of `docs/superpowers/specs/2026-09-25-pieces-and-shaped-rows-design.md` §8; #206 stays open for the importer PR)", a What changes list (format: rows document, manifest 2, progress 2 with the two rules this PR settles; Python reference; GraphghanCore; the app: pieced projects, the piece list and assembly, the written-piece Work screen, finishing and next piece, progress line, Shortcuts, Live Activity title), the Tests section with each suite's real numbers and the four new snapshots, and Follow-ons: #223 (Live Activity for a written piece), #220, #222. End with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 4: See it to green**

Watch CI and CodeRabbit with a bounded watcher (at most 20 minutes, polling `gh pr checks <n>` every 30 s, stop once nothing is pending). Fix every valid CodeRabbit finding; when a stale "changes requested" review's findings are fixed and the re-review is rate-limited, dismiss it naming the fixing commit.
