"""Render and drift-check every published (variant, gauge) combination of a pattern.

Layout: dist/charts/<variant>-<gauge>/{chart.json, chart.png, preview.png, preview-grid.png,
written-rows.txt}; the default (first [publish] entry) is also copied to dist/ top level.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from . import grid as gr
from .export import chart_json, write_dist

TOP_LEVEL_FILES = ("chart.json", "chart.png", "preview.png", "preview-grid.png", "written-rows.txt")


def chart_key(variant: str, gauge: str) -> str:
    return f"{variant}-{gauge}"


def chart_dir(pattern_dir: str | Path, variant: str, gauge: str) -> Path:
    return Path(pattern_dir) / "dist" / "charts" / chart_key(variant, gauge)


def published(meta, design) -> list[tuple[str, str]]:
    """The [publish] entries, validated against the design's variants and the known gauges."""
    entries = [(str(v), str(g)) for v, g in meta.publish]
    seen: set[tuple[str, str]] = set()
    for variant, gauge in entries:
        if variant not in design.VARIANTS:
            raise ValueError(f"[publish] variant {variant!r} is not one of: {', '.join(design.VARIANTS)}")
        if gauge not in meta.gauges and gauge not in gr.GAUGES:
            available = sorted(set(meta.gauges) | set(gr.GAUGES))
            raise ValueError(f"[publish] gauge {gauge!r} is unknown (have: {', '.join(available)})")
        if (variant, gauge) in seen:
            raise ValueError(f"[publish] lists {chart_key(variant, gauge)} twice")
        seen.add((variant, gauge))
    return entries


def render_published(pattern_dir: str | Path, meta, design) -> list[dict]:
    d = Path(pattern_dir)
    entries = published(meta, design)
    # Build every chart before touching the tree, so a design that raises half way through
    # leaves the committed dist/ exactly as it was.
    built = [(variant, gauge, *design.build(gauge, variant)) for variant, gauge in entries]
    charts = d / "dist" / "charts"
    if charts.exists():
        shutil.rmtree(charts)
    docs = []
    for i, (variant, gauge, g, report) in enumerate(built):
        # design.build left the *last* gauge active; chart_json and stats read the global one.
        gr.set_gauge(meta.gauges.get(gauge, gauge))
        out = chart_dir(d, variant, gauge)
        docs.append(write_dist(g.a, meta, gauge, report, out, variant=variant))
        if i == 0:
            (d / "dist").mkdir(parents=True, exist_ok=True)
            for name in TOP_LEVEL_FILES:
                shutil.copy(out / name, d / "dist" / name)
    return docs


def committed_charts(root: str | Path) -> list[tuple[str, str, Path]]:
    """Every committed chart.json under patterns/*/dist/charts/<key>/, as (slug, key, path)."""
    out = []
    for d in sorted((Path(root) / "patterns").iterdir()):
        charts = d / "dist" / "charts"
        if not (d / "pattern.toml").exists() or not charts.is_dir():
            continue
        for sub in sorted(p for p in charts.iterdir() if p.is_dir()):
            if (sub / "chart.json").exists():
                out.append((d.name, sub.name, sub / "chart.json"))
    return out


def drift_message(committed: dict, fresh: dict) -> str | None:
    # `generator` records the package version, which moves on its own: a release bump is not drift.
    committed = {k: v for k, v in committed.items() if k != "generator"}
    fresh = {k: v for k, v in fresh.items() if k != "generator"}
    if committed == fresh:
        return None
    diff_keys = sorted(k for k in set(committed) | set(fresh) if committed.get(k) != fresh.get(k))
    msg = f"DRIFT: chart.json differs in keys: {', '.join(diff_keys)}"
    if "rows" in diff_keys:
        pairs = zip(committed.get("rows", []), fresh.get("rows", []), strict=False)
        row_idx = next((i for i, (x, y) in enumerate(pairs) if x != y), None)
        msg += f" (first differing row index {row_idx})"
    return msg


def check_published(pattern_dir: str | Path, meta, design) -> list[str]:
    """Problems (empty when clean): missing or drifted committed charts, stale chart dirs."""
    d = Path(pattern_dir)
    entries = published(meta, design)
    problems: list[str] = []
    for i, (variant, gauge) in enumerate(entries):
        g, report = design.build(gauge, variant)
        # Round-trip through JSON so tuples-vs-lists in the report never register as drift.
        fresh = json.loads(json.dumps(chart_json(g.a, meta, gauge, report, variant)))
        paths = [chart_dir(d, variant, gauge) / "chart.json"]
        if i == 0:
            paths.append(d / "dist" / "chart.json")
        for path in paths:
            rel = path.relative_to(d).as_posix()
            if not path.exists():
                problems.append(f"missing committed chart {rel}")
                continue
            msg = drift_message(json.loads(path.read_text()), fresh)
            if msg:
                problems.append(f"{rel}: {msg}")
    expected = {chart_key(v, g) for v, g in entries}
    charts = d / "dist" / "charts"
    if charts.exists():
        for sub in sorted(p.name for p in charts.iterdir() if p.is_dir()):
            if sub not in expected:
                problems.append(f"stale dist/charts/{sub} is not in [publish]")
    return problems
