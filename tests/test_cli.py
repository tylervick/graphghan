import json
import subprocess
import sys
from pathlib import Path

from graphghan.cli import main

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run(
        [sys.executable, "-m", "graphghan.cli", *args], cwd=ROOT, capture_output=True, text=True
    )


def test_render_writes_dist_and_check_passes(tmp_path):
    assert main(["render", "craigh-na-dun", "--out", str(tmp_path)]) == 0
    doc = json.loads((tmp_path / "chart.json").read_text())
    assert doc["schema"] == 1 and doc["width"] == 189 and doc["dedication"] == "For Meaghan"
    assert (tmp_path / "chart.png").exists() and (tmp_path / "written-rows.txt").exists()
    assert main(["render", "craigh-na-dun", "--check"]) == 0  # committed dist matches


def test_check_runs_invariants_and_tests():
    r = run("check", "craigh-na-dun")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "row totals" in r.stdout and "passed" in r.stdout


def test_new_scaffolds_and_renders(tmp_path, monkeypatch):
    monkeypatch.chdir(ROOT)
    assert main(["new", "test-scaffold", "--title", "Test Scaffold", "--dir", str(tmp_path)]) == 0
    d = tmp_path / "test-scaffold"
    assert (
        (d / "pattern.toml").exists()
        and (d / "design.py").exists()
        and (d / "tests" / "test_design.py").exists()
    )
    assert main(["render", str(d), "--out", str(tmp_path / "out")]) == 0
    assert json.loads((tmp_path / "out" / "chart.json").read_text())["slug"] == "test-scaffold"
    assert main(["render", str(d), "--check"]) == 1  # no committed dist yet
    lint = subprocess.run(
        [sys.executable, "-m", "ruff", "check", "--config", str(ROOT / "pyproject.toml"), str(d)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert lint.returncode == 0, lint.stdout + lint.stderr
    scaffold_tests = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", str(d / "tests")], cwd=ROOT, capture_output=True, text=True
    )
    assert scaffold_tests.returncode == 0, scaffold_tests.stdout + scaffold_tests.stderr


def test_check_missing_pattern_is_usage_error():
    assert main(["check", "nonexistent-slug-xyz"]) == 2


def test_options_page(tmp_path):
    assert main(["options", "craigh-na-dun", "--gauges", "sc", "--out", str(tmp_path)]) == 0
    html = (tmp_path / "options.html").read_text()
    assert "final" in html and "plain-foot" in html and (tmp_path / "final_sc.png").exists()


def test_catalog(tmp_path):
    assert main(["catalog", "--out", str(tmp_path)]) == 0
    assert (tmp_path / "twist-strip.png").exists() and (tmp_path / "standing-stones.png").exists()


def test_usage_error():
    assert main(["render"]) == 2
