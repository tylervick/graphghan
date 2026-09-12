#!/usr/bin/env python3
"""Merge coded pattern records into corpus.csv and print claim counts.

    corpus_csv.py merge  <coded.json> [--csv docs/research/corpus/corpus.csv]
    corpus_csv.py counts [--csv docs/research/corpus/corpus.csv]

`coded.json` is the `coded` array returned by the code-pattern-corpus workflow (a list of
objects keyed by codebook field). Rows are keyed by `id`; a re-coded id replaces the old row.
Counts are the numbers the claim register cites: "N of M in stratum S".
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import Counter
from pathlib import Path

FIELDS = [
    "id",
    "title",
    "designer",
    "source_type",
    "source_url",
    "craft",
    "technique",
    "object",
    "year",
    "terms",
    "terms_evidence",
    "abbrev_list",
    "special_stitches",
    "special_stitch_names",
    "placement_modifiers",
    "stitches_used",
    "gauge_stitch",
    "gauge_form",
    "turning_chain",
    "turning_chain_by_stitch",
    "tc_counts_as_stitch",
    "tc_position",
    "tc_color",
    "foundation_form",
    "first_stitch_in",
    "round_join",
    "stitch_marker_instructed",
    "stitch_counts_given",
    "shaping",
    "repeats_stated",
    "border",
    "finishing_steps",
    "has_chart",
    "chart_type",
    "chart_cell_means",
    "chart_direction_stated",
    "chart_row1_position",
    "chart_key",
    "written_also",
    "rs_ws_stated",
    "skill_level",
    "hook_mm",
    "hook_us",
    "yarn_weight_form",
    "yarn_brand_line",
    "yarn_putup",
    "yarn_amount_form",
    "yarn_per_color",
    "fiber_content",
    "notions",
    "finished_size",
    "sizes_count",
    "care",
    "substitution_advice",
    "video_links",
    "copyright_terms",
    "coder",
    "confidence",
    "notes",
    "quotes",
]

DEFAULT_CSV = Path(__file__).resolve().parents[1] / "corpus" / "corpus.csv"


def load(csv_path: Path) -> dict[str, dict]:
    if not csv_path.exists():
        return {}
    with csv_path.open(newline="", encoding="utf-8") as f:
        return {row["id"]: row for row in csv.DictReader(f)}


def save(rows: dict[str, dict], csv_path: Path) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        w.writeheader()
        for rid in sorted(rows):
            w.writerow({k: rows[rid].get(k, "") for k in FIELDS})


def merge(args: argparse.Namespace) -> None:
    rows = load(args.csv)
    coded = json.loads(Path(args.coded).read_text(encoding="utf-8"))
    if isinstance(coded, dict):
        coded = coded.get("coded", [])
    added = replaced = 0
    for rec in coded:
        if not rec or not rec.get("id"):
            continue
        if rec["id"] in rows:
            replaced += 1
        else:
            added += 1
        rows[rec["id"]] = rec
    save(rows, args.csv)
    print(f"{args.csv}: {len(rows)} rows ({added} added, {replaced} replaced)")


def pct(n: int, m: int) -> str:
    return f"{n}/{m}" + (f" ({100 * n / m:.0f}%)" if m else "")


def counts(args: argparse.Namespace) -> None:
    rows = list(load(args.csv).values())
    patterns = [r for r in rows if r.get("confidence") in ("high", "medium")]
    print(f"rows: {len(rows)}; usable patterns (confidence high/medium): {len(patterns)}\n")

    def stratum(**kw):
        out = patterns
        for k, v in kw.items():
            out = [r for r in out if r.get(k) in (v if isinstance(v, tuple) else (v,))]
        return out

    print("== source_type / craft / technique ==")
    for k in ("source_type", "craft", "technique"):
        print(f"  {k}: {dict(Counter(r.get(k) for r in patterns))}")

    rowwork = stratum(
        craft=("crochet", "tunisian"), technique=("rows", "tapestry", "filet", "overlay-mosaic", "mixed")
    )
    print("\n== Claim 1: turning chain by row stitch (crochet, row-worked) ==")
    by_stitch: dict[str, Counter] = {}
    for r in rowwork:
        tc = r.get("turning_chain", "")
        if tc == "varies" and r.get("turning_chain_by_stitch"):
            for part in r["turning_chain_by_stitch"].split(";"):
                if "=" in part:
                    st, n = part.split("=", 1)
                    by_stitch.setdefault(st.strip(), Counter())[n.strip()] += 1
        elif tc not in ("", "unstated", "n/a"):
            gs = r.get("gauge_stitch", "") or "?"
            by_stitch.setdefault(gs, Counter())[tc] += 1
    for st, c in sorted(by_stitch.items()):
        m = sum(c.values())
        top = c.most_common(1)[0]
        print(f"  {st}: {dict(c)} -> top value {top[0]} in {pct(top[1], m)}")
    stated = [r for r in rowwork if r.get("turning_chain") not in ("", "unstated", "n/a")]
    print(f"  turning chain stated at all: {pct(len(stated), len(rowwork))}")

    print("\n== Claim 2: counts-as-stitch stated ==")
    c2 = Counter(r.get("tc_counts_as_stitch") for r in rowwork)
    print(f"  {dict(c2)}; stated: {pct(c2['yes'] + c2['no'], len(rowwork))}")

    print("\n== Claim 3: chain colour at a colour change ==")
    print(f"  {dict(Counter(r.get('tc_color') for r in rowwork))}")

    print("\n== Claim 4: terms declared ==")
    print(f"  terms: {dict(Counter(r.get('terms') for r in patterns))}")
    print(f"  evidence: {dict(Counter(r.get('terms_evidence') for r in patterns))}")

    print("\n== Claim 5: custom stitches ==")
    print(
        f"  special_stitches yes: {pct(sum(r.get('special_stitches') == 'yes' for r in patterns), len(patterns))}"
    )
    print(
        f"  placement modifiers used: {pct(sum(r.get('placement_modifiers') not in ('', 'none', 'n/a', 'unstated') for r in patterns), len(patterns))}"
    )

    print("\n== Claim 7: chart cell means ==")
    charted = [r for r in patterns if r.get("has_chart") == "yes"]
    print(f"  {dict(Counter(r.get('chart_cell_means') for r in charted))} over {len(charted)} charted")
    print(
        f"  written_also with chart: {pct(sum(r.get('written_also') == 'yes' for r in charted), len(charted))}"
    )
    print(f"  chart_row1_position: {dict(Counter(r.get('chart_row1_position') for r in charted))}")

    print("\n== Claim 9: front matter presence ==")
    for k in (
        "skill_level",
        "notions",
        "yarn_putup",
        "hook_mm",
        "hook_us",
        "yarn_weight_form",
        "care",
        "finished_size",
        "abbrev_list",
        "fiber_content",
        "substitution_advice",
    ):
        vals = Counter(r.get(k) for r in patterns)
        present = len(patterns) - vals.get("unstated", 0) - vals.get("no", 0) - vals.get("", 0)
        print(f"  {k}: present {pct(present, len(patterns))}  {dict(vals)}")

    print("\n== Claim 10: rounds join ==")
    rounds = stratum(technique=("joined-rounds", "spiral-rounds"))
    print(f"  {dict(Counter((r.get('technique'), r.get('round_join')) for r in rounds))}")

    print("\n== Claim 14: gauge form ==")
    print(f"  {dict(Counter(r.get('gauge_form') for r in patterns))}")

    print("\n== foundation ==")
    print(f"  {dict(Counter(r.get('foundation_form') for r in patterns))}")
    print(f"  first_stitch_in: {dict(Counter(r.get('first_stitch_in') for r in patterns))}")
    print(f"  tc_position: {dict(Counter(r.get('tc_position') for r in rowwork))}")


def main(argv: list[str]) -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("merge")
    m.add_argument("coded")
    m.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    c = sub.add_parser("counts")
    c.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    args = ap.parse_args(argv)
    {"merge": merge, "counts": counts}[args.cmd](args)


if __name__ == "__main__":
    main(sys.argv[1:])
