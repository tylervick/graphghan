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
