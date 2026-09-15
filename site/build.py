"""Build the static viewer: site/src + patterns/*/dist -> site/dist (or OUT_DIR)."""

from __future__ import annotations

import hashlib
import html
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw

from graphghan.chartdoc import finished_size
from graphghan.pattern import load_pattern
from graphghan.publish import chart_key

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "site" / "src"
SLUG_RE = re.compile(r"[a-z0-9-]+")


def finished_size_in(doc) -> list[float] | None:
    """The index always quotes inches, whatever unit the gauge is stated in, or None when the
    gauge and the grid do not count the same thing (#48)."""
    size = finished_size(doc)
    if size is None:
        return None
    w, h, unit = size
    if unit == "cm":
        w, h = round(w / 2.54, 1), round(h / 2.54, 1)
    return [w, h]


def index_entry(doc) -> dict:
    p, c = doc["pattern"], doc["chart"]
    entry = {
        "slug": p["id"],
        "title": p["title"],
        "dedication": p.get("dedication", ""),
        "version": p["version"],
        "stitch": doc["gauge"].get("stitch", ""),
        "width": c["width"],
        "height": c["height"],
    }
    size_in = finished_size_in(doc)
    if size_in is not None:
        entry["size_in"] = size_in
    entry["colors"] = len(doc["palette"])
    entry["preview"] = f"patterns/{p['id']}/preview.png"
    return entry


CHART_FILES = ("chart.json", "chart.png", "preview.png", "preview-grid.png", "written-rows.txt")


def publish_order(pattern_dir: Path) -> list[str]:
    """The chart keys in [publish] order, so the site lists charts the way the pattern declares them.

    Directory names sort alphabetically, which is not the author's order; pattern.toml sits next to
    dist/ and is the only record of it. A pattern folder without one (a fixture) falls back to sorted.
    """
    if not (pattern_dir / "pattern.toml").exists():
        return []
    return [chart_key(variant, gauge) for variant, gauge in load_pattern(pattern_dir).publish]


def published_docs(pattern_dir: Path) -> list[tuple[str, dict]]:
    """(path relative to the pattern's site dir, doc) for every published chart, default first."""
    dist = pattern_dir / "dist"
    top = json.loads((dist / "chart.json").read_text(encoding="utf-8"))
    charts = dist / "charts"
    if not charts.exists():
        return [("chart.json", top)]
    names = sorted(p.name for p in charts.iterdir() if p.is_dir())
    order = publish_order(pattern_dir)
    names.sort(key=lambda n: (order.index(n) if n in order else len(order), n))
    docs = []
    for name in names:
        doc = json.loads((charts / name / "chart.json").read_text(encoding="utf-8"))
        docs.append((f"charts/{name}/chart.json", doc))
    # The top-level copy is one of the published charts, not a chart of its own: match it on
    # (variant, gauge_key), which is what names a chart. Two gauges of one design can share a
    # chart.id when the grid happens to come out identical.
    want = (top["chart"].get("variant"), top["chart"].get("gauge_key"))
    default = [x for x in docs if (x[1]["chart"].get("variant"), x[1]["chart"].get("gauge_key")) == want]
    if not default:
        raise ValueError(f"{pattern_dir.name}: top-level dist/chart.json is not one of dist/charts/*")
    return default[:1] + [x for x in docs if x is not default[0]]


def manifest(published: list[tuple[str, dict]], updated: str) -> dict:
    top = published[0][1]
    p = top["pattern"]
    charts = []
    for i, (path, doc) in enumerate(published):
        c, g, st = doc["chart"], doc["gauge"], doc["stats"]
        size = finished_size(doc)
        entry = {
            "id": c["id"],
            "variant": c.get("variant", ""),
            "gauge_key": c.get("gauge_key", ""),
            "default": i == 0,
            "path": path,
            "preview": path.rsplit("/", 1)[0] + "/preview.png" if "/" in path else "preview.png",
            "width": c["width"],
            "height": c["height"],
        }
        if size is not None:
            entry["size"] = {"width": size[0], "height": size[1], "unit": size[2]}
        entry.update(
            {
                "stitch": g.get("stitch", ""),
                "colors": len(doc["palette"]),
                "stitches": c["width"] * c["height"],
                "changes_per_row": {
                    "mean": st["color_changes_per_row"]["mean"],
                    "max": st["color_changes_per_row"]["max"],
                },
                "yards_est": int(sum(st["yards_est"].values())),
            }
        )
        charts.append(entry)
    return {
        "schema": 1,
        "id": p["id"],
        "title": p["title"],
        "version": p["version"],
        "dedication": p.get("dedication", ""),
        "quote": p.get("quote", ""),
        "author": p.get("author", ""),
        "license": p.get("license", ""),
        "preview": "preview.png",
        "palette": [{"code": x["code"], "name": x["name"], "hex": x["hex"]} for x in top["palette"]],
        "charts": charts,
        "updated": updated,
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
    updated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = Path(out)
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(SRC, out, ignore=shutil.ignore_patterns("pattern.html", "sw.js"))
    make_icons(out)
    # The $id in each schema points at https://graphghan.milo.cat/schema/<name>.json; serve them.
    (out / "schema").mkdir(parents=True, exist_ok=True)
    for s in sorted((ROOT / "schema").glob("*.json")):
        shutil.copy(s, out / "schema" / s.name)
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
        charts_src = d / "dist" / "charts"
        if charts_src.exists():
            for sub in sorted(p for p in charts_src.iterdir() if p.is_dir()):
                (pdir / "charts" / sub.name).mkdir(parents=True, exist_ok=True)
                for name in CHART_FILES:
                    if (sub / name).exists():
                        shutil.copy(sub / name, pdir / "charts" / sub.name / name)
        published = published_docs(d)
        (pdir / "pattern.json").write_text(json.dumps(manifest(published, updated)), encoding="utf-8")
        entry = index_entry(doc)
        entry["manifest"] = f"patterns/{slug}/pattern.json"
        entry["charts"] = len(published)
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
