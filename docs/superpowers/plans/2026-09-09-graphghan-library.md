# Graphghan Library, CLI, and Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `~/Projects/outlander-blanket` into the `graphghan` package with a CLI, a first pattern (`craigh-na-dun`) with committed build output, tests, and CI, so the site and skill plans can build on fixed contracts.

**Architecture:** src-layout Python package (`src/graphghan`) with inch-based geometry (`grid.py`), a per-pattern palette (`palette.py`), motif modules, frame/compose helpers, export/validate, and an argparse CLI. Patterns live in `patterns/<slug>/` as `pattern.toml` + `design.py` + tests + committed `dist/`. CI runs ruff, pytest, a drift check, and the site build.

**Tech Stack:** Python 3.12+, uv, hatchling, numpy, pillow, pytest, ruff, GitHub Actions. No Node.

**Spec:** `docs/superpowers/specs/2026-09-09-graphghan-design.md`

## Global Constraints

- Python `>=3.12`; run everything with `uv run ...` from the repo root (`~/Projects/graphghan`).
- Dependencies: `pillow>=10`, `numpy>=1.26`; dev: `pytest>=8`, `ruff>=0.6`. Nothing else.
- Package name `graphghan`; console script `graphghan`; src layout `src/graphghan/`.
- `patterns/<slug>/dist/` is committed and must be reproducible: `graphghan render <slug> --check` exits 1 on drift.
- Row lists in `chart.json` are top-to-bottom; pattern row 1 is the last entry. Schema field `"schema": 1`.
- Default gauges (stitches/in, rows/in): `sc = (3.5, 4.0)`, `hdc = (3.25, 2.5)`, `dc = (3.0, 1.625)`.
- Commit after every task with the attribution trailer:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01W4MmgYzfdwasS3YkdiwPWe`.
- The old project is read-only source material at `~/Projects/outlander-blanket` (call it `OLD`). Copy from it; never edit it.

---

## File structure

| path | responsibility |
|---|---|
| `pyproject.toml` | package metadata, console script, pytest/ruff config |
| `src/graphghan/__init__.py` | version, re-exports `Grid`, `set_gauge` |
| `src/graphghan/grid.py` | gauge registry, `Grid`, inch-space masks, `weave` |
| `src/graphghan/palette.py` | `Color`, `Palette`, `load()` from `pattern.toml` |
| `src/graphghan/pattern.py` | `PatternMeta`, `load_pattern`, `load_design`, `find_repo_root` |
| `src/graphghan/text.py` | `text_line` (aspect-corrected TTF rendering) |
| `src/graphghan/motifs/{plaid,twist,knots,rings,thistle,dragonfly,stones,bands}.py` | one motif family each, explicit color indices |
| `src/graphghan/motifs/__init__.py` | `CATALOG` registry for thumbnails |
| `src/graphghan/frame.py` | `twist_frame`, `link_frame` |
| `src/graphghan/compose.py` | `text_block` |
| `src/graphghan/export.py` | RLE, PNGs, stats, written rows, `chart_json` |
| `src/graphghan/validate.py` | generic invariants + reports |
| `src/graphghan/options_page.py` | comparison page HTML for `graphghan options` |
| `src/graphghan/cli.py` | commands: new, options, render, check, catalog, site |
| `src/graphghan/templates/` | `pattern.toml.tmpl`, `design.py.tmpl`, `test_design.py.tmpl` |
| `patterns/craigh-na-dun/` | the first pattern |
| `examples/outlander_studies.py` | option studies as motif examples |
| `tests/` | library tests |
| `.github/workflows/ci.yml` | CI + Pages deploy |

---

### Task 1: Repository scaffold

**Files:**
- Create: `pyproject.toml`, `.gitignore`, `.python-version`, `LICENSE`, `PATTERNS-LICENSE.md`, `README.md`, `src/graphghan/__init__.py`, `tests/test_package.py`

**Interfaces:**
- Produces: importable package `graphghan` with `__version__ = "0.1.0"`.

- [ ] **Step 1: Write the failing test**

`tests/test_package.py`:
```python
import graphghan


def test_version():
    assert graphghan.__version__ == "0.1.0"
```

- [ ] **Step 2: Create project files**

`pyproject.toml`:
```toml
[project]
name = "graphghan"
version = "0.1.0"
description = "Chart generator, viewer, and Claude skill for graphghan and other pixel-chart crafts"
readme = "README.md"
requires-python = ">=3.12"
license = {text = "MIT"}
dependencies = ["pillow>=10", "numpy>=1.26"]

[project.scripts]
graphghan = "graphghan.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/graphghan"]

[dependency-groups]
dev = ["pytest>=8", "ruff>=0.6"]

[tool.pytest.ini_options]
testpaths = ["tests", "patterns", "site/tests"]

