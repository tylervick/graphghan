import json
import shutil
from pathlib import Path

import pytest

from graphghan import publish
from graphghan.pattern import load_design, load_pattern

FIX = Path(__file__).parent / "fixtures" / "minimal"


def copy_minimal(tmp_path, publish_lines='[publish]\ncharts = [["final", "sc"], ["final", "square"]]\n'):
    d = tmp_path / "minimal"
    shutil.copytree(FIX, d, ignore=shutil.ignore_patterns("__pycache__", "dist"))
    (d / "pattern.toml").write_text((d / "pattern.toml").read_text() + "\n" + publish_lines)
    return d


def test_chart_key():
    assert publish.chart_key("final", "sc") == "final-sc"


def test_published_validates_entries(tmp_path):
    d = copy_minimal(tmp_path)
    meta, design = load_pattern(d), load_design(d)
    assert publish.published(meta, design) == [("final", "sc"), ("final", "square")]
    bads = (
        'charts = [["nope", "sc"]]',
        'charts = [["final", "bogus"]]',
        'charts = [["final", "sc"], ["final", "sc"]]',
    )
    for i, bad in enumerate(bads):
        b = copy_minimal(tmp_path / f"bad{i}", f"[publish]\n{bad}\n")
        with pytest.raises(ValueError):
            publish.published(load_pattern(b), load_design(b))


def test_render_published_writes_tree_and_default_copy(tmp_path):
    d = copy_minimal(tmp_path)
    docs = publish.render_published(d, load_pattern(d), load_design(d))
    assert [x["chart"]["gauge_key"] for x in docs] == ["sc", "square"]
    for key in ("final-sc", "final-square"):
        for name in publish.TOP_LEVEL_FILES:
            assert (d / "dist" / "charts" / key / name).exists(), (key, name)
    top = json.loads((d / "dist" / "chart.json").read_text())
    assert top == json.loads((d / "dist" / "charts" / "final-sc" / "chart.json").read_text())
    assert top["chart"]["width"] == 14 and docs[1]["chart"]["width"] == 16


def test_render_published_removes_stale_dirs(tmp_path):
    d = copy_minimal(tmp_path)
    stale = d / "dist" / "charts" / "old-thing"
    stale.mkdir(parents=True)
    (stale / "chart.json").write_text("{}")
    publish.render_published(d, load_pattern(d), load_design(d))
    assert not stale.exists()


def test_check_published_reports_missing_drift_and_stale(tmp_path):
    d = copy_minimal(tmp_path)
    meta, design = load_pattern(d), load_design(d)
    assert publish.check_published(d, meta, design)  # nothing committed yet: missing
    publish.render_published(d, meta, design)
    assert publish.check_published(d, meta, design) == []
    sq = d / "dist" / "charts" / "final-square" / "chart.json"
    doc = json.loads(sq.read_text())
    doc["rows"][0] = doc["rows"][0].replace("A", "B", 1)
    sq.write_text(json.dumps(doc))
    problems = publish.check_published(d, meta, design)
    assert len(problems) == 1 and "final-square" in problems[0] and "rows" in problems[0]
    (d / "dist" / "charts" / "zzz").mkdir()
    assert any("stale" in p for p in publish.check_published(d, meta, design))


def test_drift_message_names_keys_and_first_row():
    a = {"rows": ["1A", "1B"], "stats": 1}
    b = {"rows": ["1A", "1A"], "stats": 1}
    assert publish.drift_message(a, a) is None
    assert (
        publish.drift_message(a, b) == "DRIFT: chart.json differs in keys: rows (first differing row index 1)"
    )


def test_drift_message_ignores_the_generator_version():
    a = {"rows": ["1A"], "generator": {"name": "graphghan", "version": "0.2.0"}}
    b = {"rows": ["1A"], "generator": {"name": "graphghan", "version": "0.3.0"}}
    assert publish.drift_message(a, b) is None
    assert publish.drift_message(a, b | {"rows": ["1B"]}) is not None
    assert a["generator"]["version"] == "0.2.0"  # inputs untouched


def test_render_published_leaves_the_tree_alone_when_a_build_fails(tmp_path):
    d = copy_minimal(tmp_path)
    meta, design = load_pattern(d), load_design(d)
    publish.render_published(d, meta, design)
    before = {
        p.relative_to(d).as_posix(): p.read_bytes() for p in sorted((d / "dist").rglob("*")) if p.is_file()
    }
    assert before

    real_build = design.build

    def build(gauge_key="sc", variant="final"):
        if gauge_key == "square":  # the second [publish] entry
            raise RuntimeError("boom")
        return real_build(gauge_key, variant)

    design.build = build
    with pytest.raises(RuntimeError, match="boom"):
        publish.render_published(d, meta, design)
    after = {
        p.relative_to(d).as_posix(): p.read_bytes() for p in sorted((d / "dist").rglob("*")) if p.is_file()
    }
    assert after == before
