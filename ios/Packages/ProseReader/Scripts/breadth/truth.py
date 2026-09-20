"""Deterministic ground truth for the fetched web patterns: a regex parser per grammar, then
row-width validation (tapestry rows all one width; c2c rows widen by one tile then narrow).

usage: uv run python truth.py <work dir> [id ...]
"""

import collections
import json
import re
import sys
from pathlib import Path

S = Path(sys.argv[1])  # the work folder: <id>/p01.txt in, truth/<id>.json out
HEAD = re.compile(
    r"^\W*(?:Rows?|ROWS?)\s*(\d+)(?:\s*(?:[-–]|&|and)\s*(\d+))?\s*(?:\((?:RS|WS|>>|<<)\)|\[?(?:RS|WS|LR|RL)\]?)?\s*(?:[:.\-–]|\((?:main[^)]*)\):?)\s*(?:WS:|RS:)?\s*(.*)$"
)
NUM_HEAD = re.compile(r"^(\d+)\.\s+(.*)$")  # whistle & ivy


def name_x(body):  # (Duck Egg) x 24 | blue x 2 | (Pale Rose) | White x 14
    out = []
    for m in re.finditer(r"\(([^)]+)\)(?:\s*x\s*(\d+))?|([A-Za-z][A-Za-z ]*?)\s*x\s*(\d+)", body):
        name = (m.group(1) or m.group(3)).strip().lower()
        n = int(m.group(2) or m.group(4) or 1)
        out.append((name, n))
    return out


def abbrev(body):  # (dg) x 3, c2, w, c
    out = []
    for tok in re.split(r",\s*", body.split("(")[0] if False else body):
        tok = tok.strip()
        m = (
            re.match(r"^\(([a-z]+)\)\s*x\s*(\d+)$", tok)
            or re.match(r"^([a-z]+?)(\d+)$", tok)
            or re.match(r"^([a-z]+)$", tok)
        )
        if not m:
            continue
        out.append((m.group(1), int(m.group(2)) if m.lastindex == 2 else 1))
    return out


def n_code(body):
    return [(c, int(n)) for n, c in re.findall(r"(\d+)\s*([A-Z]+)", body)]


def code_n_glued(body):
    return [(c, int(n)) for c, n in re.findall(r"\b([A-Z])(\d+)", body)]


def expand(body, width, pat):
    """pat matches (code, n); handles [..] N times, (..) N times and *..; repeat from * across."""
    body = re.sub(r"\b(?:Ch ?1|ch ?1|turn|Turn|Fasten off \w+)\b\.?", "", body)

    def grp(m):
        return ", ".join([m.group(1)] * int(m.group(2)))

    body = re.sub(r"[\[(]([^\[\]()]+)[\])]\s*(\d+)\s*times", grp, body)
    star = re.search(r"\*(.*?);?\s*repeat from \*\s*(?:across|to end)", body)
    runs = []
    pre = body if not star else body[: star.start()]
    runs += [(c, int(n)) for c, n in re.findall(pat, pre)]
    if star:
        unit = [(c, int(n)) for c, n in re.findall(pat, star.group(1))]
        post = [(c, int(n)) for c, n in re.findall(pat, body[star.end() :])]
        need = width - sum(n for _, n in runs) - sum(n for _, n in post)
        u = sum(n for _, n in unit)
        while u and need >= u:
            runs += unit
            need -= u
        runs += post
    return runs


def merge(runs):
    out = []
    for c, n in runs:
        if out and out[-1][0] == c:
            out[-1][1] += n
        else:
            out.append([c, n])
    return out


STYLE = {
    "mhc-rabbit": ("c2c", name_x),
    "jo-trowel": ("c2c", name_x),
    "tc-daisy": ("tap", name_x),
    "tc-hearts": ("tap", name_x),
    "vetka-cat": ("tap", name_x),
    "hanjan-rainbow": (
        "c2c",
        lambda b: [(c, int(n)) for c, n in re.findall(r"\b([A-Z]{1,2})\s*x\s*(\d+)", b)],
    ),
    "mhc-elephant": ("c2c", abbrev),
    "mhc-cheetah": ("c2c", abbrev),
    "wi-saturn": ("c2c", n_code),
    "wi-rocket": ("c2c", n_code),
    "pp-pillow": ("tap", code_n_glued),
    "shj-hearts": ("tap", lambda b, w: expand(b, w, r"\b([A-Z])\s*\((\d+)\)")),
    "cr-lovehearts": ("tap", lambda b, w: expand(b, w, r"\b([A-Z])\s+(\d+)\b")),
    "scc-bee": (
        "tap",
        lambda b: [
            (k.group(1), int(k.group(2)) if k.lastindex == 2 else 1)
            for k in (
                re.match(r"^\(([a-z ]+)\)\s*sc\s*(\d+)$", tok.strip()) or re.match(r"^([a-z]+)$", tok.strip())
                for tok in b.split(",")
            )
            if k
        ],
    ),
    "tr": ("tap", lambda b: [(c.lower(), int(n)) for n, c in re.findall(r"(\d+)\s*sc\s*in\s*(c\d)", b)]),
    "lb": ("tap", lambda b: [(c.lower(), int(n)) for n, c in re.findall(r"(\d+)\s*sc\s*with\s*(C\d)", b)]),
    "mmd": ("tap", lambda b: [(c, int(n)) for n, c in re.findall(r"sc\s*(\d+)\s*in\s*([a-z]+)", b)]),
    "pud-heart": (
        "tap",
        lambda b: [
            ({"Sc": "main", "P": "main", "Hsc": "heart"}[k], int(n or 1))
            for k, n in re.findall(
                r"\b(Sc|Hsc|P) in (?:first|nxt) (?:(\d+) ?sts?|st)\b",
                re.sub(r"\(([^()]+)\)\s*(\d+) times", lambda m: ", ".join([m.group(1)] * int(m.group(2))), b),
            )
        ],
    ),
    "sf-tree": (
        "tap",
        lambda b: (
            [("bobbin" if bob else "main", int(n)) for bob, n in re.findall(r"(bobbin )?sc (\d+)", b)]
            or [("main", int(n)) for n in re.findall(r"(\d+) sc", b)]
        ),
    ),
}
START = {
    "tr": r"^Row1: sc in second chain",
    "lb": r"^Row 1\. Ch22",
    "mmd": r"^Row 1: sc in the second",
    "shj-hearts": r"^Row 1: Sc in second ch",
    "cr-lovehearts": r"^Row 1 \[RS\]",
    "pp-pillow": r"^Row 1:",
    "sf-tree": r"^Row 1-4",
    "scc-bee": r"^Row 1",
    "vetka-cat": r"^ROW 4 ",
    "hanjan-rainbow": r"^Row 1 \(RS\)",
}
END = {
    "tr": r"^Row 13-15",
    "lb": r"^Row 11-14",
    "mmd": r"^Row 16",
    "scc-bee": r"^Row 75\b",
    "pud-heart": r"^Row 69|Border|border",
    "vetka-cat": r"^ROW 104",
    "sf-tree": r"^Row 2[0-9]",
}


