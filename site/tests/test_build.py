import json
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "site"))

import build as build_module  # noqa: E402
from build import build  # noqa: E402


def fake_doc(slug, title, dedication=""):
    return {
        "schema": 2,
        "pattern": {"id": slug, "title": title, "version": "1.0", "dedication": dedication, "quote": ""},
        "chart": {"id": "sha256:" + "0" * 64, "variant": "final", "gauge_key": "sc", "width": 1, "height": 1},
        "generator": {"name": "graphghan", "version": "0"},
        "palette": [
            {"code": "A", "name": "Alpha", "hex": "#000000", "yarn": {"note": "Worsted"}, "use": "Main"}
        ],
        "rows": ["1A"],
        "gauge": {"stitches": 14, "rows": 16, "over": {"value": 4, "unit": "in"}, "stitch": "sc"},
        "technique": {
            "type": "rows",
            "start": "bottom",
            "first_side": "RS",
            "rs_direction": "rtl",
            "turn": True,
        },
        "instructions": [],
        "stats": {
            "stitches": 1,
            "counts": {"A": 1},
            "yards_est": {"A": 1},
            "skeins_364yd": {"A": 0.1},
            "color_changes_per_row": {"mean": 0, "max": 0, "per_row": [0]},
        },
    }


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
    assert doc["schema"] == 2 and len(doc["rows"]) == doc["chart"]["height"]
    for name in ("icon-192.png", "icon-512.png"):
        assert (out / "icons" / name).exists()
    # the schemas are served at the $id each one claims
    for name in ("chart.schema.json", "progress.schema.json"):
        assert (out / "schema" / name).exists(), name
        assert json.loads((out / "schema" / name).read_text())["$id"].endswith(f"/schema/{name}")


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


def _add_chart_dirs(pattern_dir, top, gauges):
    """One dist/charts/final-<gauge>/ per gauge, all sharing top's chart.id."""
    for gauge in gauges:
        sub = pattern_dir / "dist" / "charts" / f"final-{gauge}"
        sub.mkdir(parents=True)
        doc = json.loads(json.dumps(top))
        doc["chart"]["gauge_key"] = doc["gauge"]["stitch"] = gauge
        (sub / "chart.json").write_text(json.dumps(doc), encoding="utf-8")
        (sub / "preview.png").write_bytes(b"\x89PNG\r\n\x1a\n")


def test_published_docs_picks_the_default_by_variant_and_gauge(tmp_path):
    # Two gauges of one design can hash to the same chart.id; only (variant, gauge_key) names a
    # chart. No pattern.toml here, so the fallback order is alphabetical and final-hdc comes first:
    # matching on chart.id would pick it, and it is not the chart at the top level.
    top = fake_doc("twin", "Twin")
    pattern_dir = _make_fake_pattern(tmp_path, "twin", top)
    _add_chart_dirs(pattern_dir, top, ("hdc", "sc"))
    published = build_module.published_docs(pattern_dir)
    assert [p[0] for p in published] == ["charts/final-sc/chart.json", "charts/final-hdc/chart.json"]
    assert published[0][1]["chart"]["gauge_key"] == top["chart"]["gauge_key"] == "sc"


def test_published_docs_orders_the_rest_the_way_publish_does(tmp_path):
    top = fake_doc("triple", "Triple")
    pattern_dir = _make_fake_pattern(tmp_path, "triple", top)
    (pattern_dir / "pattern.toml").write_text(
        (ROOT / "tests" / "fixtures" / "minimal" / "pattern.toml").read_text()
        + '\n[publish]\ncharts = [["final", "sc"], ["final", "hdc"], ["final", "dc"]]\n',
        encoding="utf-8",
    )
    _add_chart_dirs(pattern_dir, top, ("sc", "hdc", "dc"))
    published = build_module.published_docs(pattern_dir)
    # not the alphabetical final-dc, final-hdc, final-sc
    assert [p[0] for p in published] == [f"charts/final-{g}/chart.json" for g in ("sc", "hdc", "dc")]


def test_published_docs_rejects_a_top_level_chart_of_its_own(tmp_path):
    top = fake_doc("orphan", "Orphan")
    pattern_dir = _make_fake_pattern(tmp_path, "orphan", top)
    _add_chart_dirs(pattern_dir, top, ("hdc",))
    with pytest.raises(ValueError, match="not one of dist/charts"):
        build_module.published_docs(pattern_dir)


def test_build_escapes_title_dedication_and_slug(tmp_path, monkeypatch):
    doc = fake_doc("tam-lin", 'Tam & "Lin" <3')
    pattern_dir = _make_fake_pattern(tmp_path, "tam-lin", doc)
    monkeypatch.setattr(build_module, "load_patterns", lambda: [(pattern_dir, doc)])

    out, index, _ = build_module.build(tmp_path / "dist")

    page = (out / "patterns" / "tam-lin" / "index.html").read_text(encoding="utf-8")
    assert "Tam &amp; &quot;Lin&quot; &lt;3" in page
    assert 'Tam & "Lin" <3' not in page
    # a pattern without a dedication must not crash the build
    assert index[0]["dedication"] == ""


