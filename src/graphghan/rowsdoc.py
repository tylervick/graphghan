"""Written-rows documents, schema 1: a piece that is not a grid (spec 2026-09-25 §5.2).

Each entry is one printed line: rows `from`..`to` share its text; the last may be open-ended
("repeat until desired length"). Plain dicts in, plain dicts out, like chartdoc.
"""

from __future__ import annotations

import hashlib
import json

from .chartdoc import CODE_RE

ROWS_SCHEMA = 1
_ID_KEYS = ("from", "to", "text", "count", "code", "repeat")


def _canonical(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def rows_id(entries: list[dict]) -> str:
    """The document's id: its rows, not its titles. An absent key stays absent, never null."""
    rows = [{k: e[k] for k in _ID_KEYS if k in e} for e in entries]
    return "sha256:" + hashlib.sha256(_canonical({"rows": rows})).hexdigest()


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def validate_rows_document(doc: dict) -> list[str]:
    """What the JSON Schema cannot say: the rows tile 1..N, only the last is open, codes exist, the id."""
    problems: list[str] = []
    if doc.get("schema") != ROWS_SCHEMA:
        problems.append(f"schema {doc.get('schema')!r} is not {ROWS_SCHEMA}")
    entries = doc.get("rows")
    if not isinstance(entries, list) or not entries:
        return problems + ["rows is empty"]
    codes = {p.get("code") for p in doc.get("palette") or [] if isinstance(p, dict)}
    expected = 1
    for i, e in enumerate(entries):
        if not isinstance(e, dict):
            problems.append(f"rows[{i}] is not an object")
            return problems
        start, end = e.get("from"), e.get("to")
        if not _is_int(start) or start != expected:
            problems.append(f"rows[{i}] starts at {start!r}; row {expected} is missing or printed twice")
            return problems
        if end is None:
            if "repeat" not in e:
                problems.append(f"rows[{i}] has no `to` and no `repeat`")
            elif i != len(entries) - 1:
                problems.append(f"rows[{i}] is open-ended; only the last entry may be")
            expected = None
        elif not _is_int(end) or end < start:
            problems.append(f"rows[{i}].to {end!r} is before its `from` {start}")
            return problems
        else:
            expected = end + 1
        if "count" in e and (not _is_int(e["count"]) or e["count"] < 1):
            problems.append(f"rows[{i}].count {e['count']!r} is not a positive integer")
        if "code" in e and (
            not isinstance(e["code"], str) or not CODE_RE.match(e["code"]) or e["code"] not in codes
        ):
            problems.append(f"rows[{i}] uses code {e.get('code')!r}, which is not in the palette")
        if expected is None:
            break
    if doc.get("id") != rows_id(entries):
        problems.append(f"id {doc.get('id')!r} does not match the rows ({rows_id(entries)})")
    return problems


def total_rows(doc: dict) -> int | None:
    last = doc["rows"][-1]
    return last.get("to")


def _all_counted(doc: dict) -> bool:
    return all("count" in e for e in doc["rows"])


def total_stitches(doc: dict) -> int | None:
    if total_rows(doc) is None or not _all_counted(doc):
        return None
    return sum(e["count"] * (e["to"] - e["from"] + 1) for e in doc["rows"])


def stitches_before(doc: dict, row: int) -> int | None:
    """Stitches in rows 1 .. row-1, when every entry states its count."""
    if not _all_counted(doc):
        return None
    total = 0
    for e in doc["rows"]:
        last = e.get("to", row - 1)
        n = max(0, min(last, row - 1) - e["from"] + 1)
        total += n * e["count"]
    return total


def pass_at(doc: dict, row: int) -> dict | None:
    """Row `row` as the Work screen shows it: the entry's text, labelled with its place in a range."""
    if row < 1:
        return None
    for i, e in enumerate(doc["rows"]):
        end = e.get("to")
        if row < e["from"] or (end is not None and row > end):
            continue
        k = row - e["from"] + 1
        if end is None:
            label = f"{e['label']} ({k})"
        elif end == e["from"]:
            label = e["label"]
        else:
            label = f"{e['label']} ({k} of {end - e['from'] + 1})"
        return {"label": label, "text": e["text"], "count": e.get("count"), "code": e.get("code"), "entry": i}
    return None
