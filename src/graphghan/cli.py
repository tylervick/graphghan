"""graphghan command line."""

from __future__ import annotations

import argparse
import http.server
import json
import runpy
import subprocess
import sys
from pathlib import Path

import numpy as np

from . import grid as gr
from .chartdoc import cell_aspect, finished_size
from .export import chart_json, preview_png, write_dist
from .motifs import CATALOG
from .options_page import build_options_html
from .pattern import find_repo_root, load_design, load_pattern, pattern_dir
from .validate import run_all

TEMPLATES = Path(__file__).parent / "templates"


def _resolve(slug_or_path: str) -> Path | None:
    p = Path(slug_or_path)
    if p.exists() and (p / "pattern.toml").exists():
        return p.resolve()
    d = pattern_dir(slug_or_path)
    return d if (d / "pattern.toml").exists() else None


def _resolve_or_die(arg: str) -> Path | None:
    d = _resolve(arg)
    if d is None:
        print(f"pattern not found: {arg}", file=sys.stderr)
    return d


def _bad_gauge(meta, gauge: str) -> str | None:
    """None if `gauge` is usable for this pattern, else a usage-error message for stderr."""
    available = sorted(set(meta.gauges) | set(gr.GAUGES))
    if gauge in available:
        return None
    return f"unknown gauge {gauge!r} (have: {', '.join(available)})"


def _bad_variant(design, variant: str) -> str | None:
    """None if `variant` is one of the design's VARIANTS, else a usage-error message for stderr."""
    if variant in design.VARIANTS:
        return None
    return f"unknown variant {variant!r} (have: {', '.join(design.VARIANTS)})"


def cmd_render(args) -> int:
    d = _resolve_or_die(args.pattern)
    if d is None:
        return 2
    meta = load_pattern(d)
    if args.check and not (d / "dist" / "chart.json").exists():
        print(f"no committed dist for {meta.slug}; run 'graphghan render {meta.slug}' first")
        return 1
    gauge = args.gauge or meta.stitch
    bad = _bad_gauge(meta, gauge)
    if bad:
        print(bad, file=sys.stderr)
        return 2
    design = load_design(d)
    bad = _bad_variant(design, args.variant)
    if bad:
        print(bad, file=sys.stderr)
        return 2
    g, report = design.build(gauge, args.variant)
    if args.check:
        committed = json.loads((d / "dist" / "chart.json").read_text())
        # Round-trip through JSON so in-memory-only distinctions (e.g. tuples vs lists in
        # `report`) don't register as drift; this mirrors how `committed` was serialized.
        fresh = json.loads(json.dumps(chart_json(g.a, meta, gauge, report, args.variant)))
        if committed != fresh:
            diff_keys = sorted(k for k in set(committed) | set(fresh) if committed.get(k) != fresh.get(k))
            msg = f"DRIFT: chart.json differs in keys: {', '.join(diff_keys)}"
            if "rows" in diff_keys:
                row_idx = next(
                    (
                        i
                        for i, (x, y) in enumerate(
                            zip(committed.get("rows", []), fresh.get("rows", []), strict=False)
                        )
                        if x != y
                    ),
                    None,
                )
                msg += f" (first differing row index {row_idx})"
            print(msg)
            return 1
        print("no drift")
        return 0
    out = Path(args.out) if args.out else d / "dist"
    doc = write_dist(g.a, meta, gauge, report, out, variant=args.variant)
    print(f"wrote {out} ({doc['chart']['width']}x{doc['chart']['height']}, {gauge}, variant {args.variant})")
    return 0


def cmd_check(args) -> int:
    d = _resolve_or_die(args.pattern)
    if d is None:
        return 2
    meta = load_pattern(d)
    g, _ = load_design(d).build(meta.stitch, "final")
    ok = True
    for name, passed, detail in run_all(g.a, meta):
        ok &= passed
        print(f"{'ok  ' if passed else 'FAIL'} {name}: {detail}")
    r = subprocess.run([sys.executable, "-m", "pytest", "-q", str(d / "tests")], cwd=find_repo_root())
    ok &= r.returncode == 0
    return 0 if ok else 1


def cmd_new(args) -> int:
    base = Path(args.dir) if args.dir else find_repo_root() / "patterns"
    d = base / args.slug
    if d.exists():
        print(f"{d} already exists")
        return 1
    (d / "tests").mkdir(parents=True)
    (d / "reference").mkdir()
    subs = {"slug": args.slug, "title": args.title}
    (d / "pattern.toml").write_text((TEMPLATES / "pattern.toml.tmpl").read_text().format(**subs))
    (d / "design.py").write_text((TEMPLATES / "design.py.tmpl").read_text().format(**subs))
    (d / "tests" / "test_design.py").write_text(
        (TEMPLATES / "test_design.py.tmpl").read_text().format(**subs)
    )
    (d / "CHANGELOG.md").write_text(f"# {args.slug}\n\n## 0.1.0\nScaffolded.\n")
    print(f"scaffolded {d}")
    return 0