def parse(id_):
    kind, fn = STYLE[id_]
    raw = (S / id_ / "p01.txt").read_text(encoding="utf-8").replace("\xa0", " ").splitlines()
    raw = [re.sub(r"\(\d+ (?:boxes|squares|box|square)\)", "", line).strip() for line in raw]
    lines, started = [], id_ not in START
    for line in raw:  # join a row's continuation lines onto its head line
        if not started:
            if re.search(START[id_], line):
                started = True
            else:
                continue
        if HEAD.match(line) or (id_.startswith("wi-") and NUM_HEAD.match(line)) or not lines or not line:
            lines.append(line)
        elif (
            lines[-1]
            and (HEAD.match(lines[-1]) or NUM_HEAD.match(lines[-1]))
            and not re.match(r"^[A-Z][a-z]+ ", line)
        ):
            lines[-1] += " " + line
        else:
            lines.append(line)
    rows, plain = {}, []
    width_guess = None
    if id_ == "vetka-cat":
        rows.update({r: [["white", 70]] for r in (1, 2, 3)})
    for line in lines:
        m = HEAD.match(line) or (NUM_HEAD.match(line) if id_.startswith("wi-") else None)
        if not m:
            continue
        a, b, body = (
            (
                int(m.group(1)),
                int(m.group(2)) if m.lastindex >= 3 and m.group(2) else None,
                m.group(m.lastindex),
            )
            if m.re is HEAD
            else (int(m.group(1)), None, m.group(2))
        )
        rep = re.search(r"repeat row (\d+)", body, re.I)
        if rep:
            runs = rows.get(int(rep.group(1)))
        elif fn.__code__.co_argcount == 2:
            runs = merge(fn(body, width_guess or 0))
        else:
            runs = merge(fn(body))
        if not runs and kind == "tap" and re.search(r"\bsc\b", body, re.I):
            for r in range(a, (b or a) + 1):
                plain.append(r)
            if id_ in END and re.search(END[id_], line):
                break
            continue
        if not runs:
            continue
        for r in range(
            a, (b or a) + 1
        ):  # first printing wins: a later "Rows 3-75: repeat row 2" is another panel
            if r not in rows:
                rows[r] = [list(x) for x in runs]
        if kind == "tap" and width_guess is None and sum(n for _, n in runs) > 4:
            width_guess = sum(n for _, n in runs)
        if id_ in END and re.search(END[id_], line):
            break
    order = []
    for r in sorted(rows):
        for c, _ in rows[r]:
            if c not in order:
                order.append(c)
    for r in plain:  # a row written as plain sc: the first colour, full width
        if r not in rows and order:
            rows[r] = [[order[0], width_guess]]
    for r in sorted(rows):
        for c, _ in rows[r]:
            if c not in order:
                order.append(c)
    code = {c: (c if (len(c) <= 2 and c.isupper()) else chr(65 + order.index(c))) for c in order}
    out = [{"row": r, "runs": [[code[c], n] for c, n in rows[r]]} for r in sorted(rows)]
    widths = collections.Counter(sum(n for _, n in rr["runs"]) for rr in out)
    bad = [
        rr["row"]
        for rr in out
        if (kind == "tap" and sum(n for _, n in rr["runs"]) != widths.most_common(1)[0][0])
    ]
    if kind == "c2c":
        peak = max(sum(n for _, n in rr["runs"]) for rr in out)
        bad = [
            rr["row"]
            for rr in out
            if sum(n for _, n in rr["runs"]) != (rr["row"] if rr["row"] <= peak else 2 * peak - rr["row"])
        ]
    print(
        f"{id_:15} {kind} rows {len(out)} (first {out[0]['row'] if out else '-'}, last {out[-1]['row'] if out else '-'}) widths {dict(widths) if kind == 'tap' else 'peak ' + str(peak)} codes {code} BAD {bad[:12]}"
    )
    json.dump({"written_rows": out}, open(S / "truth" / f"{id_}.json", "w", encoding="utf-8"), indent=1)
    return bad


(S / "truth").mkdir(exist_ok=True)
bad_total = {id_: parse(id_) for id_ in (sys.argv[2:] or STYLE)}
bad_total = {k: v for k, v in bad_total.items() if v}
if bad_total:  # a row whose width disagrees with its neighbours: a source typo or a parser gap, listed above
    sys.exit(f"rows with an odd width: {bad_total}")
