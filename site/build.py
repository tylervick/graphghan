"""Build the static viewer: site/src + patterns/*/dist -> site/dist (or OUT_DIR)."""

from __future__ import annotations

import hashlib
import html
import json
import re
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "site" / "src"
SLUG_RE = re.compile(r"[a-z0-9-]+")


def finished_size_in(doc) -> list[float]:
    g = doc["gauge"]
    per = g["over"]["value"]
    w = doc["chart"]["width"] / (g["stitches"] / per)
    h = doc["chart"]["height"] / (g["rows"] / per)
    if g["over"]["unit"] == "cm":
        w, h = w / 2.54, h / 2.54
    return [round(w, 1), round(h, 1)]


def index_entry(doc) -> dict:
    p, c = doc["pattern"], doc["chart"]
    return {
        "slug": p["id"],
        "title": p["title"],
        "dedication": p.get("dedication", ""),
        "version": p["version"],
        "stitch": doc["gauge"].get("stitch", ""),
        "width": c["width"],
        "height": c["height"],
        "size_in": finished_size_in(doc),
        "colors": len(doc["palette"]),
        "preview": f"patterns/{p['id']}/preview.png",
    }


def load_patterns():
    items = []
    for d in sorted((ROOT / "patterns").iterdir()):
        cj = d / "dist" / "chart.json"
        if cj.exists():
            items.append((d, json.loads(cj.read_text(encoding="utf-8"))))
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
    template = (SRC / "pattern.html").read_text(encoding="utf-8")
    index = []
    for d, doc in load_patterns():
        slug = doc["pattern"]["id"]
        if not SLUG_RE.fullmatch(slug):
            raise ValueError(f"invalid slug {slug!r}")
        pdir = out / "patterns" / slug
        pdir.mkdir(parents=True, exist_ok=True)
        for name in ("chart.json", "chart.png", "preview.png", "written-rows.txt"):
            shutil.copy(d / "dist" / name, pdir / name)
        page = (
            template.replace("{{title}}", html.escape(doc["pattern"]["title"], quote=True))
            .replace("{{slug}}", html.escape(slug, quote=True))
            .replace("{{dedication}}", html.escape(doc["pattern"].get("dedication", ""), quote=True))
        )
        (pdir / "index.html").write_text(page, encoding="utf-8")
        entry = index_entry(doc)
        index.append(entry)
    (out / "patterns").mkdir(exist_ok=True)
    (out / "patterns" / "index.json").write_text(json.dumps(index), encoding="utf-8")
    files = sorted(p for p in out.rglob("*") if p.is_file())
    entries = [
        {"url": p.relative_to(out).as_posix(), "hash": hashlib.sha256(p.read_bytes()).hexdigest()[:12]}
        for p in files
    ]
    build_hash = hashlib.sha256("".join(e["hash"] for e in entries).encode()).hexdigest()[:12]
    sw = (
        (SRC / "sw.js")
        .read_text(encoding="utf-8")
        .replace("__BUILD_HASH__", build_hash)
        .replace("__PRECACHE__", json.dumps([e["url"] for e in entries]))
    )
    (out / "sw.js").write_text(sw, encoding="utf-8")
    (out / "build.json").write_text(json.dumps({"hash": build_hash, "files": entries}), encoding="utf-8")
    return out, index, build_hash


if __name__ == "__main__":
    target = globals().get("OUT_DIR") or ROOT / "site" / "dist"
    o, idx, h = build(target)
    print(f"built {o} ({len(idx)} patterns, build {h})")