def cmd_options(args) -> int:
    d = _resolve_or_die(args.pattern)
    if d is None:
        return 2
    meta = load_pattern(d)
    design = load_design(d)
    gauges = args.gauges.split(",")
    for gauge in gauges:
        bad = _bad_gauge(meta, gauge)
        if bad:
            print(bad, file=sys.stderr)
            return 2
    out = Path(args.out) if args.out else d / "build" / "options"
    out.mkdir(parents=True, exist_ok=True)
    entries = []
    for variant in design.VARIANTS:
        for gauge in gauges:
            g, report = design.build(gauge, variant)
            doc = chart_json(g.a, meta, gauge, report, variant)
            preview_png(g.a, meta.palette.rgb, out / f"{variant}_{gauge}.png", cw=6)
            per_hr = {"sc": 1100, "hdc": 850, "dc": 700}.get(gauge, 900)
            hours = (
                doc["stats"]["stitches"] / per_hr
                + sum(doc["stats"]["color_changes_per_row"]["per_row"]) * 3 / 3600
            )
            w_in, h_in, _unit = finished_size(doc)
            entries.append(
                {
                    "variant": variant,
                    "gauge": gauge,
                    "width": doc["chart"]["width"],
                    "height": doc["chart"]["height"],
                    "size_in": [w_in, h_in],
                    "colors": sorted({meta.palette.codes[i] for i in set(g.a.ravel().tolist())}),
                    "changes_mean": doc["stats"]["color_changes_per_row"]["mean"],
                    "changes_max": doc["stats"]["color_changes_per_row"]["max"],
                    "hours": round(hours),
                    "rows": doc["rows"],
                    "palette": doc["palette"],
                    "cell_aspect": cell_aspect(doc),
                }
            )
            print(
                f"{variant} {gauge}: {doc['chart']['width']}x{doc['chart']['height']} changes mean {doc['stats']['color_changes_per_row']['mean']} max {doc['stats']['color_changes_per_row']['max']}"
            )
    (out / "options.html").write_text(build_options_html(meta.title, entries))
    print(f"wrote {out / 'options.html'}")
    return 0


def cmd_catalog(args) -> int:
    out = Path(args.out) if args.out else find_repo_root() / ".claude" / "skills" / "graphghan" / "assets"
    out.mkdir(parents=True, exist_ok=True)
    gr.set_gauge("sc")
    for name, fn in CATALOG:
        arr, rgb = fn()
        preview_png(np.asarray(arr, dtype=np.uint8), rgb, out / f"{name}.png", cw=10)
    print(f"wrote {len(CATALOG)} thumbnails to {out}")
    return 0


def cmd_site(args) -> int:
    root = find_repo_root()
    build = root / "site" / "build.py"
    if not build.exists():
        print("site/build.py not found (the site plan adds it)")
        return 1
    out = Path(args.out) if args.out else root / "site" / "dist"
    runpy.run_path(str(build), run_name="__main__", init_globals={"OUT_DIR": out})
    if args.site_cmd == "build":
        return 0
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=str(out), **k)  # noqa: E731
    print(f"serving {out} at http://127.0.0.1:{args.port}/")
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler).serve_forever()
    return 0


def build_parser():
    p = argparse.ArgumentParser(prog="graphghan", description="charts for pixel-chart crafts")
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("render", help="build a pattern's chart and write it (or check it for drift)")
    r.add_argument("pattern", help="pattern slug (looked up under patterns/) or a path to a pattern folder")
    r.add_argument("--gauge", help="gauge name to build at (default: the pattern's own stitch gauge)")
    r.add_argument("--variant", default="final", help="design variant to build (default: final)")
    r.add_argument("--out", help="output directory for chart.json/png/etc (default: <pattern>/dist)")
    r.add_argument(
        "--check",
        action="store_true",
        help="don't write; compare a fresh build against the committed dist and report drift",
    )
    r.set_defaults(fn=cmd_render)

    c = sub.add_parser("check", help="run generic invariants and the pattern's own tests")
    c.add_argument("pattern", help="pattern slug (looked up under patterns/) or a path to a pattern folder")
    c.set_defaults(fn=cmd_check)

    n = sub.add_parser("new", help="scaffold a new pattern folder from a template")
    n.add_argument("slug", help="folder name / slug for the new pattern")
    n.add_argument("--title", required=True, help="human-readable title for the new pattern")
    n.add_argument("--dir", help="parent directory to scaffold into (default: patterns/)")
    n.set_defaults(fn=cmd_new)

    o = sub.add_parser("options", help="render a preview + stats grid across variants and gauges")
    o.add_argument("pattern", help="pattern slug (looked up under patterns/) or a path to a pattern folder")
    o.add_argument(
        "--gauges", default="sc,hdc", help="comma-separated gauge names to build (default: sc,hdc)"
    )
    o.add_argument(
        "--out", help="output directory for options.html and previews (default: <pattern>/build/options)"
    )
    o.set_defaults(fn=cmd_options)

    k = sub.add_parser("catalog", help="render thumbnail PNGs for every motif in the catalog")
    k.add_argument("--out", help="output directory for thumbnails (default: .claude/skills/graphghan/assets)")
    k.set_defaults(fn=cmd_catalog)

    s = sub.add_parser("site", help="build or serve the static docs/site")
    s.add_argument("site_cmd", choices=["build", "serve"], help="build the site once, or build and serve it")
    s.add_argument("--out", help="output directory for the built site (default: site/dist)")
    s.add_argument("--port", type=int, default=8765, help="port to serve on for 'serve' (default: 8765)")
    s.set_defaults(fn=cmd_site)
    return p


def main(argv=None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
