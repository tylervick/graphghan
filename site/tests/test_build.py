import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "site"))

from build import build  # noqa: E402


def test_build_layout_and_contracts(tmp_path):
    out, index, h = build(tmp_path / "dist")
    assert (out / "index.html").exists() and (out / "sw.js").exists() and (out / "manifest.webmanifest").exists()
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
    listed = set(json.loads((out / "build.json").read_text())["files"][i]["url"] for i in range(len(json.loads((out / "build.json").read_text())["files"])))
    actual = {p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file()} - {"sw.js", "build.json"}
    assert listed == actual
    assert "patterns/craigh-na-dun/index.html" in listed and "patterns/index.json" in listed
