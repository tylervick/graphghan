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
from .export import chart_json, preview_png, rows_to_strings, write_dist
from .motifs import CATALOG
from .options_page import build_options_html
from .pattern import find_repo_root, load_design, load_pattern, pattern_dir
from .validate import run_all

TEMPLATES = Path(__file__).parent / "templates"


def _resolve(slug_or_path: str) -> Path:
    p = Path(slug_or_path)
    return p.resolve() if p.exists() and (p / "pattern.toml").exists() else pattern_dir(slug_or_path)


def cmd_render(args) -> int:
    d = _resolve(args.pattern)
    meta = load_pattern(d)
    design = load_design(d)
    gauge = args.gauge or meta.stitch
    g, report = design.build(gauge, args.variant)
    if args.check:
        committed = json.loads((d / "dist" / "chart.json").read_text())
        fresh = rows_to_strings(g.a, meta.palette.codes)
        if committed["rows"] != fresh or committed["version"] != meta.version:
            bad = next((i for i, (x, y) in enumerate(zip(committed["rows"], fresh, strict=False)) if x != y), None)
            print(f"DRIFT: committed dist differs from code (first differing row index {bad}, "
                  f"version {committed['version']} vs {meta.version})")
            return 1
        print("no drift")
        return 0
    out = Path(args.out) if args.out else d / "dist"
    doc = write_dist(g.a, meta, gauge, report, out, variant=args.variant)
    print(f"wrote {out} ({doc['width']}x{doc['height']}, {gauge}, variant {args.variant})")
    return 0


def cmd_check(args) -> int:
    d = _resolve(args.pattern)
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
    (d / "tests" / "test_design.py").write_text((TEMPLATES / "test_design.py.tmpl").read_text().format(**subs))
    (d / "CHANGELOG.md").write_text(f"# {args.slug}\n\n## 0.1.0\nScaffolded.\n")
    print(f"scaffolded {d}")
    return 0


def cmd_options(args) -> int:
    d = _resolve(args.pattern)
    meta = load_pattern(d)
    design = load_design(d)
    out = Path(args.out) if args.out else d / "build" / "options"
    out.mkdir(parents=True, exist_ok=True)
    entries = []
    for variant in design.VARIANTS:
        for gauge in args.gauges.split(","):
            g, report = design.build(gauge, variant)
            doc = chart_json(g.a, meta, gauge, report, variant)
            preview_png(g.a, meta.palette.rgb, out / f"{variant}_{gauge}.png", cw=6)
            per_hr = {"sc": 1100, "hdc": 850, "dc": 700}.get(gauge, 900)
            hours = doc["stats"]["stitches"] / per_hr + sum(doc["stats"]["color_changes_per_row"]["per_row"]) * 3 / 3600
            entries.append({"variant": variant, "gauge": gauge, "width": doc["width"], "height": doc["height"],
                            "size_in": doc["size_in"], "colors": sorted({meta.palette.codes[i] for i in set(g.a.ravel().tolist())}),
                            "changes_mean": doc["stats"]["color_changes_per_row"]["mean"], "changes_max": doc["stats"]["color_changes_per_row"]["max"],
                            "hours": round(hours), "rows": doc["rows"], "palette": doc["palette"], "cell_aspect": doc["cell_aspect"]})
            print(f"{variant} {gauge}: {doc['width']}x{doc['height']} changes mean {doc['stats']['color_changes_per_row']['mean']} max {doc['stats']['color_changes_per_row']['max']}")
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
    if args.site_cmd == "build":
        runpy.run_path(str(build), run_name="__main__", init_globals={"OUT_DIR": out})
        return 0
    runpy.run_path(str(build), run_name="__main__", init_globals={"OUT_DIR": out})
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=str(out), **k)  # noqa: E731
    print(f"serving {out} at http://127.0.0.1:{args.port}/")
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler).serve_forever()
    return 0


def build_parser():
    p = argparse.ArgumentParser(prog="graphghan", description="charts for pixel-chart crafts")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("pattern")
    r.add_argument("--gauge")
    r.add_argument("--variant", default="final")
    r.add_argument("--out")
    r.add_argument("--check", action="store_true")
    r.set_defaults(fn=cmd_render)
    c = sub.add_parser("check")
    c.add_argument("pattern")
    c.set_defaults(fn=cmd_check)
    n = sub.add_parser("new")
    n.add_argument("slug")
    n.add_argument("--title", required=True)
    n.add_argument("--dir")
    n.add_argument("--template", default="craigh-na-dun")
    n.set_defaults(fn=cmd_new)
    o = sub.add_parser("options")
    o.add_argument("pattern")
    o.add_argument("--gauges", default="sc,hdc")
    o.add_argument("--out")
    o.set_defaults(fn=cmd_options)
    k = sub.add_parser("catalog")
    k.add_argument("--out")
    k.set_defaults(fn=cmd_catalog)
    s = sub.add_parser("site")
    s.add_argument("site_cmd", choices=["build", "serve"])
    s.add_argument("--out")
    s.add_argument("--port", type=int, default=8765)
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
