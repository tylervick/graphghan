"""Score a prosereader output against ground truth: exact-row matches, errors, and the row-total check.

usage: uv run python ios/Packages/ProseReader/Scripts/score.py <prose.json> craigh|orca

Craigh na Dun's rows come from our own PDF's text layer (the self-reader, so exact by
construction); Orca's from the hand transcript in fixtures/import/real/ (gitignored, on the mini).
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "src"))

from graphghan.pdfself import prose_from_own_pdf  # noqa: E402


def main() -> None:
    path, which = sys.argv[1], sys.argv[2]
    doc = json.load(open(path, encoding="utf-8"))
    entries = doc.get("written_rows", [])
    got: dict[int, dict] = {}
    dups = 0
    for r in entries:
        if r["row"] in got:
            dups += 1
        got[r["row"]] = r
    errors = sum(1 for r in entries if r.get("error"))
    if which == "craigh":
        own = prose_from_own_pdf(ROOT / "fixtures" / "import" / "craigh-na-dun-final-sc.pdf")
        truth = {r["row"]: [list(x) for x in r["runs"]] for r in own["written_rows"]}
        width: int | None = 189
    else:
        mine = json.load(
            open(
                ROOT
                / "fixtures"
                / "import"
                / "real"
                / "onhand-en-orcacrossbodybagpdfpattern-front.prose.json"
            )
        )
        truth = {r["row"]: r["runs"] for r in mine["written_rows"]}
        width = None
    exact = sum(1 for n, t in truth.items() if n in got and got[n]["runs"] == t)
    missing = sorted(n for n in truth if n not in got)
    wrong = [(n, got[n]["runs"][:6], t[:6]) for n, t in truth.items() if n in got and got[n]["runs"] != t]
    line = (
        f"{which}: truth {len(truth)} rows; read {len(entries)} entries ({dups} duplicate numbers, "
        f"{errors} errors); exact {exact}; missing {len(missing)}"
    )
    if width:
        sums_ok = sum(1 for n in truth if n in got and sum(c for _, c in got[n]["runs"]) == width)
        line += f"; rows summing to {width}: {sums_ok}"
    print(line)
    if missing:
        print("  missing:", missing[:20])
    for n, g, t in wrong[:12]:
        print(f"  row {n}: got {g} want {t}")
    print("  front:", {k: doc.get(k) for k in ("pattern", "gauge", "chart")})
    print("  palette:", doc.get("palette"))


if __name__ == "__main__":
    main()
