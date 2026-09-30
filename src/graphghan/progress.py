"""Progress documents (schemas 1 and 2): cursor math, sessions, and pace. Pure functions over passes."""

from __future__ import annotations

from datetime import datetime, timezone

from . import chartdoc, manifestdoc, rowsdoc

GAP_SECONDS = 1200


def _parse(t: str) -> datetime:
    return datetime.fromisoformat(t.replace("Z", "+00:00"))


def _fmt(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def total_cells(passes: list[dict]) -> int:
    return sum(r["count"] for p in passes for r in p["runs"])


def cells_before(passes: list[dict], row: int, run: int, stitch: int = 0) -> int:
    """Cells completed at (row, run, stitch): every earlier pass, the runs before `run`, and `stitch`
    cells of the run in hand. `run == len(runs)` is the boundary position and takes stitch 0 only."""
    if not 1 <= row <= len(passes):
        raise ValueError(f"row {row} outside 1..{len(passes)}")
    runs = passes[row - 1]["runs"]
    if not 0 <= run <= len(runs):
        raise ValueError(f"run {run} outside 0..{len(runs)} for row {row}")
    limit = runs[run]["count"] if run < len(runs) else 1
    if not 0 <= stitch < limit:
        raise ValueError(f"stitch {stitch} outside 0..{limit - 1} for row {row} run {run}")
    before = sum(r["count"] for p in passes[: row - 1] for r in p["runs"])
    return before + sum(r["count"] for r in runs[:run]) + stitch


def _cursor(obj: dict) -> tuple[int, int, int]:
    return (obj["row"], obj["run"], obj.get("stitch", 0))


def summarize(doc: dict, passes: list[dict], gap_seconds: int = GAP_SECONDS, kind: str = "stitch") -> dict:
    total = total_cells(passes)
    cur = doc["cursor"]
    done = cells_before(passes, *_cursor(cur))
    events = sorted(doc.get("events") or [], key=lambda e: _parse(e["t"]))
    sessions: list[dict] = []
    current = None
    prev_cursor = (1, 0, 0)
    prev_t = None
    for e in events:
        t = _parse(e["t"])
        if current is None or (t - prev_t).total_seconds() > gap_seconds:
            if current is not None:
                sessions.append(current)
            current = {"start": t, "end": t, "from": prev_cursor, "to": prev_cursor}
        current["end"] = t
        current["to"] = _cursor(e)
        prev_cursor, prev_t = _cursor(e), t
    if current is not None:
        sessions.append(current)
    out_sessions, active, advanced = [], 0, 0
    for s in sessions:
        st = max(0, cells_before(passes, *s["to"]) - cells_before(passes, *s["from"]))
        secs = int((s["end"] - s["start"]).total_seconds())
        active += secs
        advanced += st
        entry = {"start": _fmt(s["start"]), "end": _fmt(s["end"]), "cells": st}
        if kind == "stitch":
            entry["stitches"] = st
        out_sessions.append(entry)
    out = {
        "percent": round(100.0 * done / total, 1) if total else 0.0,
        "cells_done": done,
        "total_cells": total,
        "sessions": out_sessions,
        "active_seconds": active,
    }
    if kind == "stitch":
        out["stitches_done"] = done
        out["total_stitches"] = total
        out["stitches_per_hour"] = round(advanced / (active / 3600.0), 1) if active else None
    return out


def from_legacy_code(slug: str, row: int, run: int) -> dict:
    """A cursor-only document from the retired web viewer's base64 {slug,row,run} code (#78)."""
    return {
        "schema": 1,
        "pattern_id": slug,
        "chart_id": None,
        "cursor": {"row": row, "run": run},
        "events": [],
    }


def _key(obj: dict) -> tuple[str, int]:
    return (obj["piece"], obj.get("copy", 1))


def _rows_done(row: int, finished: bool, total: int | None) -> int:
    """Rows worked at a written cursor: the rows before it, or all of them once finished."""
    if finished:
        return total if total is not None else row
    return row - 1


def summarize_project(
    doc: dict, manifest: dict, docs: dict[str, dict], gap_seconds: int = GAP_SECONDS
) -> dict:
    """Progress schema 2 (spec 2026-09-25 §5.4): each started piece copy, the project counts, and
    sessions over every event. `docs` maps a chart id or rows id to that document.

    A piece's model is built lazily and cached, from every piece the manifest knows (not just the
    ones with a `pieces[]` summary entry): an event for a piece the manifest does not know is
    skipped, but an event for a known piece with no summary entry still counts in sessions."""
    by_id = {p["id"]: p for p in manifestdoc.pieces(manifest)}
    model_cache: dict[str, dict | None] = {}

    def piece_model(pid: str) -> dict | None:
        if pid not in model_cache:
            p = by_id.get(pid)
            if p is None:
                model_cache[pid] = None
            elif "chart" in p:
                chart = docs[p["chart"]]
                model_cache[pid] = {
                    "kind": "chart",
                    "passes": chartdoc.sequence(chart),
                    "cell": chartdoc.cell_kind(chart),
                }
            else:
                model_cache[pid] = {"kind": "rows", "doc": docs[p["rows_id"]]}
        return model_cache[pid]

    out_pieces = []
    for entry in doc["pieces"]:
        m = piece_model(entry["piece"])
        if m is None:
            continue  # a piece the manifest does not know, as the Swift reader's compactMap skips it
        finished = entry.get("finished") is not None
        cur = entry["cursor"]
        row = {"piece": entry["piece"], "copy": entry.get("copy", 1), "kind": m["kind"], "finished": finished}
        if m["kind"] == "chart":
            total = total_cells(m["passes"])
            done = cells_before(m["passes"], cur["row"], cur["run"], cur.get("stitch", 0))
            row.update(
                {
                    "percent": round(100.0 * done / total, 1) if total else 0.0,
                    "cells_done": done,
                    "total_cells": total,
                }
            )
            if m["cell"] == "stitch":
                row.update({"stitches_done": done, "total_stitches": total})
        else:
            rd = m["doc"]
            total = rowsdoc.total_rows(rd)
            done = _rows_done(cur["row"], finished, total)
            row["rows_done"] = done
            if total is not None:
                row["total_rows"] = total
                row["percent"] = round(100.0 * done / total, 1) if total else 0.0
            st_total = rowsdoc.total_stitches(rd)
            if st_total is not None:
                row["total_stitches"] = st_total
                row["stitches_done"] = st_total if finished else rowsdoc.stitches_before(rd, cur["row"])
        out_pieces.append(row)

    # Sessions: every event, split by time; each piece's worked amount across the session. Each
    # piece copy's running state is (cursor, finished), carried across sessions (not reset by a
    # gap): `finished` is True exactly when the event just applied is a finishing advance (an
    # `advance` on a written piece that leaves its row unchanged) and False after any other event
    # (back, jump, or an ordinary advance) — so un-finishing and re-finishing across a gap adds no
    # rows unless the row itself moved. An event naming a piece the manifest does not know is
    # skipped outright: it opens no session of its own and never updates `last`.
    events = sorted(doc.get("events") or [], key=lambda e: _parse(e["t"]))
    last: dict[tuple[str, int], tuple[tuple[int, int, int], bool]] = {}
    sessions, current, prev_t = [], None, None
    for e in events:
        m = piece_model(e["piece"])
        if m is None:
            continue
        t = _parse(e["t"])
        if current is None or (t - prev_t).total_seconds() > gap_seconds:
            if current is not None:
                sessions.append(current)
            current = {"start": t, "end": t, "from": {}, "to": {}}
        k = _key(e)
        before_state = last.get(k, ((1, 0, 0), False))
        current["from"].setdefault(k, before_state)
        cursor = (e["row"], e["run"], e.get("stitch", 0))
        finishing = e["kind"] == "advance" and cursor[0] == before_state[0][0] and m["kind"] == "rows"
        state = (cursor, finishing)
        current["to"][k] = state
        current["end"] = t
        last[k] = state
        prev_t = t
    if current is not None:
        sessions.append(current)

    out_sessions, active, chart_active, chart_stitches = [], 0, 0, 0
    for s in sessions:
        cells = rows = 0
        touched_chart = False
        for k, (start_cursor, start_finished) in s["from"].items():
            end_cursor, end_finished = s["to"][k]
            m = piece_model(k[0])
            if m["kind"] == "chart":
                touched_chart = True
                n = max(0, cells_before(m["passes"], *end_cursor) - cells_before(m["passes"], *start_cursor))
                cells += n
                if m["cell"] == "stitch":
                    chart_stitches += n
            else:
                total = rowsdoc.total_rows(m["doc"])
                before = _rows_done(start_cursor[0], start_finished, total)
                after = _rows_done(end_cursor[0], end_finished, total)
                rows += max(0, after - before)
        secs = int((s["end"] - s["start"]).total_seconds())
        active += secs
        if touched_chart:
            chart_active += secs
        out_sessions.append({"start": _fmt(s["start"]), "end": _fmt(s["end"]), "cells": cells, "rows": rows})

    return {
        "pieces": out_pieces,
        "pieces_done": sum(1 for p in out_pieces if p["finished"]),
        "pieces_total": sum(p["make"] for p in by_id.values()),
        "assembly_done": len(doc.get("assembly_done") or []),
        "assembly_total": len(manifest.get("assembly") or []),
        "sessions": out_sessions,
        "active_seconds": active,
        # Chart stitches only, over the time of the sessions that worked a chart (ruled in the plan).
        "stitches_per_hour": round(chart_stitches / (chart_active / 3600.0), 1) if chart_active else None,
    }