def test_build_rejects_invalid_slug(tmp_path, monkeypatch):
    doc = fake_doc("../evil", "Evil")
    pattern_dir = _make_fake_pattern(tmp_path, "evil", doc)
    monkeypatch.setattr(build_module, "load_patterns", lambda: [(pattern_dir, doc)])

    with pytest.raises(ValueError, match="invalid slug"):
        build_module.build(tmp_path / "dist")


def test_pattern_chart_json_contract(tmp_path):
    out, index, _ = build(tmp_path / "dist")
    run_re = re.compile(r"(\d+)([A-Za-z]{1,3})")
    for entry in index:
        slug = entry["slug"]
        pdir = out / "patterns" / slug
        doc = json.loads((pdir / "chart.json").read_text(encoding="utf-8"))
        assert doc["schema"] == 2
        assert {
            "pattern",
            "chart",
            "palette",
            "rows",
            "gauge",
            "technique",
            "instructions",
            "stats",
        } <= doc.keys(), slug
        assert {"id", "title", "version"} <= doc["pattern"].keys() and doc["pattern"]["id"] == slug
        assert {"id", "width", "height"} <= doc["chart"].keys()
        assert {"stitches", "rows", "over"} <= doc["gauge"].keys()
        for p in doc["palette"]:
            assert {"code", "name", "hex", "yarn", "use"} <= p.keys(), (slug, p)
            assert isinstance(p["yarn"], dict)
        stats = doc["stats"]
        for p in doc["palette"]:
            code = p["code"]
            assert code in stats["counts"] and code in stats["yards_est"] and code in stats["skeins_364yd"], (
                slug,
                code,
            )
        assert len(stats["color_changes_per_row"]["per_row"]) == doc["chart"]["height"], slug
        for sec in doc["instructions"]:
            assert {"title", "text"} <= sec.keys(), slug
        width = doc["chart"]["width"]
        for row in doc["rows"]:
            assert sum(int(n) for n, _ in run_re.findall(row)) == width, (slug, row)
        assert entry["size_in"] == [54.0, 46.0] if slug == "craigh-na-dun" else True
        written_lines = (pdir / "written-rows.txt").read_text(encoding="utf-8").splitlines()
        first_line = written_lines[0]
        assert first_line.startswith("Row 1 ("), (slug, first_line)
        body = re.sub(r"\s+\(\d+ sts\)\s*$", "", first_line.split(": ", 1)[1])
        first_runs = [int(n) for n, _ in re.findall(r"(\d+)\s+([A-Za-z]+)", body)]
        last_row_runs = [int(n) for n, _ in run_re.findall(doc["rows"][-1])]
        assert first_runs == list(reversed(last_row_runs)), slug


def test_manifest_and_charts_tree(tmp_path):
    out, index, _ = build(tmp_path / "dist")
    entry = next(e for e in index if e["slug"] == "craigh-na-dun")
    assert entry["manifest"] == "patterns/craigh-na-dun/pattern.json" and entry["charts"] == 2
    pdir = out / "patterns" / "craigh-na-dun"
    m = json.loads((pdir / "pattern.json").read_text(encoding="utf-8"))
    assert m["schema"] == 1 and m["id"] == "craigh-na-dun" and m["title"] == "Craigh na Dun Blanket"
    assert m["license"] == "CC-BY-NC-SA-4.0" and m["preview"] == "preview.png"
    assert [p["code"] for p in m["palette"]] == ["C", "K", "G", "P", "Y"] and set(m["palette"][0]) == {
        "code",
        "name",
        "hex",
    }
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", m["updated"])
    charts = m["charts"]
    assert [c["gauge_key"] for c in charts] == ["sc", "hdc"] and [c["default"] for c in charts] == [
        True,
        False,
    ]
    top = json.loads((pdir / "chart.json").read_text(encoding="utf-8"))
    assert charts[0]["id"] == top["chart"]["id"]
    for c in charts:
        assert (pdir / c["path"]).exists() and (pdir / c["preview"]).exists(), c
        doc = json.loads((pdir / c["path"]).read_text(encoding="utf-8"))
        assert doc["chart"]["id"] == c["id"]
        assert {
            "variant",
            "width",
            "height",
            "size",
            "stitch",
            "colors",
            "stitches",
            "changes_per_row",
            "yards_est",
        } <= c.keys()
        assert c["size"]["unit"] == "in" and c["stitches"] == c["width"] * c["height"]
    assert charts[0]["size"] == {"width": 54.0, "height": 46.0, "unit": "in"}
    assert charts[0]["path"] == "charts/final-sc/chart.json"


def test_manifest_for_pattern_without_charts_dir(tmp_path, monkeypatch):
    doc = fake_doc("solo", "Solo")
    pattern_dir = _make_fake_pattern(tmp_path, "solo", doc)
    monkeypatch.setattr(build_module, "load_patterns", lambda: [(pattern_dir, doc)])
    out, index, _ = build_module.build(tmp_path / "dist")
    m = json.loads((out / "patterns" / "solo" / "pattern.json").read_text(encoding="utf-8"))
    assert (
        len(m["charts"]) == 1 and m["charts"][0]["path"] == "chart.json" and m["charts"][0]["default"] is True
    )
    assert index[0]["charts"] == 1
