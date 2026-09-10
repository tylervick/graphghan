import json
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "site"))

import build as build_module  # noqa: E402
from build import build  # noqa: E402


def test_build_layout_and_contracts(tmp_path):
    out, index, h = build(tmp_path / "dist")
    assert (
        (out / "index.html").exists() and (out / "sw.js").exists() and (out / "manifest.webmanifest").exists()
    )
    assert len(h) == 12
    idx = json.loads((out / "patterns" / "index.json").read_text())
    assert index == idx and any(p["slug"] == "craigh-na-dun" for p in idx)
    p = out / "patterns" / "craigh-na-dun"
    for name in ("index.html", "chart.json", "chart.png", "preview.png", "written-rows.txt"):
        assert (p / name).exists(), name
    page = (p / "index.html").read_text()
    assert "Craigh na Dun Blanket" in page and "{{" not in page and '<base href="../../">' in page
    doc = json.loads((p / "chart.json").read_text())
    assert doc["schema"] == 1 and len(doc["rows"]) == doc["height"]
    for name in ("icon-192.png", "icon-512.png"):
        assert (out / "icons" / name).exists()


def test_precache_covers_every_file(tmp_path):
    out, _, h = build(tmp_path / "dist")
    sw = (out / "sw.js").read_text()
    assert "__PRECACHE__" not in sw and h in sw
    listed = set(
        json.loads((out / "build.json").read_text())["files"][i]["url"]
        for i in range(len(json.loads((out / "build.json").read_text())["files"]))
    )
    actual = {p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file()} - {"sw.js", "build.json"}
    assert listed == actual
    assert "patterns/craigh-na-dun/index.html" in listed and "patterns/index.json" in listed


def _make_fake_pattern(tmp_path, name, doc):
    """Set up a fake patterns/<name>/dist/ directory build() can copy from."""
    pattern_dir = tmp_path / "src-patterns" / name
    dist_dir = pattern_dir / "dist"
    dist_dir.mkdir(parents=True)
    (dist_dir / "chart.json").write_text(json.dumps(doc), encoding="utf-8")
    (dist_dir / "chart.png").write_bytes(b"\x89PNG\r\n\x1a\n")
    (dist_dir / "preview.png").write_bytes(b"\x89PNG\r\n\x1a\n")
    (dist_dir / "written-rows.txt").write_text("Row 1 (RS): 1 A  (1 sts)\n", encoding="utf-8")
    return pattern_dir


def test_build_escapes_title_dedication_and_slug(tmp_path, monkeypatch):
    doc = {
        "slug": "tam-lin",
        "title": 'Tam & "Lin" <3',
        "version": "1.0",
        "stitch": "sc",
        "width": 1,
        "height": 1,
        "size_in": [1, 1],
        "palette": [{"code": "A", "name": "Alpha", "hex": "#000000", "yarn": "Worsted", "use": "Main"}],
    }
    pattern_dir = _make_fake_pattern(tmp_path, "tam-lin", doc)
    monkeypatch.setattr(build_module, "load_patterns", lambda: [(pattern_dir, doc)])

    out, index, _ = build_module.build(tmp_path / "dist")

    page = (out / "patterns" / "tam-lin" / "index.html").read_text(encoding="utf-8")
    assert "Tam &amp; &quot;Lin&quot; &lt;3" in page
    assert 'Tam & "Lin" <3' not in page
    # a pattern without a dedication must not crash the build
    assert index[0]["dedication"] == ""


def test_build_rejects_invalid_slug(tmp_path, monkeypatch):
    doc = {
        "slug": "../evil",
        "title": "Evil",
        "version": "1.0",
        "stitch": "sc",
        "width": 1,
        "height": 1,
        "size_in": [1, 1],
        "palette": [{"code": "A", "name": "Alpha", "hex": "#000000", "yarn": "Worsted", "use": "Main"}],
    }
    pattern_dir = _make_fake_pattern(tmp_path, "evil", doc)
    monkeypatch.setattr(build_module, "load_patterns", lambda: [(pattern_dir, doc)])

    with pytest.raises(ValueError, match="invalid slug"):
        build_module.build(tmp_path / "dist")


def test_pattern_chart_json_contract(tmp_path):
    out, index, _ = build(tmp_path / "dist")
    required_keys = {
        "schema",
        "slug",
        "title",
        "version",
        "stitch",
        "gauge",
        "cell_aspect",
        "width",
        "height",
        "size_in",
        "palette",
        "rows",
        "stats",
        "notes",
    }
    run_re = re.compile(r"(\d+)([A-Za-z])")
    for entry in index:
        slug = entry["slug"]
        pdir = out / "patterns" / slug
        doc = json.loads((pdir / "chart.json").read_text(encoding="utf-8"))

        missing = required_keys - doc.keys()
        assert not missing, f"{slug} missing keys {missing}"
        assert {"st_per_in", "rows_per_in"} <= doc["gauge"].keys(), slug

        for p in doc["palette"]:
            assert {"code", "name", "hex", "yarn", "use"} <= p.keys(), (slug, p)

        stats = doc["stats"]
        for p in doc["palette"]:
            code = p["code"]
            assert code in stats["counts"], (slug, code)
            assert code in stats["yards_est"], (slug, code)
            assert code in stats["skeins_364yd"], (slug, code)

        assert len(stats["color_changes_per_row"]["per_row"]) == doc["height"], slug

        notes = doc["notes"]
        assert isinstance(notes["setup"], list), slug
        assert isinstance(notes["colors"], list), slug

        width = doc["width"]
        for row in doc["rows"]:
            runs = run_re.findall(row)
            assert sum(int(n) for n, _ in runs) == width, (slug, row)

        written_lines = (pdir / "written-rows.txt").read_text(encoding="utf-8").splitlines()
        first_line = written_lines[0]
        assert first_line.startswith("Row 1 ("), (slug, first_line)
        # written-rows.txt runs are "N CODE" (space-separated); drop the
        # row label and trailing "(N sts)" before pulling out run lengths.
        body = re.sub(r"\s+\(\d+ sts\)\s*$", "", first_line.split(": ", 1)[1])
        first_runs = [int(n) for n, _ in re.findall(r"(\d+)\s+([A-Za-z]+)", body)]
        last_row_runs = [int(n) for n, _ in run_re.findall(doc["rows"][-1])]
        assert first_runs == list(reversed(last_row_runs)), slug
