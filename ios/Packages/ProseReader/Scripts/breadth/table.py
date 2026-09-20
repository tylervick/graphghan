"""Breadth table: one line per pattern with a truth file and a reader output.

usage: uv run python table.py <work dir>
"""

import re
import subprocess
import sys
from pathlib import Path

S = Path(sys.argv[1])  # the work folder
R = Path(__file__).resolve().parents[5] / "fixtures" / "import" / "real"
GENRE = dict(
    line.split("\t")[:2]
    for line in (Path(__file__).with_name("sources.tsv")).read_text(encoding="utf-8").splitlines()
)
GENRE.update(
    {
        "tr": "tapestry",
        "mmd": "tapestry",
        "lb": "tapestry",
        "shd": "tapestry",
        "rv-canyon-moon": "tapestry PDF",
        "rv-axolotl": "tapestry PDF",
    }
)
TRUTH = {"shd": R / "shd-tapestry-blanket-dedup.prose.json"}
print("| pattern | genre | rows | exact | missing | wrong | errors |\n|---|---|---|---|---|---|---|")
for id_ in ["shd"] + list(GENRE):
    got, truth = S / f"{id_}.json", TRUTH.get(id_, S / "truth" / f"{id_}.json")
    if not got.exists() or not truth.exists():
        print(f"| {id_} | {GENRE.get(id_, '')} | | not run | | | |")
        continue
    proc = subprocess.run(
        [sys.executable, Path(__file__).with_name("score.py"), got, truth], capture_output=True, text=True
    )
    m = re.match(
        r"truth (\d+) rows; read (\d+) \((\d+) errors\); exact (\d+) \(raw codes \d+\); missing (\d+); wrong (\d+)",
        proc.stdout,
    )
    if proc.returncode or not m:
        sys.exit(f"score.py failed for {id_}: {proc.stderr.strip() or proc.stdout.strip()}")
    n, read, err, ex, miss, wrong = m.groups()
    print(f"| {id_} | {GENRE.get(id_, '')} | {n} | {ex} | {miss} | {wrong} | {err} |")
