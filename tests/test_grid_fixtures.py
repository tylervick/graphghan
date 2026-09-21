"""The committed grid fixtures are what generate.py draws and what the reader answers today."""

import json
import runpy
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GRID = ROOT / "fixtures" / "import" / "grid"


def test_committed_grid_fixtures_regenerate_identically():
    # Pixels, not bytes: zlib packs the same image differently on Linux and macOS.
    gen = runpy.run_path(str(GRID / "generate.py"))
    for name, (img, want_cells) in gen["images"]().items():
        committed = Image.open(GRID / f"{name}.png").convert("RGB")
        assert np.array_equal(np.asarray(img), np.asarray(committed)), name
        want = json.loads((GRID / f"{name}.json").read_text(encoding="utf-8"))
        assert gen["answer"](committed, want_cells) == want, name


def test_the_answers_are_what_the_unit_tests_assert():
    one = json.loads((GRID / "one-grid.json").read_text(encoding="utf-8"))
    assert [(r["cols"], r["rows"]) for r in one["regions"]] == [(37, 29)]
    two = json.loads((GRID / "two-grids.json").read_text(encoding="utf-8"))
    assert sorted((r["cols"], r["rows"]) for r in two["regions"]) == [(12, 20), (15, 20)]
    assert json.loads((GRID / "text-page.json").read_text(encoding="utf-8"))["regions"] == []
