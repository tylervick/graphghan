"""Build the static viewer: site/src + patterns/*/dist -> site/dist (or OUT_DIR)."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "site" / "src"
INDEX_KEYS = ("slug", "title", "dedication", "version", "stitch", "width", "height", "size_in")


def load_patterns():
    items = []
    for d in sorted((ROOT / "patterns").iterdir()):
        cj = d / "dist" / "chart.json"
        if cj.exists():
            items.append((d, json.loads(cj.read_text())))
    return items


def make_icons(out: Path):
    """Deep green square, gold moon, three charcoal stones: recognisable at 48 px."""
    (out / "icons").mkdir(parents=True, exist_ok=True)
    for size in (192, 512):
        img = Image.new("RGB", (size, size), (30, 77, 58))
        d = ImageDraw.Draw(img)
        u = size / 16
        d.ellipse([11 * u, 2.5 * u, 14.5 * u, 6 * u], fill=(217, 162, 27))
        for x0, h in ((3.5, 5), (6.5, 7), (9.5, 5.5)):
            d.rectangle([x0 * u, (12 - h) * u, (x0 + 1.8) * u, 12 * u], fill=(43, 47, 51))
        d.rectangle([0, 12 * u, size, size], fill=(24, 60, 45))
        img.save(out / "icons" / f"icon-{size}.png")


def build(out: Path):
    out = Path(out)
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(SRC, out, ignore=shutil.ignore_patterns("pattern.html", "sw.js"))
    make_icons(out)
    template = (SRC / "pattern.html").read_text()
    index = []
    for d, doc in load_patterns():
        pdir = out / "patterns" / doc["slug"]
        pdir.mkdir(parents=True, exist_ok=True)
        for name in ("chart.json", "chart.png", "preview.png", "written-rows.txt"):
            shutil.copy(d / "dist" / name, pdir / name)
        page = (template.replace("{{title}}", doc["title"]).replace("{{slug}}", doc["slug"])
                .replace("{{dedication}}", doc.get("dedication", "")))
        (pdir / "index.html").write_text(page)
        entry = {k: doc[k] for k in INDEX_KEYS}
        entry["colors"] = len(doc["palette"])
        entry["preview"] = f"patterns/{doc['slug']}/preview.png"
        index.append(entry)
    (out / "patterns").mkdir(exist_ok=True)
    (out / "patterns" / "index.json").write_text(json.dumps(index))
    files = sorted(p for p in out.rglob("*") if p.is_file())
    entries = [{"url": p.relative_to(out).as_posix(), "hash": hashlib.sha256(p.read_bytes()).hexdigest()[:12]} for p in files]
    build_hash = hashlib.sha256("".join(e["hash"] for e in entries).encode()).hexdigest()[:12]
    sw = (SRC / "sw.js").read_text().replace("__BUILD_HASH__", build_hash).replace("__PRECACHE__", json.dumps([e["url"] for e in entries]))
    (out / "sw.js").write_text(sw)
    (out / "build.json").write_text(json.dumps({"hash": build_hash, "files": entries}))
    return out, index, build_hash


if __name__ == "__main__":
    target = globals().get("OUT_DIR") or ROOT / "site" / "dist"
    o, idx, h = build(target)
    print(f"built {o} ({len(idx)} patterns, build {h})")
