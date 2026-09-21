"""The committed grid fixtures are what generate.py draws and what the reader answers today."""

import json
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRID = ROOT / "fixtures" / "import" / "grid"


def test_committed_grid_fixtures_regenerate_identically(tmp_path):
    gen = runpy.run_path(str(GRID / "generate.py"))
    for name, (img, want_cells) in gen["images"]().items():
        img.save(tmp_path / f"{name}.png", optimize=True)
        assert (tmp_path / f"{name}.png").read_bytes() == (GRID / f"{name}.png").read_bytes(), name
        want = json.loads((GRID / f"{name}.json").read_text(encoding="utf-8"))
        assert gen["answer"](img, want_cells) == want, name


def test_the_answers_are_what_the_unit_tests_assert():
    one = json.loads((GRID / "one-grid.json").read_text(encoding="utf-8"))
    assert [(r["cols"], r["rows"]) for r in one["regions"]] == [(37, 29)]
    two = json.loads((GRID / "two-grids.json").read_text(encoding="utf-8"))
    assert sorted((r["cols"], r["rows"]) for r in two["regions"]) == [(12, 20), (15, 20)]
    assert json.loads((GRID / "text-page.json").read_text(encoding="utf-8"))["regions"] == []
