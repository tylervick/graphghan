"""score.py <got.prose.json> <truth.prose.json>: exact rows raw and after relabelling both sides'
codes by order of first appearance (a consistent permutation of key letters is not a reading error)."""

import json
import sys

got_doc, truth_doc = (json.load(open(p, encoding="utf-8")) for p in sys.argv[1:3])
for doc, p in ((got_doc, sys.argv[1]), (truth_doc, sys.argv[2])):
    rows = doc.get("written_rows", [])  # the tool writes no key when it read nothing
    if not isinstance(rows, list) or any(
        not isinstance(r.get("row"), int) or not isinstance(r.get("runs"), list) for r in rows
    ):
        sys.exit(f"{p}: written_rows must be a list of {{row: int, runs: [[code, count], ...]}}")


def rows_of(doc):  # the first printing of a row number wins: a second panel's "Rows 2-46" is another panel
    out = {}
    for r in doc.get("written_rows", []):
        if r.get("runs") and r["row"] not in out:
            out[r["row"]] = [[c, n] for c, n in r["runs"]]
    return out


def canon(rows):
    order, out = [], {}
    for n in sorted(rows):
        for c, _ in rows[n]:
            if c not in order:
                order.append(c)
        out[n] = [[chr(65 + order.index(c)), k] for c, k in rows[n]]
    return out


got, truth = rows_of(got_doc), rows_of(truth_doc)
errors = sum(1 for r in got_doc.get("written_rows", []) if r.get("error"))
raw = sum(1 for n, t in truth.items() if got.get(n) == t)
gc, tc = canon(got), canon(truth)
exact_c = [n for n, t in tc.items() if gc.get(n) == t]
exact_r = [n for n, t in truth.items() if got.get(n) == t]
exact = exact_r if len(exact_r) >= len(exact_c) else exact_c  # printed codes kept, or a consistent relabel
missing = [n for n in truth if n not in got]
wrong = [(n, gc[n][:6], t[:6]) for n, t in tc.items() if n in gc and n not in exact]
print(
    f"truth {len(truth)} rows; read {len(got)} ({errors} errors); exact {len(exact)} (raw codes {raw}); missing {len(missing)}; wrong {len(wrong)}"
)
if missing:
    print("  missing:", missing[:20])
for n, g, t in wrong[:10]:
    print(f"  row {n}: got {g} want {t}")
