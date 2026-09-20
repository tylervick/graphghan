"""The pattern manifest (schema 1) over a pattern's committed dist/: `patterns/<id>/pattern.json`.

One definition, two consumers. `site/build.py` writes it into the published feed; `bundle.py`
writes it into a `.graphghan` file. A second implementation would be a second definition of the
manifest, and the app is not supposed to be able to tell where one came from.

See docs/chart-format.md (Pattern manifest) and the design spec
docs/superpowers/specs/2026-09-10-graphghan-ios-app-design.md §4.3.
"""

from __future__ import annotations

import json
from pathlib import Path

from .chartdoc import finished_size
from .pattern import load_pattern
from .publish import chart_key

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
