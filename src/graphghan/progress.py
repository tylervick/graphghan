"""Progress documents (schema 1): cursor math, sessions, and pace. Pure functions over passes."""

from __future__ import annotations

from datetime import datetime, timezone

GAP_SECONDS = 1800


def _parse(t: str) -> datetime:
    return datetime.fromisoformat(t.replace("Z", "+00:00"))


def _fmt(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def total_stitches(passes: list[dict]) -> int:
    return sum(r["count"] for p in passes for r in p["runs"])


def stitches_before(passes: list[dict], row: int, run: int) -> int:
    """Stitches completed when the cursor sits at (row, run): every earlier pass plus runs before `run`."""
    if not 1 <= row <= len(passes):
        raise ValueError(f"row {row} outside 1..{len(passes)}")
    runs = passes[row - 1]["runs"]
    if not 0 <= run <= len(runs):
        raise ValueError(f"run {run} outside 0..{len(runs)} for row {row}")
    before = sum(r["count"] for p in passes[: row - 1] for r in p["runs"])
    return before + sum(r["count"] for r in runs[:run])


def summarize(doc: dict, passes: list[dict], gap_seconds: int = GAP_SECONDS) -> dict:
    total = total_stitches(passes)
    cur = doc["cursor"]
    done = stitches_before(passes, cur["row"], cur["run"])
    events = sorted(doc.get("events") or [], key=lambda e: _parse(e["t"]))
    sessions: list[dict] = []
    current = None
    prev_cursor = (1, 0)
    prev_t = None
    for e in events:
        t = _parse(e["t"])
        if current is None or (t - prev_t).total_seconds() > gap_seconds:
            if current is not None:
                sessions.append(current)
            current = {"start": t, "end": t, "from": prev_cursor, "to": prev_cursor}
        current["end"] = t
        current["to"] = (e["row"], e["run"])
        prev_cursor, prev_t = (e["row"], e["run"]), t
    if current is not None:
        sessions.append(current)
    out_sessions, active, advanced = [], 0, 0
    for s in sessions:
        st = max(0, stitches_before(passes, *s["to"]) - stitches_before(passes, *s["from"]))
        secs = int((s["end"] - s["start"]).total_seconds())
        active += secs
        advanced += st
        out_sessions.append({"start": _fmt(s["start"]), "end": _fmt(s["end"]), "stitches": st})
    return {
        "percent": round(100.0 * done / total, 1) if total else 0.0,
        "stitches_done": done,
        "total_stitches": total,
        "sessions": out_sessions,
        "active_seconds": active,
        "stitches_per_hour": round(advanced / (active / 3600.0), 1) if active else None,
    }


def from_legacy_code(slug: str, row: int, run: int) -> dict:
    """A cursor-only document from the PWA's base64 {slug,row,run} code."""
    return {
        "schema": 1,
        "pattern_id": slug,
        "chart_id": None,
        "cursor": {"row": row, "run": run},
        "events": [],
    }