[tool.ruff]
line-length = 110
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "B"]
ignore = ["E501"]
```

`.gitignore`:
```
.venv/
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
patterns/*/build/
site/dist/
```

`.python-version`: `3.12`

`LICENSE`: the MIT license text with `Copyright (c) 2026 Tyler Vick`.

`PATTERNS-LICENSE.md`:
```markdown
Pattern designs under `patterns/` are licensed CC BY-NC-SA 4.0
(https://creativecommons.org/licenses/by-nc-sa/4.0/). The code is MIT (see LICENSE).
Lettering fonts under `fonts/` and `site/src/fonts/` are under the SIL Open Font License.
```

`README.md` (stub, expanded in Task 12):
```markdown
# graphghan

Chart generator, offline viewer, and Claude skill for graphghan (pixel) crochet blankets.
See `docs/superpowers/specs/2026-09-09-graphghan-design.md`.
```

`src/graphghan/__init__.py`:
```python
"""graphghan: charts for pixel-chart crafts, drawn in inches and rasterized to any gauge."""

__version__ = "0.1.0"
```

- [ ] **Step 3: Install and run the test**

Run: `uv sync && uv run pytest tests/test_package.py -v`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: scaffold graphghan package"
```

---

### Task 2: Gauge and grid

**Files:**
- Create: `src/graphghan/grid.py` (from `OLD/outlander/grid.py`), `tests/test_grid.py`

**Interfaces:**
- Produces:
  - `GAUGES: dict[str, tuple[float, float]]`, `set_gauge(name_or_pair)`, `register_gauge(name, st_per_in, rows_per_in)`, `current_gauge() -> tuple[float, float]`
  - module globals `ST_PER_IN, ROWS_PER_IN, SW, SH` (inches per column/row), `cols(inches) -> int`, `rows(inches) -> int`
  - `class Grid(w, h, fill)` with `.a` (uint8 `[h, w]`), `.rect(x0, y0, x1, y1, c)`, `.blit(arr, x0, y0, transparent=None)`
  - masks (all return bool arrays `[h, w]`, centers in cell units, sizes in inches): `ellipse_ring(w,h,cx,cy,a_in,b_in,a_out,b_out)`, `circle_ring(w,h,cx,cy,r_in,r_out)`, `square_ring`, `diamond_ring`, `ellipse_fill(w,h,cx,cy,a,b,theta_deg=0)`, `stadium_ring(w,h,cx,cy,half_len,r_in,r_out,vertical=False)`, `segment_band(w,h,p0,p1,half_width_in)`, `curve_mask(w,h,pts,radius_cells)`, `curve_mask_in(w,h,pts,radius_in,sx,sy)`
  - `dilate(mask)`, `weave(mask_a, mask_b, windows) -> (a, b, found)`, `sector_windows(w,h,cx,cy,n,start_deg=0,a_first=True)`

- [ ] **Step 1: Write the failing tests**

`tests/test_grid.py`:
```python
import numpy as np
import pytest

from graphghan import grid as gr


@pytest.fixture(autouse=True)
def reset_gauge():
    gr.set_gauge("sc")
    yield
    gr.set_gauge("sc")


def test_default_gauge_and_conversions():
    assert gr.current_gauge() == (3.5, 4.0)
    assert gr.cols(4.0) == 14 and gr.rows(4.0) == 16
    assert abs(gr.SW - 1 / 3.5) < 1e-9 and gr.SH == 0.25


def test_set_gauge_by_name_and_pair():
    gr.set_gauge("hdc")
    assert gr.current_gauge() == (3.25, 2.5) and gr.rows(4.0) == 10
    gr.set_gauge((4.0, 4.0))
    assert gr.cols(1.0) == 4 and gr.rows(1.0) == 4


def test_register_gauge():
    gr.register_gauge("bulky", 2.75, 3.0)
    gr.set_gauge("bulky")
    assert gr.current_gauge() == (2.75, 3.0)


def test_grid_rect_and_blit():
    g = gr.Grid(10, 6, 0)
    g.rect(1, 1, 4, 3, 2)
    assert g.a[1:3, 1:4].tolist() == [[2, 2, 2], [2, 2, 2]] and g.a.sum() == 12
    patch = np.array([[7, 0], [0, 7]], dtype=np.uint8)
    g.blit(patch, 8, 4, transparent=0)
    assert g.a[4, 8] == 7 and g.a[4, 9] == 0 and g.a[5, 9] == 7


def test_circle_ring_is_round_in_inches():
    # 2 in radius ring: ~7 columns wide, 8 rows tall in cells
    m = gr.circle_ring(40, 40, 19.5, 19.5, 1.7, 2.0)
    ys, xs = np.where(m)
    assert 13 <= xs.max() - xs.min() + 1 <= 15
    assert 15 <= ys.max() - ys.min() + 1 <= 17


def test_weave_cuts_under_strand_only_inside_window():
    a = np.zeros((7, 7), bool); a[3, :] = True          # horizontal bar
    b = np.zeros((7, 7), bool); b[:, 3] = True          # vertical bar
    win = np.ones((7, 7), bool)
    a2, b2, found = gr.weave(a, b, [(win, True)])
    assert found == 1
    assert a2.sum() == 7                                # over strand untouched
    assert not b2[2, 3] and not b2[4, 3] and b2[0, 3]   # under strand loses the cells touching the bar


def test_curve_mask_in_is_symmetric():
    pts = [(x, 5.0) for x in np.arange(-1, 21, 0.05)]
    m = gr.curve_mask_in(20, 11, pts, 0.3, gr.SW, gr.SH)
    assert np.array_equal(m, m[:, ::-1])
    assert m[5].all() and m[4].all() and not m[2].any()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/test_grid.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'graphghan.grid'`

- [ ] **Step 3: Create grid.py**

Copy `OLD/outlander/grid.py` to `src/graphghan/grid.py`, then replace its gauge block (the lines from `# design gauge` through the end of `set_gauge`) with:

```python
# gauge: stitches per inch, rows per inch (worsted + 5 mm defaults)
GAUGES: dict[str, tuple[float, float]] = {"sc": (3.5, 4.0), "hdc": (3.25, 2.5), "dc": (3.0, 1.625)}
ST_PER_IN = 3.5
ROWS_PER_IN = 4.0
SW = 1.0 / ST_PER_IN   # inches per column
SH = 1.0 / ROWS_PER_IN  # inches per row


def register_gauge(name: str, st_per_in: float, rows_per_in: float) -> None:
    GAUGES[name] = (float(st_per_in), float(rows_per_in))


def set_gauge(gauge) -> None:
    """Switch the working gauge by name or (st_per_in, rows_per_in). Every cols()/rows()/mask call reads it."""
    global ST_PER_IN, ROWS_PER_IN, SW, SH
    ST_PER_IN, ROWS_PER_IN = GAUGES[gauge] if isinstance(gauge, str) else (float(gauge[0]), float(gauge[1]))
    SW, SH = 1.0 / ST_PER_IN, 1.0 / ROWS_PER_IN


def current_gauge() -> tuple[float, float]:
    return ST_PER_IN, ROWS_PER_IN
```

Keep every other function from the old file unchanged (`cols`, `rows`, `Grid`, `inch_coords`, `ellipse_ring`, `circle_ring`, `square_ring`, `diamond_ring`, `dilate`, `weave`, `sector_windows`, `curve_mask`, `stadium_ring`, `ellipse_fill`, `curve_mask_in`, `segment_band`). Add to `src/graphghan/__init__.py`:

```python
from .grid import Grid, set_gauge, register_gauge, current_gauge, cols, rows  # noqa: F401
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/test_grid.py -v`
Expected: 7 PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: gauge registry and inch-space grid"
```

---

### Task 3: Palette and pattern metadata

**Files:**
- Create: `src/graphghan/palette.py`, `src/graphghan/pattern.py`, `tests/test_palette.py`, `tests/test_pattern.py`, `tests/fixtures/minimal/pattern.toml`, `tests/fixtures/minimal/design.py`

**Interfaces:**
- Produces:
  - `Color(code, name, rgb, yarn="", use="")` with `.hex`
  - `Palette(colors)`: `pal["C"] -> int`, `len(pal)`, `.codes: list[str]`, `.rgb: list[tuple]`, `.colors: list[Color]`, `.color(code) -> Color`, `Palette.from_toml(path)`, `palette.load(design_file) -> Palette`
  - `PatternMeta` dataclass: `slug, title, dedication, quote, version, stitch, size_in, hook, yarn_weight, first_row_color, gauges: dict[str, tuple[float,float]], palette: Palette, notes: dict[str, list[str]], dir: Path`
  - `load_pattern(pattern_dir) -> PatternMeta` (also registers the pattern's gauges), `load_design(pattern_dir) -> module`, `find_repo_root(start=None) -> Path`, `pattern_dir(slug) -> Path`

- [ ] **Step 1: Write the fixture pattern**

`tests/fixtures/minimal/pattern.toml`:
```toml
[pattern]
slug = "minimal"
title = "Minimal"
dedication = ""
quote = ""
version = "0.0.1"
stitch = "sc"
size_in = [4.0, 3.0]
hook = "5 mm"
yarn_weight = "worsted"
first_row_color = "A"

[gauge]
sc = [3.5, 4.0]
square = [4.0, 4.0]

[[colors]]
code = "A"
name = "Alpha"
hex = "#112233"
yarn = "any"
use = "ground"

[[colors]]
code = "B"
name = "Beta"
hex = "#ffffff"

[notes]
setup = ["Chain W + 1 in A."]
colors = []
```

`tests/fixtures/minimal/design.py`:
```python
from graphghan import Grid, grid as gr, palette

PAL = palette.load(__file__)
VARIANTS = {"final": {}}


def build(gauge_key="sc", variant="final"):
    gr.set_gauge(gauge_key)
    W, H = gr.cols(4.0), gr.rows(3.0)
    g = Grid(W, H, PAL["A"])
    g.rect(2, 2, W - 2, H - 2, PAL["B"])
    return g, {"panel": (2, 2, W - 2, H - 2)}
```

- [ ] **Step 2: Write the failing tests**

`tests/test_palette.py`:
```python
from pathlib import Path

from graphghan.palette import Color, Palette, load

FIX = Path(__file__).parent / "fixtures" / "minimal"


def test_color_hex():
    assert Color("A", "Alpha", (17, 34, 51)).hex == "#112233"


def test_palette_from_toml_orders_and_indexes():
    pal = Palette.from_toml(FIX / "pattern.toml")
    assert len(pal) == 2 and pal.codes == ["A", "B"]
    assert pal["A"] == 0 and pal["B"] == 1
    assert pal.rgb == [(17, 34, 51), (255, 255, 255)]
    assert pal.color("A").yarn == "any" and pal.color("B").use == ""


def test_load_from_design_file():
    pal = load(str(FIX / "design.py"))
    assert pal.codes == ["A", "B"]
```

`tests/test_pattern.py`:
```python
from pathlib import Path

from graphghan import grid as gr
from graphghan.pattern import find_repo_root, load_design, load_pattern

FIX = Path(__file__).parent / "fixtures" / "minimal"


def test_load_pattern_meta_and_gauges():
    meta = load_pattern(FIX)
    assert meta.slug == "minimal" and meta.title == "Minimal" and meta.version == "0.0.1"
    assert meta.size_in == (4.0, 3.0) and meta.first_row_color == "A"
    assert meta.gauges["square"] == (4.0, 4.0) and gr.GAUGES["square"] == (4.0, 4.0)
    assert meta.notes["setup"] == ["Chain W + 1 in A."]
    assert meta.palette.codes == ["A", "B"]


def test_load_design_builds():
    load_pattern(FIX)
    design = load_design(FIX)
    g, report = design.build("sc", "final")
    assert g.a.shape == (12, 14) and report["panel"] == (2, 2, 12, 10)
    assert design.VARIANTS == {"final": {}}


def test_find_repo_root():
    root = find_repo_root(Path(__file__))
    assert (root / "pyproject.toml").exists()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest tests/test_palette.py tests/test_pattern.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 4: Implement palette.py**

```python
"""Per-pattern palette: an ordered list of colors whose index is the cell value in the grid."""
from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Color:
    code: str
    name: str
    rgb: tuple[int, int, int]
    yarn: str = ""
    use: str = ""

    @property
    def hex(self) -> str:
        return "#%02x%02x%02x" % self.rgb


def parse_hex(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


class Palette:
    def __init__(self, colors: list[Color]):
        self.colors = list(colors)
        self._index = {c.code: i for i, c in enumerate(self.colors)}
        if len(self._index) != len(self.colors):
            raise ValueError("duplicate color codes in palette")

    def __getitem__(self, code: str) -> int:
        return self._index[code]

    def __len__(self) -> int:
        return len(self.colors)

    def __contains__(self, code: str) -> bool:
        return code in self._index

    @property
    def codes(self) -> list[str]:
        return [c.code for c in self.colors]

    @property
    def rgb(self) -> list[tuple[int, int, int]]:
        return [c.rgb for c in self.colors]

    @property
    def names(self) -> list[str]:
        return [c.name for c in self.colors]

    def color(self, code: str) -> Color:
        return self.colors[self._index[code]]

    @classmethod
    def from_toml(cls, path: str | Path) -> "Palette":
        data = tomllib.loads(Path(path).read_text())
        return cls([Color(c["code"], c["name"], parse_hex(c["hex"]), c.get("yarn", ""), c.get("use", ""))
                    for c in data["colors"]])


def load(design_file: str | Path) -> Palette:
    """Palette for the pattern whose design.py is `design_file` (pattern.toml sits beside it)."""
    return Palette.from_toml(Path(design_file).resolve().parent / "pattern.toml")
```

- [ ] **Step 5: Implement pattern.py**

```python
"""Pattern folders: pattern.toml metadata and design.py loading."""
from __future__ import annotations

import importlib.util
import tomllib
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType

from . import grid as gr
from .palette import Palette


@dataclass
class PatternMeta:
    slug: str
    title: str
    dedication: str
    quote: str
    version: str
    stitch: str
    size_in: tuple[float, float]
    hook: str
    yarn_weight: str
    first_row_color: str
    gauges: dict[str, tuple[float, float]]
    palette: Palette
    notes: dict[str, list[str]]
    dir: Path


def find_repo_root(start: str | Path | None = None) -> Path:
    p = Path(start or Path.cwd()).resolve()
    for cand in [p, *p.parents]:
        if (cand / "pyproject.toml").exists():
            return cand
    raise FileNotFoundError("no pyproject.toml found walking up from %s" % p)


def pattern_dir(slug: str, root: Path | None = None) -> Path:
    return (root or find_repo_root()) / "patterns" / slug


def load_pattern(pattern_dir: str | Path) -> PatternMeta:
    d = Path(pattern_dir).resolve()
    data = tomllib.loads((d / "pattern.toml").read_text())
    p = data["pattern"]
    gauges = {k: (float(v[0]), float(v[1])) for k, v in data.get("gauge", {}).items()}
    for name, (st, rows) in gauges.items():
        gr.register_gauge(name, st, rows)
    notes = {k: list(v) for k, v in data.get("notes", {}).items()}
    return PatternMeta(
        slug=p["slug"], title=p["title"], dedication=p.get("dedication", ""), quote=p.get("quote", ""),
        version=p["version"], stitch=p.get("stitch", "sc"), size_in=tuple(float(x) for x in p["size_in"]),
        hook=p.get("hook", ""), yarn_weight=p.get("yarn_weight", ""), first_row_color=p.get("first_row_color", ""),
        gauges=gauges, palette=Palette.from_toml(d / "pattern.toml"), notes=notes, dir=d,
    )


def load_design(pattern_dir: str | Path) -> ModuleType:
    d = Path(pattern_dir).resolve()
    spec = importlib.util.spec_from_file_location("design_%s" % d.name.replace("-", "_"), d / "design.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
```

- [ ] **Step 6: Run tests**

Run: `uv run pytest tests/test_palette.py tests/test_pattern.py -v`
Expected: 6 PASS

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: palette and pattern metadata loading"
```

---

### Task 4: Lettering

**Files:**
- Create: `src/graphghan/text.py`, `fonts/Metamorphous-Regular.ttf` (copy from `OLD/fonts/`), `fonts/OFL.txt`, `tests/test_text.py`

**Interfaces:**
- Produces: `text_line(text, size_rows, color, bg, font_path, threshold=0.5, bold=0.0) -> (arr uint8 [size_rows, w], ascent_rows, descent_rows)`; `FONT_METAMORPHOUS: Path` (repo `fonts/Metamorphous-Regular.ttf`, located relative to the package via `find_repo_root`).

- [ ] **Step 1: Write the failing tests**

`tests/test_text.py`:
```python
import numpy as np

from graphghan import grid as gr
from graphghan.text import FONT_METAMORPHOUS, text_line


def test_line_height_is_exact_and_glyphs_present():
    gr.set_gauge("sc")
    arr, asc, desc = text_line("Lord", 17, color=1, bg=0, font_path=FONT_METAMORPHOUS, bold=0.035, threshold=0.42)
    assert arr.shape[0] == 17 and asc + desc == 17 and 10 <= asc <= 15
    assert (arr == 1).sum() > 60 and arr[:, 0].any() and arr[:, -1].any()   # trimmed to ink


def test_width_follows_cell_aspect():
    gr.set_gauge("sc")
    w_sc = text_line("woman", 12, 1, 0, FONT_METAMORPHOUS)[0].shape[1]
    gr.set_gauge("hdc")
    w_hdc = text_line("woman", 12, 1, 0, FONT_METAMORPHOUS)[0].shape[1]
    gr.set_gauge("sc")
    # hdc rows are 1.68x taller than sc rows, so the same 12-row line is physically taller and wider
    assert w_hdc > w_sc * 1.4
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/test_text.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Implement text.py and vendor the font**

```bash
mkdir -p fonts && cp ~/Projects/outlander-blanket/fonts/Metamorphous-Regular.ttf fonts/
curl -sSL -o fonts/OFL.txt https://raw.githubusercontent.com/google/fonts/main/ofl/metamorphous/OFL.txt
```

`src/graphghan/text.py`:
```python
"""Lettering: render a TTF line so that its full line height spans N rows, with glyph widths
corrected for the cell aspect, at any gauge and any font."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import grid as gr
from .pattern import find_repo_root

FONT_METAMORPHOUS = find_repo_root(Path(__file__)) / "fonts" / "Metamorphous-Regular.ttf"


def text_line(text: str, size_rows: int, color: int, bg: int, font_path: str | Path,
              threshold: float = 0.5, bold: float = 0.0):
    """Returns (array, ascent_rows, descent_rows). Rendered at 8x and box-filtered down;
    `bold` is a stroke width as a fraction of the row size; `threshold` is the ink cutoff (0..1)."""
    big = ImageFont.truetype(str(font_path), size_rows * 8)
    asc_px, desc_px = big.getmetrics()
    line_px = asc_px + desc_px
    img = Image.new("L", (size_rows * 8 * max(1, len(text)) * 2 + 40, line_px), 0)
    ImageDraw.Draw(img).text((20, 0), text, font=big, fill=255,
                             stroke_width=int(round(bold * size_rows * 8)), stroke_fill=255)
    a = np.array(img)
    xs = np.where(a.max(axis=0) > 0)[0]
    img = img.crop((int(xs.min()), 0, int(xs.max()) + 1, line_px))
    scale = size_rows * gr.SH / line_px                   # inches per source pixel
    cols_out = max(1, int(round(img.width * scale / gr.SW)))
    small = img.resize((cols_out, size_rows), Image.BOX)
    m = np.array(small) >= int(255 * threshold)
    arr = np.full(m.shape, bg, dtype=np.uint8)
    arr[m] = color
    ascent = int(round(asc_px * size_rows / line_px))
    return arr, ascent, size_rows - ascent
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/test_text.py -v`
Expected: 2 PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: aspect-corrected lettering with vendored Metamorphous"
```

---

### Task 5: Motif modules

**Files:**
- Create: `src/graphghan/motifs/__init__.py`, `plaid.py`, `twist.py`, `knots.py`, `rings.py`, `thistle.py`, `dragonfly.py`, `stones.py`, `bands.py`, `tests/test_motifs.py`
- Source material: `OLD/outlander/motifs.py`

**Interfaces:**
- Produces (all arrays are uint8 palette indices; colors are explicit ints):
  - `plaid.plaid(w, h, phase_x, phase_y, colors: dict[str, int], sett=SETT_DEFAULT, priority=("Y","R","B","G"))`
  - `twist.twist_strip_in(length, thick, horizontal=True, period_in=4.0, amp_in=1.0, radius_in=0.3, bg=0, fg=1, fit=True) -> (arr, period_in)`
  - `knots.solomon_knot(w, h, bg, fg, half=2.4, r_out=1.05, stroke=0.6) -> (arr, found)`, `knots.corner_block(w, h, bg, fg, outline=2) -> (arr, found)`, `knots.woven_x_block(w, h, bg, fg, outline=2, bar_in=0.6) -> arr`
  - `rings.rings(bg, fg, r_in=1.1, r_out=1.75, gap_in=1.9) -> (arr, found)`
  - `thistle.thistle(bg, head, leaf)`, `thistle.thistle_small(bg, head, leaf)`, `thistle.thistle_scaled(height_in, bg, head, leaf)`, `thistle.bloom_icon(bg, head, calyx)`
  - `dragonfly.dragonfly(w, h, bg, body, wing_fill, wing_line, span=7.0)`, `dragonfly.amber_drop(w, h, bg, fill, line, a=4.3, b=4.9, edge=0.42)`
  - `stones.standing_stones(w, h, bg, hill, stone, moon)`
  - `bands.stripe_band(length, thick, seq: list[tuple[int, int]], horizontal=True)`
  - `motifs.CATALOG: list[tuple[str, callable]]` where each callable takes no args and returns `(arr, rgb_list)` for thumbnails.

- [ ] **Step 1: Write the failing tests**

`tests/test_motifs.py`:
```python
import numpy as np
import pytest

from graphghan import grid as gr
from graphghan.motifs import CATALOG, bands, dragonfly, knots, plaid, rings, stones, thistle, twist

BG, FG, P2, P3 = 0, 1, 2, 3


@pytest.fixture(autouse=True)
def sc():
    gr.set_gauge("sc")


def test_twist_is_inch_true_and_corner_anchored():
    arr, period = twist.twist_strip_in(161, 14, horizontal=True, bg=BG, fg=FG)
    assert arr.shape == (14, 161) and abs(period - 4.0) < 1e-9
    v, period_v = twist.twist_strip_in(152, 12, horizontal=False, bg=BG, fg=FG)
    assert v.shape == (152, 12) and abs(period_v - 4.0) < 1e-9
    gold = arr == FG
    assert gold[:, 0].sum() <= 5 and gold[:, -1].sum() <= 5        # strands converge at both corners
    assert not gold[0].any() and not gold[-1].any()                 # margin rows stay background


def test_solomon_and_corner_block_have_four_crossings():
    _, n = knots.solomon_knot(21, 24, BG, FG)
    assert n == 4
    blk, n = knots.corner_block(25, 28, BG, FG)
    assert n == 4 and (blk[0] == FG).all() and (blk[:, 0] == FG).all()


def test_woven_x_block_has_cross():
    blk = knots.woven_x_block(18, 20, BG, FG)
    assert blk[9, 9] == FG and blk[2, 9] == BG


def test_rings_interlock():
    arr, n = rings.rings(BG, FG)
    assert n == 2 and (arr == FG).sum() > 60


def test_thistles():
    big = thistle.thistle(BG, P2, P3)
    small = thistle.thistle_small(BG, P2, P3)
    assert big.shape == (34, 19) and small.shape == (25, 19)
    assert (big == P2).sum() > 60 and (small == P2).sum() >= 30
    scaled = thistle_scaled = thistle.thistle_scaled(6.0, BG, P2, P3)
    assert scaled.shape[0] == gr.rows(6.0)
    icon = thistle.bloom_icon(BG, P2, FG)
    assert (icon == P2).any() and (icon == FG).any()


def test_dragonfly_is_symmetric_and_amber_is_outlined():
    d = dragonfly.dragonfly(40, 48, BG, FG, P2, FG, span=7.0)
    assert np.array_equal(d, d[:, ::-1]) and (d == FG).sum() > 100
    a = dragonfly.amber_drop(36, 44, BG, P2, FG)
    assert a[22, 18] == P2 and (a == FG).sum() > 40


def test_stones_moon_clear_of_stones():
    s = stones.standing_stones(170, 56, BG, P2, FG, P3)
    assert (s == FG).sum() > 150 and (s == P3).sum() > 60 and (s == P2).sum() > 800
    assert not (gr.dilate(s == P3) & (s == FG)).any()


def test_plaid_min_run_two():
    a = plaid.plaid(120, 80, 0, 0, {"G": BG, "B": FG, "Y": P2, "R": P3})
    from graphghan.export import rle_rows
    for runs in rle_rows(a) + rle_rows(a.T):
        assert min(n for _, n in runs) >= 2


def test_stripe_band():
    b = bands.stripe_band(30, 6, [(BG, 2), (FG, 2), (P2, 2)])
    assert b.shape == (6, 30) and (b[0] == BG).all() and (b[2] == FG).all() and (b[5] == P2).all()
    assert bands.stripe_band(30, 6, [(BG, 2), (FG, 2), (P2, 2)], horizontal=False).shape == (30, 6)


def test_catalog_renders():
    assert len(CATALOG) >= 8
    for name, fn in CATALOG:
        arr, rgb = fn()
        assert arr.ndim == 2 and len(rgb) > int(arr.max())
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/test_motifs.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Create the motif modules**

Each module starts with:
```python
from __future__ import annotations
import numpy as np
from .. import grid as gr
```
and takes colors as explicit ints. Port from `OLD/outlander/motifs.py` as follows.

`plaid.py`:
```python
SETT_DEFAULT = [("G", 1.5), ("B", 0.75), ("Y", 0.5), ("B", 0.75), ("G", 1.5), ("R", 1.0)]


def sett_cells(sett, density, min_cells=2):
    return [(code, max(min_cells, int(round(inches * density)))) for code, inches in sett]


def stripe_lookup(length, density, phase, sett, colors):
    seq = []
    for code, n in sett_cells(sett, density):
        seq += [colors[code]] * n
    seq = np.array(seq, dtype=np.uint8)
    idx = np.arange(length)
    mirrored = np.minimum(idx, length - 1 - idx)
    return seq[(mirrored + phase) % len(seq)]


def plaid(w, h, phase_x, phase_y, colors, sett=SETT_DEFAULT, priority=("Y", "R", "B", "G")):
    """Crochet-friendly plaid: mirrored setts on both axes; each cell takes the higher-priority
    of its column stripe and row stripe. No stripe is narrower than 2 cells."""
    rank = {colors[code]: len(priority) - i for i, code in enumerate(priority)}
    sx = stripe_lookup(w, gr.ST_PER_IN, phase_x, sett, colors)[None, :]
    sy = stripe_lookup(h, gr.ROWS_PER_IN, phase_y, sett, colors)[:, None]
    px = np.vectorize(rank.get)(sx)
    py = np.vectorize(rank.get)(sy)
    return np.where(px >= py, sx, sy).astype(np.uint8)
```

`twist.py`: copy `twist_strip_in` from OLD verbatim (the version with `u0 = -0.5`, odd half-period fitting, and `amp = max(2, int(round(amp_in / across_in)))`), changing the import to `from ..grid import curve_mask_in, weave` and the signature to `twist_strip_in(length, thick, horizontal=True, period_in=4.0, amp_in=1.0, radius_in=0.3, bg=0, fg=1, fit=True)`.

`knots.py`: copy `solomon_knot`, `corner_block`, `woven_x_block` from OLD; signatures become `solomon_knot(w, h, bg, fg, half=2.4, r_out=1.05, stroke=0.6)`, `corner_block(w, h, bg, fg, outline=2)` (passes `bg, fg` through), `woven_x_block(w, h, bg, fg, outline=2, bar_in=0.6)`. Imports: `from ..grid import stadium_ring, segment_band, weave, sector_windows`.

`rings.py`: copy `rings` with signature `rings(bg, fg, r_in=1.1, r_out=1.75, gap_in=1.9)`; imports `from ..grid import circle_ring, weave`.

`thistle.py`: copy `THISTLE_ART`, `THISTLE_SMALL_ART`, `_art_to_array(art, bg, head, leaf)` (map `P`->head, `G`->leaf), `thistle(bg, head, leaf)`, `thistle_small(bg, head, leaf)`, `thistle_scaled(height_in, bg, head, leaf)` (uses `thistle_small` when `height_in < 7.0`, base design gauge 3.5 x 4.0), and `bloom_icon(bg, head, calyx)` (crown color `head`, calyx color `calyx`). Needs `from PIL import Image`.

`dragonfly.py`: copy `dragonfly(w, h, bg, body, wing_fill, wing_line, span=7.0, cx=None, cy=None)` and `amber_drop(w, h, bg, fill, line, a=4.3, b=4.9, edge=0.42)`; imports `from ..grid import ellipse_fill, stadium_ring`.

`stones.py`: copy `standing_stones(w, h, bg, hill, stone, moon)` (the version that places the moon at `cx + 9.6 / gr.SW`, `moon_cy = max(r / gr.SH + gr.rows(0.3), hill_top - 4.0 / gr.SH)`, and chamfers one top corner per stone).

`bands.py`:
```python
def stripe_band(length, thick, seq, horizontal=True):
    """Stripes across a band; `seq` is [(color, cells), ...] repeated to fill `thick`."""
    across = []
    for c, n in seq:
        across += [c] * n
    across = (across * (thick // len(across) + 1))[:thick]
    col = np.array(across, dtype=np.uint8)
    arr = np.repeat(col[:, None], length, axis=1)
    return arr if horizontal else arr.T.copy()
```

`__init__.py`:
```python
"""Motif families. CATALOG renders a sample of each for the skill's thumbnails."""
from . import bands, dragonfly, knots, plaid, rings, stones, thistle, twist  # noqa: F401

SAMPLE_RGB = [(30, 77, 58), (217, 162, 27), (242, 232, 213), (43, 47, 51), (107, 45, 92), (31, 58, 147), (139, 30, 45)]
G, Y, C, K, P, B, R = range(7)


def _catalog():
    return [
        ("twist-strip", lambda: (twist.twist_strip_in(70, 14, bg=G, fg=Y)[0], SAMPLE_RGB)),
        ("solomon-knot", lambda: (knots.corner_block(25, 28, G, Y)[0], SAMPLE_RGB)),
        ("woven-x", lambda: (knots.woven_x_block(18, 20, G, Y), SAMPLE_RGB)),
        ("rings", lambda: (rings.rings(C, Y)[0], SAMPLE_RGB)),
        ("thistle", lambda: (thistle.thistle(C, P, G), SAMPLE_RGB)),
        ("thistle-small", lambda: (thistle.thistle_small(C, P, G), SAMPLE_RGB)),
        ("bloom-icon", lambda: (thistle.bloom_icon(G, P, Y), SAMPLE_RGB)),
        ("dragonfly", lambda: (dragonfly.dragonfly(40, 48, Y, K, C, K), SAMPLE_RGB)),
        ("amber-drop", lambda: (dragonfly.amber_drop(36, 44, C, Y, K), SAMPLE_RGB)),
        ("standing-stones", lambda: (stones.standing_stones(120, 50, C, G, K, Y), SAMPLE_RGB)),
        ("plaid", lambda: (plaid.plaid(96, 64, 0, 0, {"G": G, "B": B, "Y": Y, "R": R}), SAMPLE_RGB)),
        ("stripe-band", lambda: (bands.stripe_band(60, 10, [(G, 2), (B, 2), (G, 2), (Y, 2), (G, 2)]), SAMPLE_RGB)),
    ]


CATALOG = _catalog()
```

- [ ] **Step 4: Run tests**

Run: `uv run pytest tests/test_motifs.py -v`
Expected: 10 PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: motif modules with explicit colors and a catalog"
```

---

### Task 6: Frames and composition

**Files:**
- Create: `src/graphghan/frame.py`, `src/graphghan/compose.py`, `tests/test_frame.py`

**Interfaces:**
- Produces:
  - `frame.twist_frame(g, W, H, bg, fg, edge_in=0.5, strip_in=3.5, corners="dot", margin_in=0.75) -> (x0, y0, x1, y1)` panel rect; `corners` in `{"solid", "dot", "cross"}`
  - `frame.link_frame(g, W, H, ground, rail, bloom, calyx, edge_color, edge_in=0.5, band_in=2.5, link_in=5.0, margin_in=0.5) -> (x0, y0, x1, y1)`
  - `compose.text_block(g, lines, x_center, y_top, size, pitch, font_path, color, bg, bold=0.035, threshold=0.42) -> list[tuple[int,int,int,int]]` boxes `(x0, y0, x1, y1)` per line

- [ ] **Step 1: Write the failing tests**

`tests/test_frame.py`:
```python
import numpy as np
import pytest

from graphghan import Grid, grid as gr
from graphghan.compose import text_block
from graphghan.frame import link_frame, twist_frame
from graphghan.text import FONT_METAMORPHOUS

G, Y, C, K, P, R = range(6)


@pytest.fixture(autouse=True)
def sc():
    gr.set_gauge("sc")


@pytest.mark.parametrize("corners", ["solid", "dot", "cross"])
def test_twist_frame_edges_mirror_and_panel(corners):
    W, H = 189, 184
    g = Grid(W, H, G)
    x0, y0, x1, y1 = twist_frame(g, W, H, G, Y, corners=corners)
    a = g.a
    ex, ey = gr.cols(0.5), gr.rows(0.5)
    assert (a[:ey] == Y).all() and (a[-ey:] == Y).all() and (a[:, :ex] == Y).all() and (a[:, -ex:] == Y).all()
    sx, sy = gr.cols(3.5), gr.rows(3.5)
    assert np.array_equal(a[:, :ex + sx], a[:, W - ex - sx:][:, ::-1])
    assert np.array_equal(a[:ey + sy], a[H - ey - sy:][::-1])
    assert x0 == W - x1 and y0 == H - y1 and x1 - x0 > 140 and y1 - y0 > 130


def test_link_frame_panel_and_blooms():
    W, H = 120, 100
    g = Grid(W, H, G)
    x0, y0, x1, y1 = link_frame(g, W, H, G, Y, P, Y, R)
    assert (g.a[0] == R).all() and (g.a == P).sum() >= 8 * 4
    assert x0 == W - x1 and y0 == H - y1


def test_text_block_centres_lines():
    g = Grid(200, 100, C)
    boxes = text_block(g, ["Lord, you", "gave me"], 100, 10, 17, 20, FONT_METAMORPHOUS, K, C)
    assert len(boxes) == 2 and boxes[1][1] == 30
    for x0, y0, x1, y1 in boxes:
        assert abs((x0 + x1) / 2 - 100) <= 1 and (g.a[y0:y1, x0:x1] == K).any()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/test_frame.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Implement compose.py**

```python
"""Composition helpers shared by pattern designs."""
from __future__ import annotations

from .text import text_line


def text_block(g, lines, x_center, y_top, size, pitch, font_path, color, bg, bold=0.035, threshold=0.42):
    """Blit `lines` centred on x_center, one every `pitch` rows, each `size` rows tall.
    Returns one (x0, y0, x1, y1) box per line."""
    boxes = []
    for i, t in enumerate(lines):
        arr, _asc, _desc = text_line(t, size, color, bg, font_path, threshold=threshold, bold=bold)
        h, w = arr.shape
        x0 = int(round(x_center - w / 2.0))
        y0 = y_top + i * pitch
        g.blit(arr, x0, y0, transparent=bg)
        boxes.append((x0, y0, x0 + w, y0 + h))
    return boxes
```

- [ ] **Step 4: Implement frame.py**

```python
"""Border frames. Each paints into a Grid and returns the inner (cream panel) rect."""
from __future__ import annotations

from . import grid as gr
from .motifs import knots, thistle, twist


def twist_frame(g, W, H, bg, fg, edge_in=0.5, strip_in=3.5, corners="dot", margin_in=0.75):
    """Edge line in `fg`, inch-true braided twist (`fg` on `bg`) all round, inner `fg` line, `bg` margin.
    corners: "solid" (fg squares), "dot" (fg square, bg inset, fg dot), "cross" (bigger woven-X blocks)."""
    ex, ey = gr.cols(edge_in), gr.rows(edge_in)
    sx, sy = gr.cols(strip_in), gr.rows(strip_in)
    mx, my = gr.cols(margin_in), gr.rows(margin_in)
    g.rect(0, 0, W, H, fg)
    g.rect(ex, ey, W - ex, H - ey, bg)
    if corners == "cross":
        bw, bh, cx0, cy0 = ex + sx + 1 + mx, ey + sy + 1 + my, 0, 0
    else:
        bw, bh, cx0, cy0 = sx, sy, ex, ey
    top, _ = twist.twist_strip_in(W - 2 * (cx0 + bw), sy, horizontal=True, bg=bg, fg=fg)
    g.blit(top, cx0 + bw, ey)
    g.blit(top[::-1, :], cx0 + bw, H - ey - sy)
    side, _ = twist.twist_strip_in(H - 2 * (cy0 + bh), sx, horizontal=False, bg=bg, fg=fg)
    g.blit(side, ex, cy0 + bh)
    g.blit(side[:, ::-1], W - ex - sx, cy0 + bh)
    ix, iy = ex + sx, ey + sy
    g.rect(ix, iy, W - ix, H - iy, fg)
    g.rect(ix + 1, iy + 1, W - ix - 1, H - iy - 1, bg)
    for bx in (cx0, W - cx0 - bw):
        for by in (cy0, H - cy0 - bh):
            if corners == "cross":
                g.blit(knots.woven_x_block(bw, bh, bg, fg), bx, by)
            elif corners == "dot":
                g.rect(bx, by, bx + bw, by + bh, fg)
                g.rect(bx + 2, by + 2, bx + bw - 2, by + bh - 2, bg)
                g.rect(bx + bw // 2 - 1, by + bh // 2 - 1, bx + bw // 2 + 1, by + bh // 2 + 1, fg)
            else:
                g.rect(bx, by, bx + bw, by + bh, fg)
    px0, py0 = ix + 1 + mx, iy + 1 + my
    return px0, py0, W - px0, H - py0


def link_frame(g, W, H, ground, rail, bloom, calyx, edge_color, edge_in=0.5, band_in=2.5, link_in=5.0, margin_in=0.5):
    """A band of linked rectangles: `rail` rails and dividers on `ground`, a thistle bloom in every link."""
    ex, ey = gr.cols(edge_in), gr.rows(edge_in)
    bx, by = gr.cols(band_in), gr.rows(band_in)
    rx, ry = gr.cols(0.5), gr.rows(0.5)
    g.rect(0, 0, W, H, edge_color)
    g.rect(ex, ey, W - ex, H - ey, ground)
    for (x0, y0, x1, y1) in ((ex, ey, W - ex, H - ey), (ex + bx - rx, ey + by - ry, W - ex - bx + rx, H - ey - by + ry)):
        g.rect(x0, y0, x1, y0 + ry, rail); g.rect(x0, y1 - ry, x1, y1, rail)
        g.rect(x0, y0, x0 + rx, y1, rail); g.rect(x1 - rx, y0, x1, y1, rail)
    icon = thistle.bloom_icon(ground, bloom, calyx)
    ih, iw = icon.shape
    for y0 in (ey, H - ey - by):
        cy = (y0 + ry + y0 + by - ry) // 2
        x_start, x_end = ex + bx, W - ex - bx
        n = max(1, int(round((x_end - x_start) * gr.SW / link_in)))
        step = (x_end - x_start) / n
        g.rect(x_start - rx, y0, x_start, y0 + by, rail); g.rect(x_end, y0, x_end + rx, y0 + by, rail)
        for i in range(1, n):
            xx = int(round(x_start + i * step))
            g.rect(xx - rx // 2, y0, xx - rx // 2 + rx, y0 + by, rail)
        for i in range(n):
            cx = int(round(x_start + (i + 0.5) * step))
            g.blit(icon, cx - iw // 2, cy - ih // 2)
    for x0 in (ex, W - ex - bx):
        cx = (x0 + rx + x0 + bx - rx) // 2
        y_start, y_end = ey + by, H - ey - by
        n = max(1, int(round((y_end - y_start) * gr.SH / link_in)))
        step = (y_end - y_start) / n
        g.rect(x0, y_start - ry, x0 + bx, y_start, rail); g.rect(x0, y_end, x0 + bx, y_end + ry, rail)
        for i in range(1, n):
            yy = int(round(y_start + i * step))
            g.rect(x0, yy - ry // 2, x0 + bx, yy - ry // 2 + ry, rail)
        for i in range(n):
            cy = int(round(y_start + (i + 0.5) * step))
            g.blit(icon, cx - iw // 2, cy - ih // 2)
    for cx0 in (ex, W - ex - bx):
        for cy0 in (ey, H - ey - by):
            g.blit(icon, cx0 + bx // 2 - iw // 2, cy0 + by // 2 - ih // 2)
    mx, my = ex + bx + gr.cols(margin_in), ey + by + gr.rows(margin_in)
    return mx, my, W - mx, H - my
```

- [ ] **Step 5: Run tests**

Run: `uv run pytest tests/test_frame.py -v`
Expected: 5 PASS

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: twist and link frames, text block composer"
```

---

### Task 7: Export and validate

**Files:**
- Create: `src/graphghan/export.py`, `src/graphghan/validate.py`, `tests/test_export.py`, `tests/test_validate.py`

**Interfaces:**
- Produces:
  - `export.rle_rows(a) -> list[list[tuple[int, int]]]` (color index, run length) per row top-to-bottom
  - `export.rows_to_strings(a, codes) -> list[str]` e.g. `"2Y7B"`; `export.decode_rows(strings, codes) -> np.ndarray`
  - `export.chart_png(a, rgb, path)`, `export.preview_png(a, rgb, path, cw=8, ch=None, grid=False)`
  - `export.stats(a, codes) -> dict` with keys `stitches, size_in, counts, single_stitch_runs, color_changes_per_row{mean,max,per_row}, yards_est, skeins_364yd`
  - `export.written_rows(a, codes) -> list[str]` (`Row 1 (RS): 189 Y  (189 sts)`, odd rows reversed)
  - `export.chart_json(a, meta, gauge_key, report, variant="final") -> dict` (schema 1) and `export.write_dist(a, meta, gauge_key, report, out_dir) -> dict` writing `chart.json`, `chart.png`, `preview.png`, `preview-grid.png`, `written-rows.txt`
  - `validate.bad_rows(a, width) -> list[int]`, `validate.used_indices(a) -> set[int]`, `validate.solid_edge(a, color, ex, ey) -> bool`, `validate.mirror_lr(a, n_cols) -> bool`, `validate.mirror_tb(a, n_rows) -> bool`, `validate.changes_per_row(a) -> list[int]`, `validate.min_run(a) -> int`, `validate.run_all(a, meta) -> list[tuple[str, bool, str]]`

- [ ] **Step 1: Write the failing tests**

`tests/test_export.py`:
```python
import json

import numpy as np
from pathlib import Path

from graphghan import grid as gr
from graphghan.export import chart_json, decode_rows, rle_rows, rows_to_strings, stats, write_dist, written_rows
from graphghan.pattern import load_pattern

FIX = Path(__file__).parent / "fixtures" / "minimal"


def small():
    a = np.zeros((3, 5), dtype=np.uint8)
    a[1, 1:4] = 1
    return a


def test_rle_round_trip():
    a = small()
    assert rle_rows(a)[1] == [(0, 1), (1, 3), (0, 1)]
    s = rows_to_strings(a, ["A", "B"])
    assert s == ["5A", "1A3B1A", "5A"]
    assert np.array_equal(decode_rows(s, ["A", "B"]), a)


def test_written_rows_reverse_odd_rows():
    a = small(); a[2, 0] = 1                      # bottom row: B then A
    lines = written_rows(a, ["A", "B"])
    assert lines[0] == "Row 1 (RS): 4 A, 1 B  (5 sts)"   # read right to left
    assert lines[1].startswith("Row 2 (WS): 1 A, 3 B, 1 A")


def test_stats_sum_and_changes():
    gr.set_gauge("sc")
    s = stats(small(), ["A", "B"])
    assert s["stitches"] == 15 and s["counts"] == {"A": 12, "B": 3}
    assert s["color_changes_per_row"]["per_row"] == [0, 2, 0] and s["color_changes_per_row"]["max"] == 2
    assert s["size_in"] == [round(5 / 3.5, 1), 0.8]


def test_chart_json_schema_and_write_dist(tmp_path):
    meta = load_pattern(FIX)
    gr.set_gauge("sc")
    doc = chart_json(small(), meta, "sc", {"panel": (1, 1, 4, 2)})
    for key in ("schema", "slug", "title", "dedication", "quote", "version", "stitch", "gauge", "cell_aspect",
                "width", "height", "size_in", "palette", "rows", "stats", "notes", "report"):
        assert key in doc
    assert doc["schema"] == 1 and doc["gauge"] == {"st_per_in": 3.5, "rows_per_in": 4.0}
    assert doc["palette"][0] == {"code": "A", "name": "Alpha", "hex": "#112233", "yarn": "any", "use": "ground"}
    write_dist(small(), meta, "sc", {"panel": (1, 1, 4, 2)}, tmp_path)
    assert json.loads((tmp_path / "chart.json").read_text())["rows"] == ["5A", "1A3B1A", "5A"]
    for name in ("chart.png", "preview.png", "preview-grid.png", "written-rows.txt"):
        assert (tmp_path / name).exists()
```

`tests/test_validate.py`:
```python
import numpy as np
from pathlib import Path

from graphghan import validate
from graphghan.pattern import load_pattern

FIX = Path(__file__).parent / "fixtures" / "minimal"


def framed():
    a = np.zeros((8, 10), dtype=np.uint8)
    a[2:6, 2:8] = 1
    return a


def test_helpers():
    a = framed()
    assert validate.bad_rows(a, 10) == [] and validate.bad_rows(a, 9) == list(range(8))
    assert validate.used_indices(a) == {0, 1}
    assert validate.solid_edge(a, 0, 2, 2) and not validate.solid_edge(a, 1, 2, 2)
    assert validate.mirror_lr(a, 3) and validate.mirror_tb(a, 3)
    assert validate.changes_per_row(a) == [0, 0, 2, 2, 2, 2, 0, 0] and validate.min_run(a) == 2


def test_run_all_reports():
    meta = load_pattern(FIX)
    results = validate.run_all(framed(), meta)
    names = [r[0] for r in results]
    assert "row totals" in names and "palette closure" in names and "solid edge" in names
    assert all(ok for _, ok, _ in results)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/test_export.py tests/test_validate.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Implement export.py**

```python
"""Exports: run-length rows, PNGs, stats, written rows, chart.json (schema 1)."""
from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from . import grid as gr

SCHEMA = 1
_RUN = re.compile(r"(\d+)([A-Za-z])")


def rle_rows(a):
    out = []
    for row in a:
        runs, prev, n = [], int(row[0]), 0
        for v in row:
            v = int(v)
            if v == prev:
                n += 1
            else:
                runs.append((prev, n)); prev, n = v, 1
        runs.append((prev, n))
        out.append(runs)
    return out


def rows_to_strings(a, codes):
    return ["".join(f"{n}{codes[c]}" for c, n in row) for row in rle_rows(a)]


def decode_rows(strings, codes):
    idx = {c: i for i, c in enumerate(codes)}
    rows = []
    for s in strings:
        row = []
        for n, c in _RUN.findall(s):
            row += [idx[c]] * int(n)
        rows.append(row)
    return np.array(rows, dtype=np.uint8)


def chart_png(a, rgb, path):
    img = Image.new("P", (a.shape[1], a.shape[0]))
    pal = [v for c in rgb for v in c] + [0, 0, 0] * (256 - len(rgb))
    img.putpalette(pal)
    img.putdata(a.astype(np.uint8).ravel().tolist())
    img.convert("RGB").save(path)


def preview_png(a, rgb, path, cw=8, ch=None, grid=False, bold_every=10):
    h, w = a.shape
    if ch is None:
        ch = max(1, int(round(cw * gr.SH / gr.SW)))
    img = Image.fromarray(np.array(rgb, dtype=np.uint8)[a]).resize((w * cw, h * ch), Image.NEAREST)
    if grid:
        d = ImageDraw.Draw(img)
        for x in range(w + 1):
            d.line([(x * cw, 0), (x * cw, h * ch)], fill=(0, 0, 0) if x % bold_every == 0 else (120, 120, 120))
        for y in range(h + 1):
            d.line([(0, y * ch), (w * cw, y * ch)], fill=(0, 0, 0) if y % bold_every == 0 else (120, 120, 120))
    img.save(path)


def stats(a, codes):
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
    yards = {code: n * cell_sqin * 1.1 * 1.2 for code, n in counts.items()}   # 1.1 yd/sq in worsted sc, +20% tails
    return {
        "stitches": int(w * h), "size_in": [round(w * gr.SW, 1), round(h * gr.SH, 1)],
        "counts": counts, "single_stitch_runs": singles,
        "color_changes_per_row": {"mean": round(sum(per_row) / len(per_row), 1), "max": max(per_row), "per_row": per_row},
        "yards_est": {k: int(round(v)) for k, v in yards.items()},
        "skeins_364yd": {k: round(v / 364, 1) for k, v in yards.items()},
    }


def written_rows(a, codes):
    runs = rle_rows(a)
    h = len(runs)
    lines = []
    for i in range(h):
        row_no = i + 1
        row = runs[h - 1 - i]
        if row_no % 2 == 1:
            row = row[::-1]
        side = "RS" if row_no % 2 == 1 else "WS"
        lines.append(f"Row {row_no} ({side}): " + ", ".join(f"{n} {codes[c]}" for c, n in row)
                     + f"  ({sum(n for _, n in row)} sts)")
    return lines


def chart_json(a, meta, gauge_key, report, variant="final"):
    st, rows = meta.gauges.get(gauge_key, gr.GAUGES[gauge_key])
    codes = meta.palette.codes
    return {
        "schema": SCHEMA, "slug": meta.slug, "title": meta.title, "dedication": meta.dedication, "quote": meta.quote,
        "version": meta.version, "variant": variant, "stitch": gauge_key,
        "gauge": {"st_per_in": st, "rows_per_in": rows}, "cell_aspect": round(st / rows, 4),
        "hook": meta.hook, "yarn_weight": meta.yarn_weight, "first_row_color": meta.first_row_color,
        "width": int(a.shape[1]), "height": int(a.shape[0]), "size_in": [round(a.shape[1] / st, 1), round(a.shape[0] / rows, 1)],
        "palette": [{"code": c.code, "name": c.name, "hex": c.hex, "yarn": c.yarn, "use": c.use} for c in meta.palette.colors],
        "rows": rows_to_strings(a, codes), "stats": stats(a, codes), "notes": meta.notes,
        "report": {k: (list(v) if isinstance(v, tuple) else v) for k, v in report.items()},
    }


def write_dist(a, meta, gauge_key, report, out_dir, variant="final"):
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    doc = chart_json(a, meta, gauge_key, report, variant)
    (out / "chart.json").write_text(json.dumps(doc, separators=(",", ":")) + "\n")
    chart_png(a, meta.palette.rgb, out / "chart.png")
    preview_png(a, meta.palette.rgb, out / "preview.png")
    preview_png(a, meta.palette.rgb, out / "preview-grid.png", grid=True)
    (out / "written-rows.txt").write_text("\n".join(written_rows(a, meta.palette.codes)) + "\n")
    return doc
```

- [ ] **Step 4: Implement validate.py**

```python
"""Generic chart invariants and reports. Pattern-specific checks live in each pattern's tests."""
from __future__ import annotations

import numpy as np

from . import grid as gr
from .export import rle_rows


def bad_rows(a, width):
    return [i for i, row in enumerate(a) if len(row) != width]


def used_indices(a):
    return set(int(v) for v in np.unique(a))


def solid_edge(a, color, ex, ey):
    return bool((a[:ey] == color).all() and (a[-ey:] == color).all() and (a[:, :ex] == color).all() and (a[:, -ex:] == color).all())


def mirror_lr(a, n_cols):
    return bool(np.array_equal(a[:, :n_cols], a[:, -n_cols:][:, ::-1]))


def mirror_tb(a, n_rows):
    return bool(np.array_equal(a[:n_rows], a[-n_rows:][::-1]))


def changes_per_row(a):
    return [len(r) - 1 for r in rle_rows(a)]


def min_run(a):
    return min(n for row in rle_rows(a) for _, n in row)


def run_all(a, meta):
    """Returns [(name, ok, detail)] for the checks every pattern must pass."""
    h, w = a.shape
    used = used_indices(a)
    first = meta.palette[meta.first_row_color] if meta.first_row_color in meta.palette else None
    ch = changes_per_row(a)
    results = [
        ("row totals", bad_rows(a, w) == [], f"{h} rows of {w}"),
        ("palette closure", used <= set(range(len(meta.palette))), f"indices used: {sorted(used)}"),
        ("solid edge", first is not None and solid_edge(a, first, 1, 1), f"edge color {meta.first_row_color}"),
        ("first row solid", first is not None and bool((a[-1] == first).all()), "row 1 is a single color"),
        ("mirror left/right (outer 2 cols)", mirror_lr(a, 2), ""),
        ("mirror top/bottom (outer 2 rows)", mirror_tb(a, 2), ""),
        ("changes per row", True, f"mean {sum(ch) / len(ch):.1f}, max {max(ch)}"),
        ("min run", True, f"{min_run(a)} stitch(es)"),
    ]
    return results
```

- [ ] **Step 5: Run tests**

Run: `uv run pytest tests/test_export.py tests/test_validate.py -v`
Expected: 6 PASS

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: export (chart.json schema 1) and generic validation"
```

---

### Task 8: The craigh-na-dun pattern

**Files:**
- Create: `patterns/craigh-na-dun/pattern.toml`, `patterns/craigh-na-dun/design.py`, `patterns/craigh-na-dun/CHANGELOG.md`, `patterns/craigh-na-dun/tests/test_design.py`, `patterns/craigh-na-dun/reference/reference-sheet.png` (copy of `OLD/reference-sheet.png`)

**Interfaces:**
- Consumes: everything above.
- Produces: `build(gauge_key="sc", variant="final") -> (Grid, report)` with report keys `panel, scene, text (list of boxes), text_bottom, thistles (2 boxes), dragonfly (box, only when foot == "dragonfly")`; `VARIANTS = {"final": {"corners": "dot", "foot": "dragonfly"}, "plain-foot": {"corners": "dot", "foot": "plain"}, "solid-corners": {"corners": "solid", "foot": "dragonfly"}, "cross-corners": {"corners": "cross", "foot": "dragonfly"}}`.

- [ ] **Step 1: Write pattern.toml**

```toml
[pattern]
slug = "craigh-na-dun"
title = "Craigh na Dun Blanket"
dedication = "For Meaghan"
quote = "Lord, you gave me a rare woman, and God! I loved her well."
version = "1.0.0"
stitch = "sc"
size_in = [54.0, 46.0]
hook = "5 mm (US H-8)"
yarn_weight = "worsted (#4)"
first_row_color = "Y"

[gauge]
sc = [3.5, 4.0]
hdc = [3.25, 2.5]

[[colors]]
code = "C"
name = "Cream"
hex = "#F2E8D5"
yarn = "Aran / off-white"
use = "sky, quote panel"

[[colors]]
code = "K"
name = "Charcoal"
hex = "#2B2F33"
yarn = "Charcoal or black"
use = "stones, lettering, dragonfly"

[[colors]]
code = "G"
name = "Deep Green"
hex = "#1E4D3A"
yarn = "Hunter green"
use = "hill, border ground, thistle foliage"

[[colors]]
code = "P"
name = "Purple"
hex = "#6B2D5C"
yarn = "Plum / dark orchid"
use = "thistle heads"

[[colors]]
code = "Y"
name = "Gold"
hex = "#D9A21B"
yarn = "Gold"
use = "moon, braided border, edge lines"

[notes]
setup = [
  "Foundation: chain W + 1 in Gold (Y). Row 1 begins in the 2nd chain from the hook; the whole first row is Gold, part of the outer 2-row gold edge.",
  "Ch 1, turn at the end of every row. The chart counts stitches only; the turning chain is not a stitch.",
  "Change colors in the last yarn-over of the stitch before the new color: work the stitch until two loops remain, drop the old color, pull the new one through.",
  "Block the finished blanket to size so the braid straightens and the lettering squares up.",
]
colors = [
  "Braid rows (the top and bottom strips) alternate gold and green every 2 to 5 stitches; carry the other color under the stitches, tapestry style. The side strips add about four gold runs to every other row.",
  "Lettering rows are cream and charcoal only across the panel. Carry charcoal under the cream between letters, or use a bobbin per word.",
  "Scene rows are cream sky with charcoal stones and the gold moon; the hill rows are long green runs, the easiest in the blanket.",
]
```

- [ ] **Step 2: Write the failing pattern tests**

`patterns/craigh-na-dun/tests/test_design.py`:
```python
from pathlib import Path

import numpy as np
import pytest

from graphghan import grid as gr, validate
from graphghan.pattern import load_design, load_pattern

HERE = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="module")
def chart():
    meta = load_pattern(HERE)
    design = load_design(HERE)
    g, report = design.build("sc", "final")
    return g.a, report, meta


def test_dimensions_and_limits(chart):
    a, _, _ = chart
    assert a.shape == (184, 189)


def test_generic_invariants(chart):
    a, _, meta = chart
    failures = [(n, d) for n, ok, d in validate.run_all(a, meta) if not ok]
    assert failures == []


def test_five_colors_only(chart):
    a, _, meta = chart
    assert {meta.palette.codes[i] for i in validate.used_indices(a)} == {"C", "K", "G", "P", "Y"}


def test_frame_corner_squares_mirror(chart):
    a, _, _ = chart
    ex, ey, sx, sy = gr.cols(0.5), gr.rows(0.5), gr.cols(3.5), gr.rows(3.5)
    tl = a[ey:ey + sy, ex:ex + sx]
    assert np.array_equal(tl, a[ey:ey + sy, -ex - sx:-ex][:, ::-1])
    assert np.array_equal(tl, a[-ey - sy:-ey, ex:ex + sx][::-1, :])


def test_panel_and_outside(chart):
    a, rep, meta = chart
    C, K, G, P, Y = (meta.palette[c] for c in "CKGPY")
    x0, y0, x1, y1 = rep["panel"]
    panel = a[y0:y1, x0:x1]
    assert set(np.unique(panel).tolist()) <= {C, K, G, P, Y} and (panel == C).mean() > 0.6
    outside = a.copy(); outside[y0:y1, x0:x1] = C
    assert not (outside == K).any() and not (outside == P).any()


def test_scene(chart):
    a, rep, meta = chart
    K, G, Y = (meta.palette[c] for c in "KGY")
    x0, y0, x1, y1 = rep["scene"]
    scene = a[y0:y1, x0:x1]
    assert (scene == K).sum() > 150 and (scene == Y).sum() > 60 and (scene == G).sum() > 800
    assert not (gr.dilate(scene == Y) & (scene == K)).any()


def test_text_lines_clear(chart):
    a, rep, meta = chart
    C, K = meta.palette["C"], meta.palette["K"]
    px0, _, px1, _ = rep["panel"]
    for (lx0, ly0, lx1, ly1) in rep["text"]:
        assert set(np.unique(a[ly0:ly1, px0:px1]).tolist()) <= {C, K}


def test_thistles_and_dragonfly(chart):
    a, rep, meta = chart
    K, P = meta.palette["K"], meta.palette["P"]
    (lx0, ly0, lx1, ly1), (rx0, ry0, rx1, ry1) = rep["thistles"]
    assert (a[ly0:ly1, lx0:lx1] == P).sum() >= 30
    assert np.array_equal(a[ly0:ly1, lx0:lx1], a[ry0:ry1, rx0:rx1][:, ::-1])
    dx0, dy0, dx1, dy1 = rep["dragonfly"]
    assert (a[dy0:dy1, dx0:dx1] == K).sum() > 60 and abs((dx0 + dx1) / 2 - a.shape[1] / 2) <= 1


def test_variants_build():
    design = load_design(HERE)
    load_pattern(HERE)
    for name in design.VARIANTS:
        g, _ = design.build("sc", name)
        assert g.a.shape == (184, 189)
    g, _ = design.build("hdc", "final")
    assert g.a.shape == (115, 176)
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `uv run pytest patterns/craigh-na-dun -v`
Expected: FAIL with `FileNotFoundError` (no design.py)

- [ ] **Step 4: Write design.py**

```python
"""Craigh na Dun Blanket: standing stones, the quote, thistles, a dragonfly, braided gold border."""
from __future__ import annotations

from graphghan import Grid, grid as gr, palette
from graphghan.compose import text_block
from graphghan.frame import twist_frame
from graphghan.motifs import dragonfly, stones, thistle
from graphghan.text import FONT_METAMORPHOUS

PAL = palette.load(__file__)
C, K, G, P, Y = (PAL[c] for c in "CKGPY")

QUOTE = ["Lord, you gave me", "a rare woman,", "and God!", "I loved her well."]
TEXT_ROWS = {"sc": 17, "hdc": 12, "dc": 9}
TEXT_GAP = {"sc": 3, "hdc": 2, "dc": 1}
SIZE_IN = (54.0, 46.0)

VARIANTS = {
    "final": {"corners": "dot", "foot": "dragonfly"},
    "plain-foot": {"corners": "dot", "foot": "plain"},
    "solid-corners": {"corners": "solid", "foot": "dragonfly"},
    "cross-corners": {"corners": "cross", "foot": "dragonfly"},
}


def build(gauge_key: str = "sc", variant: str = "final"):
    opts = VARIANTS[variant]
    gr.set_gauge(gauge_key)
    W, H = gr.cols(SIZE_IN[0]), gr.rows(SIZE_IN[1])
    g = Grid(W, H, G)
    x0, y0, x1, y1 = twist_frame(g, W, H, G, Y, corners=opts["corners"])
    g.rect(x0, y0, x1, y1, C)
    cx = (x0 + x1) // 2
    size, pitch = TEXT_ROWS[gauge_key], TEXT_ROWS[gauge_key] + TEXT_GAP[gauge_key]
    text_h = 3 * pitch + size
    bottom_rows = gr.rows(6.5 if opts["foot"] == "dragonfly" else 6.0)
    gap = gr.rows(0.8)
    scene_h = max(gr.rows(9.0), min(gr.rows(14.0), (y1 - y0) - text_h - bottom_rows - 3 * gap))
    g.blit(stones.standing_stones(x1 - x0, scene_h, C, G, K, Y), x0, y0)
    text_top = y0 + scene_h + gap
    boxes = text_block(g, QUOTE, cx, text_top, size, pitch, FONT_METAMORPHOUS, K, C)
    text_bottom = text_top + text_h
    th = thistle.thistle_scaled(min(6.5, (y1 - gr.rows(0.4) - (text_bottom + gap)) * gr.SH), C, P, G)
    thh, thw = th.shape
    ty = y1 - gr.rows(0.4) - thh
    lx, rx = x0 + gr.cols(1.2), x1 - gr.cols(1.2) - thw
    g.blit(th, lx, ty, transparent=C)
    g.blit(th[:, ::-1], rx, ty, transparent=C)
    report = {"panel": (x0, y0, x1, y1), "scene": (x0, y0, x1, y0 + scene_h), "text": boxes,
              "text_bottom": text_bottom, "thistles": [(lx, ty, lx + thw, ty + thh), (rx, ty, rx + thw, ty + thh)]}
    if opts["foot"] == "dragonfly":
        span = 6.5
        dw, dh = gr.cols(span + 0.6), gr.rows(5.6)
        df = dragonfly.dragonfly(dw, dh, C, K, K, K, span=span)
        room = y1 - gr.rows(0.4) - (text_bottom + gap)
        if dh > room:
            df = df[(dh - room) // 2:(dh - room) // 2 + room]
        dy = y1 - gr.rows(0.4) - df.shape[0]
        g.blit(df, cx - dw // 2, dy, transparent=C)
        report["dragonfly"] = (cx - dw // 2, dy, cx - dw // 2 + dw, y1 - gr.rows(0.4))
    return g, report
```

`patterns/craigh-na-dun/CHANGELOG.md`:
```markdown
# craigh-na-dun

## 1.0.0 (2026-09-09)
First release. 189 x 184 sc, 5 colors, 54 x 46 in. Standing stones under a full moon, the quote in
Metamorphous, thistles, a dragonfly, braided gold twist border with nailhead corners.
```

Copy the reference sheet: `mkdir -p patterns/craigh-na-dun/reference && cp ~/Projects/outlander-blanket/reference-sheet.png patterns/craigh-na-dun/reference/`

- [ ] **Step 5: Run tests**

Run: `uv run pytest patterns/craigh-na-dun -v`
Expected: 9 PASS

- [ ] **Step 6: Verify the chart matches the finalized design**

Run:
```bash
uv run python -c "
import json, numpy as np
from graphghan.pattern import load_pattern, load_design
from graphghan.export import rows_to_strings
d='patterns/craigh-na-dun'; meta=load_pattern(d); g,_=load_design(d).build('sc','final')
old=json.load(open('/Users/tyler/Projects/outlander-blanket/out/final/chart.json'))['rows']
print('identical to finalized design:', rows_to_strings(g.a, meta.palette.codes)==old)"
```
Expected: `identical to finalized design: True`. If False, diff the first differing row and fix the port before continuing (the old palette had 7 entries; only the five used codes matter, and the old chart used the same codes).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(pattern): craigh-na-dun design, metadata, and tests"
```

---

### Task 9: CLI (render, check, new, options, catalog, site)

**Files:**
- Create: `src/graphghan/cli.py`, `src/graphghan/options_page.py`, `src/graphghan/templates/pattern.toml.tmpl`, `src/graphghan/templates/design.py.tmpl`, `src/graphghan/templates/test_design.py.tmpl`, `tests/test_cli.py`
- Modify: `patterns/craigh-na-dun/dist/*` (generated and committed)

**Interfaces:**
- Consumes: `pattern.load_pattern/load_design`, `export.write_dist`, `validate.run_all`, `motifs.CATALOG`.
- Produces: console script `graphghan` with subcommands:
  - `render <slug> [--gauge K] [--variant V] [--out DIR] [--check]`
  - `check <slug>`
  - `new <slug> --title T [--template craigh-na-dun]`
  - `options <slug> [--gauges sc,hdc]` → `patterns/<slug>/build/options.html` + PNGs
  - `catalog [--out DIR]` (default `.claude/skills/graphghan/assets`)
  - `site build [--out DIR]`, `site serve [--port N]` (run `site/build.py` via runpy; error if missing)
  - `main(argv=None) -> int`

- [ ] **Step 1: Write the failing tests**

`tests/test_cli.py`:
```python
import json
import subprocess
import sys
from pathlib import Path

from graphghan.cli import main

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run([sys.executable, "-m", "graphghan.cli", *args], cwd=ROOT, capture_output=True, text=True)


def test_render_writes_dist_and_check_passes(tmp_path):
    assert main(["render", "craigh-na-dun", "--out", str(tmp_path)]) == 0
    doc = json.loads((tmp_path / "chart.json").read_text())
    assert doc["schema"] == 1 and doc["width"] == 189 and doc["dedication"] == "For Meaghan"
    assert (tmp_path / "chart.png").exists() and (tmp_path / "written-rows.txt").exists()
    assert main(["render", "craigh-na-dun", "--check"]) == 0        # committed dist matches


def test_check_runs_invariants_and_tests():
    r = run("check", "craigh-na-dun")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "row totals" in r.stdout and "passed" in r.stdout


def test_new_scaffolds_and_renders(tmp_path, monkeypatch):
    monkeypatch.chdir(ROOT)
    assert main(["new", "test-scaffold", "--title", "Test Scaffold", "--dir", str(tmp_path)]) == 0
    d = tmp_path / "test-scaffold"
    assert (d / "pattern.toml").exists() and (d / "design.py").exists() and (d / "tests" / "test_design.py").exists()
    assert main(["render", str(d), "--out", str(tmp_path / "out")]) == 0
    assert json.loads((tmp_path / "out" / "chart.json").read_text())["slug"] == "test-scaffold"


def test_options_page(tmp_path):
    assert main(["options", "craigh-na-dun", "--gauges", "sc", "--out", str(tmp_path)]) == 0
    html = (tmp_path / "options.html").read_text()
    assert "final" in html and "plain-foot" in html and (tmp_path / "final_sc.png").exists()


def test_catalog(tmp_path):
    assert main(["catalog", "--out", str(tmp_path)]) == 0
    assert (tmp_path / "twist-strip.png").exists() and (tmp_path / "standing-stones.png").exists()


def test_usage_error():
    assert main(["render"]) == 2
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/test_cli.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: Write the templates**

`src/graphghan/templates/pattern.toml.tmpl`:
```toml
[pattern]
slug = "{slug}"
title = "{title}"
dedication = ""
quote = "Your quote here"
version = "0.1.0"
stitch = "sc"
size_in = [54.0, 46.0]
hook = "5 mm (US H-8)"
yarn_weight = "worsted (#4)"
first_row_color = "Y"

[gauge]
sc = [3.5, 4.0]
hdc = [3.25, 2.5]

[[colors]]
code = "C"
name = "Cream"
hex = "#F2E8D5"
yarn = "Aran / off-white"
use = "panel"

[[colors]]
code = "K"
name = "Charcoal"
hex = "#2B2F33"
yarn = "Charcoal"
use = "lettering"

[[colors]]
code = "G"
name = "Deep Green"
hex = "#1E4D3A"
yarn = "Hunter green"
use = "border ground"

[[colors]]
code = "Y"
name = "Gold"
hex = "#D9A21B"
yarn = "Gold"
use = "border"

[notes]
setup = ["Foundation: chain W + 1 in Gold (Y)."]
colors = []
```

`src/graphghan/templates/design.py.tmpl`:
```python
"""{title}: quote panel inside a braided border. Edit freely; keep build() deterministic."""
from __future__ import annotations

from graphghan import Grid, grid as gr, palette
from graphghan.compose import text_block
from graphghan.frame import twist_frame
from graphghan.text import FONT_METAMORPHOUS

PAL = palette.load(__file__)
C, K, G, Y = (PAL[c] for c in "CKGY")

QUOTE = ["Your quote", "goes here"]
TEXT_ROWS = {{"sc": 17, "hdc": 12, "dc": 9}}
TEXT_GAP = {{"sc": 3, "hdc": 2, "dc": 1}}
SIZE_IN = (54.0, 46.0)

VARIANTS = {{"final": {{"corners": "dot"}}, "solid-corners": {{"corners": "solid"}}}}


def build(gauge_key: str = "sc", variant: str = "final"):
    opts = VARIANTS[variant]
    gr.set_gauge(gauge_key)
    W, H = gr.cols(SIZE_IN[0]), gr.rows(SIZE_IN[1])
    g = Grid(W, H, G)
    x0, y0, x1, y1 = twist_frame(g, W, H, G, Y, corners=opts["corners"])
    g.rect(x0, y0, x1, y1, C)
    size, pitch = TEXT_ROWS[gauge_key], TEXT_ROWS[gauge_key] + TEXT_GAP[gauge_key]
    text_h = (len(QUOTE) - 1) * pitch + size
    text_top = (y0 + y1) // 2 - text_h // 2
    boxes = text_block(g, QUOTE, (x0 + x1) // 2, text_top, size, pitch, FONT_METAMORPHOUS, K, C)
    return g, {{"panel": (x0, y0, x1, y1), "text": boxes}}
```

`src/graphghan/templates/test_design.py.tmpl`:
```python
from pathlib import Path

import numpy as np
import pytest

from graphghan import validate
from graphghan.pattern import load_design, load_pattern

HERE = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="module")
def chart():
    meta = load_pattern(HERE)
    g, report = load_design(HERE).build(meta.stitch, "final")
    return g.a, report, meta


def test_generic_invariants(chart):
    a, _, meta = chart
    assert [(n, d) for n, ok, d in validate.run_all(a, meta) if not ok] == []


def test_text_lines_clear(chart):
    a, rep, meta = chart
    C, K = meta.palette["C"], meta.palette["K"]
    px0, _, px1, _ = rep["panel"]
    for (lx0, ly0, lx1, ly1) in rep["text"]:
        assert set(np.unique(a[ly0:ly1, px0:px1]).tolist()) <= {{C, K}}
```

- [ ] **Step 4: Implement options_page.py**

```python
"""The comparison page written by `graphghan options`: every variant at every gauge, with stats."""
from __future__ import annotations

import json


def build_options_html(title, entries):
    """entries: list of dicts {variant, gauge, width, height, size_in, colors, changes_mean, changes_max, hours, rows, palette}."""
    cards = []
    for e in entries:
        cards.append(
            f'<article><h2>{e["variant"]} · {e["gauge"]}</h2>'
            f'<canvas data-key="{e["variant"]}_{e["gauge"]}"></canvas>'
            f'<table><tr><th>Stitches × rows</th><td>{e["width"]} × {e["height"]}</td></tr>'
            f'<tr><th>Finished</th><td>{e["size_in"][0]}″ × {e["size_in"][1]}″</td></tr>'
            f'<tr><th>Colors</th><td>{len(e["colors"])}</td></tr>'
            f'<tr><th>Changes / row</th><td>mean {e["changes_mean"]}, max {e["changes_max"]}</td></tr>'
            f'<tr><th>Stitching</th><td>~{e["hours"]} h</td></tr></table></article>')
    data = json.dumps({f'{e["variant"]}_{e["gauge"]}': e for e in entries})
    return f"""<meta charset="utf-8"><title>{title} options</title>
<style>body{{font-family:system-ui;margin:24px;background:#f4f5f0;color:#1f2a24}}article{{margin:0 0 32px;background:#fff;padding:16px;border:1px solid #d3d9d0;border-radius:6px}}
canvas{{display:block;max-width:100%;margin:8px 0}}table{{border-collapse:collapse}}th{{text-align:left;padding:4px 12px 4px 0;color:#5b675f;font-weight:600}}td{{padding:4px 0}}</style>
<h1>{title}: options</h1>
{''.join(cards)}
<script>
const DATA={data};
for (const [key,e] of Object.entries(DATA)) {{
  const cv=document.querySelector(`canvas[data-key="${{key}}"]`), ctx=cv.getContext('2d');
  const hex=Object.fromEntries(e.palette.map(p=>[p.code,p.hex]));
  const cw=Math.max(2,Math.floor(1100/e.width)), ch=Math.max(2,Math.round(cw*e.cell_aspect));
  cv.width=e.width*cw; cv.height=e.height*ch;
  e.rows.forEach((s,y)=>{{let x=0; for (const m of s.matchAll(/(\\d+)([A-Za-z])/g)) {{ctx.fillStyle=hex[m[2]]; ctx.fillRect(x*cw,y*ch,+m[1]*cw,ch); x+=+m[1];}}}});
}}
</script>"""
```

- [ ] **Step 5: Implement cli.py**

```python
"""graphghan command line."""
from __future__ import annotations

import argparse
import http.server
import json
import runpy
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

from . import grid as gr
from .export import chart_json, preview_png, rows_to_strings, stats, write_dist
from .motifs import CATALOG
from .options_page import build_options_html
from .pattern import find_repo_root, load_design, load_pattern, pattern_dir
from .validate import run_all

TEMPLATES = Path(__file__).parent / "templates"


def _resolve(slug_or_path: str) -> Path:
    p = Path(slug_or_path)
    return p.resolve() if p.exists() and (p / "pattern.toml").exists() else pattern_dir(slug_or_path)


def cmd_render(args) -> int:
    d = _resolve(args.pattern)
    meta = load_pattern(d)
    design = load_design(d)
    gauge = args.gauge or meta.stitch
    g, report = design.build(gauge, args.variant)
    if args.check:
        committed = json.loads((d / "dist" / "chart.json").read_text())
        fresh = rows_to_strings(g.a, meta.palette.codes)
        if committed["rows"] != fresh or committed["version"] != meta.version:
            bad = next((i for i, (x, y) in enumerate(zip(committed["rows"], fresh)) if x != y), None)
            print(f"DRIFT: committed dist differs from code (first differing row index {bad}, version {committed['version']} vs {meta.version})")
            return 1
        print("no drift")
        return 0
    out = Path(args.out) if args.out else d / "dist"
    doc = write_dist(g.a, meta, gauge, report, out, variant=args.variant)
    print(f"wrote {out} ({doc['width']}x{doc['height']}, {gauge}, variant {args.variant})")
    return 0


def cmd_check(args) -> int:
    d = _resolve(args.pattern)
    meta = load_pattern(d)
    g, _ = load_design(d).build(meta.stitch, "final")
    ok = True
    for name, passed, detail in run_all(g.a, meta):
        ok &= passed
        print(f"{'ok  ' if passed else 'FAIL'} {name}: {detail}")
    r = subprocess.run([sys.executable, "-m", "pytest", "-q", str(d / "tests")], cwd=find_repo_root())
    ok &= r.returncode == 0
    return 0 if ok else 1


def cmd_new(args) -> int:
    base = Path(args.dir) if args.dir else find_repo_root() / "patterns"
    d = base / args.slug
    if d.exists():
        print(f"{d} already exists"); return 1
    (d / "tests").mkdir(parents=True); (d / "reference").mkdir()
    subs = {"slug": args.slug, "title": args.title}
    (d / "pattern.toml").write_text((TEMPLATES / "pattern.toml.tmpl").read_text().format(**subs))
    (d / "design.py").write_text((TEMPLATES / "design.py.tmpl").read_text().format(**subs))
    (d / "tests" / "test_design.py").write_text((TEMPLATES / "test_design.py.tmpl").read_text().format(**subs))
    (d / "CHANGELOG.md").write_text(f"# {args.slug}\n\n## 0.1.0\nScaffolded.\n")
    print(f"scaffolded {d}")
    return 0


def cmd_options(args) -> int:
    d = _resolve(args.pattern)
    meta = load_pattern(d)
    design = load_design(d)
    out = Path(args.out) if args.out else d / "build" / "options"
    out.mkdir(parents=True, exist_ok=True)
    entries = []
    for variant in design.VARIANTS:
        for gauge in args.gauges.split(","):
            g, report = design.build(gauge, variant)
            doc = chart_json(g.a, meta, gauge, report, variant)
            preview_png(g.a, meta.palette.rgb, out / f"{variant}_{gauge}.png", cw=6)
            per_hr = {"sc": 1100, "hdc": 850, "dc": 700}.get(gauge, 900)
            hours = doc["stats"]["stitches"] / per_hr + sum(doc["stats"]["color_changes_per_row"]["per_row"]) * 3 / 3600
            entries.append({"variant": variant, "gauge": gauge, "width": doc["width"], "height": doc["height"],
                            "size_in": doc["size_in"], "colors": sorted({meta.palette.codes[i] for i in set(g.a.ravel().tolist())}),
                            "changes_mean": doc["stats"]["color_changes_per_row"]["mean"], "changes_max": doc["stats"]["color_changes_per_row"]["max"],
                            "hours": round(hours), "rows": doc["rows"], "palette": doc["palette"], "cell_aspect": doc["cell_aspect"]})
            print(f"{variant} {gauge}: {doc['width']}x{doc['height']} changes mean {doc['stats']['color_changes_per_row']['mean']} max {doc['stats']['color_changes_per_row']['max']}")
    (out / "options.html").write_text(build_options_html(meta.title, entries))
    print(f"wrote {out / 'options.html'}")
    return 0


def cmd_catalog(args) -> int:
    out = Path(args.out) if args.out else find_repo_root() / ".claude" / "skills" / "graphghan" / "assets"
    out.mkdir(parents=True, exist_ok=True)
    gr.set_gauge("sc")
    for name, fn in CATALOG:
        arr, rgb = fn()
        preview_png(np.asarray(arr, dtype=np.uint8), rgb, out / f"{name}.png", cw=10)
    print(f"wrote {len(CATALOG)} thumbnails to {out}")
    return 0


def cmd_site(args) -> int:
    root = find_repo_root()
    build = root / "site" / "build.py"
    if not build.exists():
        print("site/build.py not found (the site plan adds it)"); return 1
    out = Path(args.out) if args.out else root / "site" / "dist"
    if args.site_cmd == "build":
        runpy.run_path(str(build), run_name="__main__", init_globals={"OUT_DIR": out})
        return 0
    runpy.run_path(str(build), run_name="__main__", init_globals={"OUT_DIR": out})
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=str(out), **k)  # noqa: E731
    print(f"serving {out} at http://127.0.0.1:{args.port}/")
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler).serve_forever()
    return 0


def build_parser():
    p = argparse.ArgumentParser(prog="graphghan", description="charts for pixel-chart crafts")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render"); r.add_argument("pattern"); r.add_argument("--gauge"); r.add_argument("--variant", default="final")
    r.add_argument("--out"); r.add_argument("--check", action="store_true"); r.set_defaults(fn=cmd_render)
    c = sub.add_parser("check"); c.add_argument("pattern"); c.set_defaults(fn=cmd_check)
    n = sub.add_parser("new"); n.add_argument("slug"); n.add_argument("--title", required=True); n.add_argument("--dir")
    n.add_argument("--template", default="craigh-na-dun"); n.set_defaults(fn=cmd_new)
    o = sub.add_parser("options"); o.add_argument("pattern"); o.add_argument("--gauges", default="sc,hdc"); o.add_argument("--out")
    o.set_defaults(fn=cmd_options)
    k = sub.add_parser("catalog"); k.add_argument("--out"); k.set_defaults(fn=cmd_catalog)
    s = sub.add_parser("site"); s.add_argument("site_cmd", choices=["build", "serve"]); s.add_argument("--out"); s.add_argument("--port", type=int, default=8765)
    s.set_defaults(fn=cmd_site)
    return p


def main(argv=None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 6: Render and commit the dist, then run the tests**

Run: `uv run graphghan render craigh-na-dun && ls patterns/craigh-na-dun/dist`
Expected: `chart.json chart.png preview-grid.png preview.png written-rows.txt`

Run: `uv run pytest tests/test_cli.py -v`
Expected: 6 PASS

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: graphghan CLI (render, check, new, options, catalog, site) and committed dist"
```

---

### Task 10: Option studies as examples

**Files:**
- Create: `examples/outlander_studies.py`, `examples/README.md`, `tests/test_examples.py`

**Interfaces:**
- Produces: `examples.outlander_studies.STUDIES: dict[str, callable]` with keys `dragonfly-in-amber`, `highland-tartan`, `link-border`; each callable `(gauge_key="sc") -> (Grid, report)`.

- [ ] **Step 1: Write the failing test**

`tests/test_examples.py`:
```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples"))

from outlander_studies import STUDIES  # noqa: E402


def test_studies_build_under_200():
    for name, fn in STUDIES.items():
        g, report = fn("sc")
        assert g.a.shape[0] < 200 and g.a.shape[1] < 200, name
        assert "panel" in report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_examples.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'outlander_studies'`

- [ ] **Step 3: Write the studies**

`examples/outlander_studies.py` (a self-contained palette; these are motif demonstrations, not published patterns):
```python
"""Option studies from the Outlander blanket project, kept as worked examples of the motifs."""
from __future__ import annotations

from graphghan import Grid, grid as gr
from graphghan.compose import text_block
from graphghan.frame import link_frame, twist_frame
from graphghan.motifs import dragonfly, knots, plaid, rings, stones, thistle, twist
from graphghan.palette import Color, Palette
from graphghan.text import FONT_METAMORPHOUS

PAL = Palette([Color("C", "Cream", (242, 232, 213)), Color("K", "Charcoal", (43, 47, 51)), Color("G", "Deep Green", (30, 77, 58)),
               Color("P", "Purple", (107, 45, 92)), Color("B", "Royal Blue", (31, 58, 147)), Color("R", "Burgundy", (139, 30, 45)),
               Color("Y", "Gold", (217, 162, 27))])
C, K, G, P, B, R, Y = (PAL[c] for c in "CKGPBRY")
QUOTE = ["Lord, you gave me", "a rare woman,", "and God!", "I loved her well."]
TEXT_ROWS = {"sc": 17, "hdc": 12}
TEXT_GAP = {"sc": 3, "hdc": 2}


def _text(g, cx, top, gauge):
    size, pitch = TEXT_ROWS[gauge], TEXT_ROWS[gauge] + TEXT_GAP[gauge]
    return text_block(g, QUOTE, cx, top, size, pitch, FONT_METAMORPHOUS, K, C), 3 * pitch + size


def dragonfly_in_amber(gauge="sc"):
    gr.set_gauge(gauge)
    W, H = gr.cols(50.0), gr.rows(49.0)
    g = Grid(W, H, G)
    x0, y0, x1, y1 = twist_frame(g, W, H, G, Y, corners="dot", margin_in=0.25)
    g.rect(x0, y0, x1, y1, C)
    cx = (x0 + x1) // 2
    aw, ah = gr.cols(11.0), gr.rows(11.8)
    amber = dragonfly.amber_drop(aw, ah, C, Y, K, a=5.1, b=5.6)
    df = dragonfly.dragonfly(aw, ah, Y, K, C, K, span=8.0)
    amber[df != Y] = df[df != Y]
    ay, ax = y0 + gr.rows(0.6), cx - aw // 2
    g.blit(amber, ax, ay)
    th = thistle.thistle_scaled(8.5, C, P, G)
    thh, thw = th.shape
    ty, tx = ay + (ah - thh) // 2, ax - gr.cols(1.2) - thw
    g.blit(th, tx, ty, transparent=C); g.blit(th[:, ::-1], x1 - (tx - x0) - thw, ty, transparent=C)
    boxes, text_h = _text(g, cx, ay + ah + gr.rows(1.0), gauge)
    room = y1 - gr.rows(0.5) - (ay + ah + gr.rows(1.0) + text_h + gr.rows(0.6))
    knot_in = min(6.5, room * gr.SH)
    if knot_in >= 2.5:
        kw, kh = gr.cols(knot_in), gr.rows(knot_in); s = knot_in / 5.0
        knot, _ = knots.solomon_knot(kw, kh, C, Y, half=2.4 * s, r_out=1.05 * s, stroke=0.6 * s if s > 0.8 else 0.5)
        g.blit(knot, cx - kw // 2, y1 - gr.rows(0.5) - kh)
    return g, {"panel": (x0, y0, x1, y1), "text": boxes}


def highland_tartan(gauge="sc"):
    gr.set_gauge(gauge)
    W, H = gr.cols(56.0), gr.rows(48.0)
    g = Grid(W, H, G)
    ex, ey = gr.cols(0.5), gr.rows(0.5)
    px, py = gr.cols(2.75), gr.rows(2.75)
    sx, sy = gr.cols(3.5), gr.rows(3.5)
    qx, qy = gr.cols(2.0), gr.rows(2.0)
    gx, gy = gr.cols(0.75), gr.rows(0.75)
    g.blit(plaid.plaid(W, H, 0, 0, {"G": G, "B": B, "Y": Y, "R": R}), 0, 0)
    g.rect(0, 0, W, ey, Y); g.rect(0, H - ey, W, H, Y); g.rect(0, 0, ex, H, Y); g.rect(W - ex, 0, W, H, Y)
    tx0, ty0 = ex + px, ey + py
    top, _ = twist.twist_strip_in(W - 2 * tx0, sy - 2, horizontal=True, bg=G, fg=Y)
    for yy in (ty0, H - ty0 - sy):
        g.rect(tx0, yy, W - tx0, yy + sy, Y); g.blit(top, tx0, yy + 1)
    side, _ = twist.twist_strip_in(H - 2 * ty0, sx - 2, horizontal=False, bg=G, fg=Y)
    for xx in (tx0, W - tx0 - sx):
        g.rect(xx, ty0, xx + sx, H - ty0, Y); g.blit(side, xx + 1, ty0)
    cw, chh = gr.cols(6.0), gr.rows(6.0)
    bx, by = int(round(tx0 + sx / 2.0 - cw / 2.0)), int(round(ty0 + sy / 2.0 - chh / 2.0))
    block, _ = knots.corner_block(cw, chh, G, Y)
    for xx in (bx, W - bx - cw):
        for yy in (by, H - by - chh):
            g.blit(block, xx, yy)
    mx, my = tx0 + sx + qx, ty0 + sy + qy
    g.rect(mx, my, W - mx, H - my, G)
    x0, y0, x1, y1 = mx + gx, my + gy, W - mx - gx, H - my - gy
    g.rect(x0, y0, x1, y1, C)
    cx = (x0 + x1) // 2
    boxes, text_h = _text(g, cx, y0 + gr.rows(0.8), gauge)
    ring, _ = rings.rings(C, Y)
    rh, rw = ring.shape
    g.blit(ring, cx - rw // 2, y1 - gr.rows(0.5) - rh)
    return g, {"panel": (x0, y0, x1, y1), "text": boxes}


def link_border(gauge="sc"):
    gr.set_gauge(gauge)
    W, H = gr.cols(54.0), gr.rows(46.0)
    g = Grid(W, H, G)
    x0, y0, x1, y1 = link_frame(g, W, H, G, Y, P, Y, R)
    g.rect(x0, y0, x1, y1, C)
    cx = (x0 + x1) // 2
    scene_h = gr.rows(12.0)
    g.blit(stones.standing_stones(x1 - x0, scene_h, C, G, K, Y), x0, y0)
    boxes, _ = _text(g, cx, y0 + scene_h + gr.rows(0.8), gauge)
    return g, {"panel": (x0, y0, x1, y1), "text": boxes}


STUDIES = {"dragonfly-in-amber": dragonfly_in_amber, "highland-tartan": highland_tartan, "link-border": link_border}
```

`examples/README.md`:
```markdown
# Examples

`outlander_studies.py` holds the option studies from the first project (dragonfly in amber, Highland
tartan frame, linked-ring border). They are not published patterns; they show how the motifs compose.
Render one with:

    uv run python -c "from examples.outlander_studies import STUDIES; ..."
```

- [ ] **Step 4: Run test**

Run: `uv run pytest tests/test_examples.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "docs: option studies as motif examples"
```

---

### Task 11: CI workflow and lint

**Files:**
- Create: `.github/workflows/ci.yml`, `tests/test_drift.py`

**Interfaces:**
- Consumes: `graphghan render <slug> --check`, `graphghan site build` (from the site plan; the job tolerates its absence until merged).

- [ ] **Step 1: Write the drift test**

`tests/test_drift.py`:
```python
from pathlib import Path

from graphghan.cli import main

ROOT = Path(__file__).resolve().parents[1]


def test_committed_dist_matches_code():
    for d in sorted((ROOT / "patterns").iterdir()):
        if (d / "pattern.toml").exists() and (d / "dist" / "chart.json").exists():
            assert main(["render", str(d), "--check"]) == 0, d.name
```

Run: `uv run pytest tests/test_drift.py -v` → PASS

- [ ] **Step 2: Lint clean**

Run: `uv run ruff check . && uv run ruff format --check .`
Fix anything reported (imports order, unused names) until both pass.

- [ ] **Step 3: Write ci.yml**

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
  pages: write
  id-token: write
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        with: {enable-cache: true}
      - run: uv sync --all-groups
      - run: uv run ruff check .
      - run: uv run pytest -q
      - name: Build site
        run: |
          if [ -f site/build.py ]; then uv run graphghan site build; else echo "no site yet"; mkdir -p site/dist; fi
      - uses: actions/upload-pages-artifact@v3
        with: {path: site/dist}
  deploy:
    if: github.ref == 'refs/heads/main'
    needs: test
    runs-on: ubuntu-latest
    environment: {name: github-pages, url: ${{ steps.deployment.outputs.page_url }}}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "ci: ruff, pytest, drift check, Pages deploy"
```

---

### Task 12: Publish the repo and integrate (runs after the site and skill plans merge)

**Files:**
- Modify: `README.md`
- Create: GitHub repo `tylervick/graphghan`; symlink `~/.claude/skills/graphghan`

- [ ] **Step 1: Create and push the repository**

```bash
gh repo create tylervick/graphghan --public --source=. --description "Chart generator, offline viewer, and Claude skill for graphghan crochet blankets" --push
gh api -X POST repos/tylervick/graphghan/pages -f build_type=workflow || true   # enable Pages via Actions
```
Expected: repo exists, `main` pushed, first CI run green (`gh run watch`).

- [ ] **Step 2: Merge the stream branches**

```bash
git merge --no-ff feat/library && git merge --no-ff feat/site && git merge --no-ff feat/skill
uv run pytest -q && uv run graphghan site build
git push
```
Expected: tests pass; Pages deploy succeeds; `https://tylervick.github.io/graphghan/` lists Craigh na Dun.

- [ ] **Step 3: Symlink the skill and tag the pattern**

```bash
ln -sfn ~/Projects/graphghan/.claude/skills/graphghan ~/.claude/skills/graphghan
git tag -a craigh-na-dun/v1.0.0 -m "Craigh na Dun Blanket 1.0.0" && git push --tags
```

- [ ] **Step 4: Write the README**

Replace `README.md` with: what the repo is (three deliverables), the live site URL, quick start (`uv sync`, `uv run graphghan new`, `options`, `render`, `check`, `site serve`), the pattern folder contract (one paragraph pointing at the spec), the skill (how it is used from Claude Code and the symlink), licensing (MIT code, CC BY-NC-SA patterns, OFL fonts), and a one-line credit that the lettering face is Metamorphous.

- [ ] **Step 5: Phone check and memory**

Open the Pages URL on a phone: install to the home screen, turn on airplane mode, open Craigh na Dun, step three rows in working mode, reload. All of that must work offline. Then record the repo URL, site URL, and the skill symlink in the project memory file `~/.claude/projects/-Users-tyler/memory/project_outlander_blanket.md` (rename to `project_graphghan.md` and update `MEMORY.md`).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "docs: README for the published repo" && git push
```

---

## Self-review

- **Spec coverage:** §3 layout → Tasks 1–9; §3.1 versioning/dist/drift → Tasks 9, 11, 12; §4 contracts → Tasks 3, 7, 8; §5 CLI → Task 9 (site subcommand delegates to the site plan); §7 skill and §6 site → separate plans; §8 tests/CI → every task + Task 11; §9 work plan → Task 12; §10 success criteria → Task 8 step 6 (byte-identical rows), Task 11 (drift), Task 12 (site live, phone check).
- **Placeholders:** none; every code step is complete.
- **Type consistency:** `twist_strip_in(length, thick, horizontal, ..., bg, fg)` used identically in Tasks 5, 6, 10; `write_dist(a, meta, gauge_key, report, out_dir, variant)` in Tasks 7 and 9; `PatternMeta.palette.codes/rgb` in Tasks 7, 9; report keys `panel/scene/text/thistles/dragonfly` in Tasks 8 and its tests.
