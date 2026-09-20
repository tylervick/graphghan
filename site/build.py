"""Build the published pattern feed: site/src + patterns/*/dist -> site/dist (or OUT_DIR).

The output is what https://graphghan.milo.cat/ serves and what the iOS app reads: a
`patterns/index.json` listing, a `pattern.json` manifest and chart files per pattern, the JSON
Schemas the documents point their `$id` at, and a static landing page copied from `src/`. It is a
data feed, not an application -- the browser viewer this replaced is gone (#78).
"""

from __future__ import annotations

import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

from graphghan.chartdoc import finished_size
from graphghan.manifest import CHART_FILES, manifest, published_docs

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


def load_patterns():
    items = []
    for d in sorted((ROOT / "patterns").iterdir()):
        cj = d / "dist" / "chart.json"
        if cj.exists():
            items.append((d, json.loads(cj.read_text(encoding="utf-8"))))
    return items


def build(out: Path):
    updated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = Path(out)
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(SRC, out)
    # The $id in each schema points at https://graphghan.milo.cat/schema/<name>.json; serve them.
    (out / "schema").mkdir(parents=True, exist_ok=True)
    for s in sorted((ROOT / "schema").glob("*.json")):
        shutil.copy(s, out / "schema" / s.name)
    # Metamorphous is the lettering face the charts themselves are set in, so the landing page is
    # set in it too. One file, from the same fonts/ the renderer uses -- not a second copy.
    (out / "fonts").mkdir(parents=True, exist_ok=True)
    for name in ("Metamorphous-Regular.ttf", "OFL.txt"):
        shutil.copy(ROOT / "fonts" / name, out / "fonts" / name)
    index = []
    for d, doc in load_patterns():
        slug = doc["pattern"]["id"]
        # The slug is the only part of a pattern document that becomes a path here, so it is the
        # only part that can escape the output directory. Refuse it rather than sanitise it.
        if not SLUG_RE.fullmatch(slug):
            raise ValueError(f"invalid slug {slug!r}")
        pdir = out / "patterns" / slug
        pdir.mkdir(parents=True, exist_ok=True)
        for name in ("chart.json", "chart.png", "preview.png", "written-rows.txt"):
            shutil.copy(d / "dist" / name, pdir / name)
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
    return out, index


if __name__ == "__main__":
    target = globals().get("OUT_DIR") or ROOT / "site" / "dist"
    o, idx = build(target)
    print(f"built {o} ({len(idx)} patterns)")
