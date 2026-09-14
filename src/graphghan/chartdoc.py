"""Chart documents, schema 2: run strings, chart ids, technique sequencing, validation, derived sizes.

Everything here works on plain dicts (the JSON document), never on the numpy grid, so the same
rules can be re-implemented from the spec (docs/chart-format.md) in any language.
"""

from __future__ import annotations

import hashlib
import json
import re

RUN_RE = re.compile(r"(\d+)([A-Za-z]{1,3})")
ROW_RE = re.compile(r"^(\d+[A-Za-z]{1,3})+$")
CODE_RE = re.compile(r"^[A-Za-z]{1,3}$")
HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")

TECHNIQUE_ROWS = {"type": "rows", "start": "bottom", "first_side": "RS", "rs_direction": "rtl", "turn": True}

BOUNDARY_KINDS = ("turn", "join", "rejoin", "spiral", "return")
CHAIN_COLORS = ("next", "current")


class UnsupportedTechnique(ValueError):
    """The document has no derivable working order (unknown/reserved technique and no passes)."""


def parse_runs(s: str) -> list[tuple[str, int]]:
    return [(code, int(n)) for n, code in RUN_RE.findall(s)]


def _canonical(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def chart_id(codes: list[str], rows: list[str], technique: dict, passes: list[dict] | None = None) -> str:
    obj = {"codes": list(codes), "rows": list(rows), "technique": technique}
    if passes is not None:
        obj["passes"] = passes
    return "sha256:" + hashlib.sha256(_canonical(obj)).hexdigest()


def _other_side(s: str) -> str:
    return "WS" if s == "RS" else "RS"


def _flip(d: str) -> str:
    return "ltr" if d == "rtl" else "rtl"


def _normalize_pass(p: dict) -> dict:
    return {
        "label": str(p.get("label", "")),
        "side": p.get("side"),
        "direction": p.get("direction"),
        "grid_row": p.get("grid_row"),
        "runs": [{"code": r["code"], "count": int(r["count"]), "x0": r.get("x0")} for r in p["runs"]],
    }


def sequence(doc: dict) -> list[dict]:
    """Passes in working order. Explicit `passes` win; else derive from `technique`."""
    if isinstance(doc.get("passes"), list):
        return [_normalize_pass(p) for p in doc["passes"]]
    t = doc.get("technique") or {}
    typ = t.get("type")
    if typ not in ("rows", "rounds"):
        raise UnsupportedTechnique(
            f"technique {typ!r} has no derivable working order and the chart has no passes"
        )
    rows = doc["rows"]
    h = len(rows)
    start = t.get("start", "bottom")
    first_side = t.get("first_side", "RS")
    rs_direction = t.get("rs_direction", "rtl")
    label = "Row" if typ == "rows" else "Round"
    out = []
    for k in range(1, h + 1):
        y = h - k if start == "bottom" else k - 1
        if typ == "rows":
            side = first_side if k % 2 == 1 else _other_side(first_side)
            direction = rs_direction if side == "RS" else _flip(rs_direction)
        else:
            side, direction = first_side, rs_direction
        runs, x = [], 0
        for code, n in parse_runs(rows[y]):
            runs.append({"code": code, "count": n, "x0": x})
            x += n
        if direction == "rtl":
            runs.reverse()
        out.append(
            {"label": f"{label} {k}", "side": side, "direction": direction, "grid_row": y, "runs": runs}
        )
    return out


def cell_aspect(doc: dict) -> float:
    g = doc["gauge"]
    return round(g["stitches"] / g["rows"], 4)


def finished_size(doc: dict) -> tuple[float, float, str]:
    g = doc["gauge"]
    per = g["over"]["value"]
    w = doc["chart"]["width"] / (g["stitches"] / per)
    h = doc["chart"]["height"] / (g["rows"] / per)
    return round(w, 1), round(h, 1), g["over"]["unit"]


def validate_document(doc: dict) -> list[str]:
    """Structural checks the JSON Schema cannot express. Returns human-readable problems."""
    problems: list[str] = []
    palette = doc.get("palette", [])
    codes = [p.get("code") if isinstance(p, dict) else None for p in palette]
    seen: set[str] = set()
    for i, p in enumerate(palette):
        if not isinstance(p, dict):
            problems.append(f"palette[{i}] is not an object")
            continue
        code = p.get("code", "")
        if not isinstance(code, str) or not CODE_RE.match(code):
            problems.append(f"palette[{i}].code {code!r} is not 1-3 letters")
        else:  # only a well-formed code can be a duplicate of another
            if code in seen:
                problems.append(f"palette[{i}].code {code!r} is a duplicate")
            seen.add(code)
        if not HEX_RE.match(str(p.get("hex", ""))):
            problems.append(f"palette[{i}].hex {p.get('hex')!r} is not #RRGGBB")
    width = doc.get("chart", {}).get("width")
    height = doc.get("chart", {}).get("height")
    rows = doc.get("rows", [])
    if height != len(rows):
        problems.append(f"chart.height {height} does not match {len(rows)} rows")
    known = set(seen)
    for y, s in enumerate(rows):
        if not isinstance(s, str) or not ROW_RE.match(s):
            problems.append(f"row {y} {s!r} is not a run string")
            continue
        total = 0
        for code, n in parse_runs(s):
            if code not in known:
                problems.append(f"row {y} uses unknown code {code!r}")
            total += n
        if total != width:
            problems.append(f"row {y} sums to {total}, not chart.width {width}")
    for name, layer in (doc.get("layers") or {}).items():
        lrows = layer.get("rows", [])
        if len(lrows) != len(rows):
            problems.append(f"layers.{name} has {len(lrows)} rows, chart has {len(rows)}")
        legend = set((layer.get("legend") or {}).keys())
        for y, s in enumerate(lrows):
            if not isinstance(s, str) or not ROW_RE.match(s):
                problems.append(f"layers.{name} row {y} is not a run string")
                continue
            if sum(n for _, n in parse_runs(s)) != width:
                problems.append(f"layers.{name} row {y} does not sum to chart.width")
            for code, _ in parse_runs(s):
                if code not in legend:
                    problems.append(f"layers.{name} row {y} uses code {code!r} missing from legend")
    passes = doc.get("passes")
    if isinstance(passes, list):
        cells = [[c for c, n in parse_runs(s) for _ in range(n)] if isinstance(s, str) else [] for s in rows]
        for i, p in enumerate(passes):
            if not isinstance(p, dict):
                problems.append(f"passes[{i}] is not an object")
                continue
            gy = p.get("grid_row")
            if not isinstance(gy, int) or isinstance(gy, bool):
                gy = None
            runs = p.get("runs")
            if not isinstance(runs, list):
                problems.append(f"passes[{i}].runs is not a list")
                continue
            for j, r in enumerate(runs):
                if not isinstance(r, dict):
                    problems.append(f"passes[{i}].runs[{j}] is not an object")
                    continue
                if r.get("code") not in known:
                    problems.append(f"passes[{i}].runs[{j}] uses unknown code {r.get('code')!r}")
                    continue
                count = r.get("count")
                if not isinstance(count, int) or isinstance(count, bool) or count < 1:
                    problems.append(f"passes[{i}].runs[{j}].count {count!r} is not a positive integer")
                    continue
                x0 = r.get("x0")
                if not isinstance(x0, int) or isinstance(x0, bool):
                    x0 = None
                if gy is None or x0 is None:
                    continue
                # Bound against the row as parsed, not chart.width: a short row with an in-width
                # pass must report "outside the grid" rather than IndexError on the cell check.
                if not (0 <= gy < len(cells)) or x0 < 0 or x0 + count > len(cells[gy]):
                    problems.append(f"passes[{i}].runs[{j}] lies outside the grid")
                    continue
                if any(cells[gy][x] != r["code"] for x in range(x0, x0 + count)):
                    problems.append(
                        f"passes[{i}].runs[{j}] does not match the cells at grid_row {gy}, x0 {x0}"
                    )
    gauge = doc.get("gauge")
    boundary = gauge.get("boundary") if isinstance(gauge, dict) else None
    if boundary is not None:
        if not isinstance(boundary, dict):
            problems.append("gauge.boundary is not an object")
        else:
            if boundary.get("kind") not in BOUNDARY_KINDS:
                problems.append(
                    f"gauge.boundary.kind {boundary.get('kind')!r} is not one of {BOUNDARY_KINDS}"
                )
            chain = boundary.get("chain")
            if isinstance(chain, bool) or not isinstance(chain, int) or chain < 0:
                problems.append(f"gauge.boundary.chain {chain!r} is not an integer >= 0")
            if "color" in boundary and boundary["color"] not in CHAIN_COLORS:
                problems.append(f"gauge.boundary.color {boundary['color']!r} is not one of {CHAIN_COLORS}")
    foundation = doc.get("foundation")
    if isinstance(foundation, dict) and isinstance(width, int):
        chain = foundation.get("chain")
        into = foundation.get("first_stitch_in", 1)
        if isinstance(chain, int) and isinstance(into, int) and not isinstance(chain, bool):
            needed = width + into - 1
            if chain < needed:  # row 1 could not be worked: refuse, never warn (#50)
                problems.append(
                    f"foundation.chain {chain} is shorter than the {needed} chains row 1 needs "
                    f"(width {width} + first_stitch_in {into} - 1)"
                )
    expected = chart_id(codes, rows, doc.get("technique") or {}, passes if isinstance(passes, list) else None)
    actual = doc.get("chart", {}).get("id")
    if actual != expected:
        problems.append(f"chart.id {actual!r} does not match content ({expected})")
    return problems
