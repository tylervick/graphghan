import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from graphghan.cli import main

ROOT = Path(__file__).resolve().parents[1]
FIX = Path(__file__).parent / "fixtures" / "minimal"


def run(*args):
    return subprocess.run(
        [sys.executable, "-m", "graphghan.cli", *args], cwd=ROOT, capture_output=True, text=True
    )


def test_render_writes_dist_and_check_passes(tmp_path):
    assert main(["render", "craigh-na-dun", "--out", str(tmp_path)]) == 0
    doc = json.loads((tmp_path / "chart.json").read_text())
    assert (
        doc["schema"] == 2 and doc["chart"]["width"] == 189 and doc["pattern"]["dedication"] == "For Meaghan"
    )
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
    assert json.loads((tmp_path / "out" / "chart.json").read_text())["pattern"]["id"] == "test-scaffold"
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
    assert "3 passed" in scaffold_tests.stdout, scaffold_tests.stdout + scaffold_tests.stderr


def test_check_missing_pattern_is_usage_error():
    assert main(["check", "nonexistent-slug-xyz"]) == 2


def test_options_page(tmp_path):
    assert main(["options", "craigh-na-dun", "--gauges", "sc", "--out", str(tmp_path)]) == 0
    html = (tmp_path / "options.html").read_text()
    assert "final" in html and "plain-foot" in html and (tmp_path / "final_sc.png").exists()
    assert "[A-Za-z]{1,3}" in html


def test_options_entry_without_a_derived_size(tmp_path):
    """A gauge whose unit doesn't match the grid's cell kind (C2C-style: gauge counts tiles,
    chart.cell is absent so cells default to stitches) must not crash the options page.
    finished_size withholds the size (#48) and the rendered entry simply carries none."""
    copy = tmp_path / "minimal-tiles"
    shutil.copytree(FIX, copy, ignore=shutil.ignore_patterns("__pycache__"))
    toml_path = copy / "pattern.toml"
    toml_path.write_text(toml_path.read_text() + '\n[stitch.square]\nunit = "tiles"\n')
    out = tmp_path / "out"
    assert main(["options", str(copy), "--gauges", "square", "--out", str(out)]) == 0
    html = (out / "options.html").read_text()
    assert "final" in html and "square" in html
    assert "Finished" not in html  # size withheld: gauge counts tiles, chart cells are stitches
    entry = json.loads(re.search(r"const DATA=(\{.*\});", html).group(1))["final_square"]
    assert entry["size_in"] is None
    assert entry["hours"] is not None  # stitches count is still present; only the size withholds


def test_catalog(tmp_path):
    assert main(["catalog", "--out", str(tmp_path)]) == 0
    assert (tmp_path / "twist-strip.png").exists() and (tmp_path / "standing-stones.png").exists()


def test_usage_error():
    assert main(["render"]) == 2


def test_render_rejects_unknown_gauge(tmp_path, capsys):
    assert main(["render", "craigh-na-dun", "--gauge", "bogus", "--out", str(tmp_path)]) == 2
    err = capsys.readouterr().err
    assert "unknown gauge 'bogus'" in err and "dc" in err


def test_render_rejects_unknown_variant(tmp_path):
    assert main(["render", "craigh-na-dun", "--variant", "bogus", "--out", str(tmp_path)]) == 2


def test_render_check_detects_drift(tmp_path):
    copy = tmp_path / "craigh-na-dun-copy"
    shutil.copytree(ROOT / "patterns" / "craigh-na-dun", copy, ignore=shutil.ignore_patterns("__pycache__"))
    toml_path = copy / "pattern.toml"
    original = toml_path.read_text()
    changed = original.replace('hex = "#F2E8D5"', 'hex = "#000000"', 1)
    assert changed != original
    toml_path.write_text(changed)
    assert main(["render", str(copy), "--check"]) == 1


def test_render_check_rejects_out(tmp_path, capsys):
    assert main(["render", "craigh-na-dun", "--check", "--out", str(tmp_path)]) == 2
    assert "--check cannot be combined with --out" in capsys.readouterr().err
    assert not (tmp_path / "chart.json").exists()


def test_export_rejects_a_chart_key_that_is_a_path(capsys):
    assert main(["export", "craigh-na-dun", "--format", "csv", "--chart", "../x"]) == 2
    assert "invalid --chart '../x'" in capsys.readouterr().err


def test_render_adhoc_requires_out_and_never_touches_dist(tmp_path):
    assert main(["render", "craigh-na-dun", "--gauge", "hdc"]) == 2
    assert main(["render", "craigh-na-dun", "--variant", "plain-foot"]) == 2
    assert main(["render", "craigh-na-dun", "--gauge", "hdc", "--check"]) == 2
    assert main(["render", "craigh-na-dun", "--variant", "plain-foot", "--out", str(tmp_path)]) == 0
    assert json.loads((tmp_path / "chart.json").read_text())["chart"]["variant"] == "plain-foot"


def test_committed_dist_publishes_sc_and_hdc():
    dist = ROOT / "patterns" / "craigh-na-dun" / "dist"
    for key in ("final-sc", "final-hdc"):
        assert (dist / "charts" / key / "chart.json").exists()
    top = json.loads((dist / "chart.json").read_text())
    assert (
        top["chart"]["id"]
        == json.loads((dist / "charts" / "final-sc" / "chart.json").read_text())["chart"]["id"]
    )


def test_export_formats_and_default_paths(tmp_path, monkeypatch):
    monkeypatch.chdir(ROOT)
    for fmt in ("png", "oxs", "csv"):
        out = tmp_path / f"chart.{fmt}"
        assert main(["export", "craigh-na-dun", "--format", fmt, "--out", str(out)]) == 0
        assert out.exists() and out.stat().st_size > 0
    assert (
        main(
            [
                "export",
                "craigh-na-dun",
                "--format",
                "csv",
                "--chart",
                "final-hdc",
                "--out",
                str(tmp_path / "hdc.csv"),
            ]
        )
        == 0
    )
    assert len((tmp_path / "hdc.csv").read_text().splitlines()) == 115
    assert main(["export", "craigh-na-dun", "--format", "csv", "--chart", "final-nope"]) == 1
    assert main(["export", "craigh-na-dun", "--format", "csv"]) == 0
    default = ROOT / "patterns" / "craigh-na-dun" / "build" / "exports" / "final-sc.csv"
    assert default.exists()
    default.unlink()


def test_export_pdf_writes_a_printable_pattern(tmp_path):
    out = tmp_path / "craigh.pdf"
    assert main(["export", "craigh-na-dun", "--format", "pdf", "--out", str(out)]) == 0
    assert out.read_bytes()[:5] == b"%PDF-"
