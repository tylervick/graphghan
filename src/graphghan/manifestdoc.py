"""Pattern manifests, schemas 1 and 2 (spec 2026-09-25 §5.3). Schema 2 adds `pieces` and
`assembly`; a manifest without `pieces` is one piece, its default chart."""

from __future__ import annotations

import re

SLUG_RE = re.compile(r"^[a-z0-9-]+$")


def _default_chart(doc: dict) -> dict | None:
    charts = doc.get("charts") or []
    return next((c for c in charts if c.get("default")), charts[0] if charts else None)


def pieces(doc: dict) -> list[dict]:
    """The pieces in the pattern's order, `make` defaulted; one implicit piece for schema 1."""
    if "pieces" not in doc:
        chart = _default_chart(doc)
        return [
            {
                "id": "chart",
                "title": doc.get("title", ""),
                "make": 1,
                "chart": chart["id"] if chart else None,
                "pages": [],
            }
        ]
    out = []
    for p in doc["pieces"]:
        q = {"id": p["id"], "title": p["title"], "make": p.get("make", 1), "pages": p.get("pages", [])}
        if "chart" in p:
            q["chart"] = p["chart"]
        if "rows" in p:
            q["rows"] = p["rows"]
            q["rows_id"] = p.get("rows_id")
        out.append(q)
    return out


def validate_manifest(doc: dict) -> list[str]:
    problems: list[str] = []
    schema = doc.get("schema")
    charts = doc.get("charts") or []
    chart_ids = [c.get("id") for c in charts]
    defaults = [c for c in charts if c.get("default")]
    if charts and len(defaults) != 1:
        problems.append(f"charts has {len(defaults)} default entries; exactly one must be the default")
    if "pieces" not in doc:
        if schema not in (1, 2):
            problems.append(f"schema {schema!r} is not 1 or 2")
        return problems
    if schema != 2:
        problems.append(f"pieces needs schema 2, not {schema!r}")
    ps = doc["pieces"]
    if not isinstance(ps, list) or not ps:
        return problems + ["pieces is empty"]
    seen: set[str] = set()
    named: list[str] = []
    for i, p in enumerate(ps):
        pid = p.get("id")
        if not isinstance(pid, str) or not SLUG_RE.match(pid):
            problems.append(f"pieces[{i}].id {pid!r} is not a slug")
        elif pid in seen:
            problems.append(f"pieces[{i}].id {pid!r} is a duplicate")
        seen.add(pid if isinstance(pid, str) else "")
        make = p.get("make", 1)
        if not isinstance(make, int) or isinstance(make, bool) or make < 1:
            problems.append(f"pieces[{i}].make {make!r} is not an integer >= 1")
        has_chart, has_rows = "chart" in p, "rows" in p
        if has_chart == has_rows:
            problems.append(f"pieces[{i}] must name exactly one of `chart` and `rows`")
        elif has_chart:
            if p["chart"] not in chart_ids:
                problems.append(f"pieces[{i}] names a chart {p['chart']!r} that is not in `charts`")
            named.append(p["chart"])
        elif not isinstance(p.get("rows_id"), str):
            problems.append(f"pieces[{i}] has `rows` but no `rows_id`")
    for c in chart_ids:
        if c not in named:
            problems.append(f"charts lists {c!r}, which no piece names")
    if len(named) != len(set(named)):
        problems.append("two pieces name the same chart; a pieced manifest lists each chart once")
    if defaults and named and defaults[0].get("id") != named[0]:
        problems.append("the default chart must be the first chart piece's chart")
    for i, step in enumerate(doc.get("assembly") or []):
        if not isinstance(step, dict) or not isinstance(step.get("title"), str):
            problems.append(f"assembly[{i}] has no title")
    return problems
