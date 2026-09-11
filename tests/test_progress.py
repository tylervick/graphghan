import pytest

from graphghan import chartdoc, progress

ROWS = ["14A"] * 2 + ["2A10B2A"] * 8 + ["14A"] * 2
DOC = {"rows": ROWS, "technique": dict(chartdoc.TECHNIQUE_ROWS)}
PASSES = chartdoc.sequence(DOC)


def ev(t, row, run, kind="advance"):
    return {"t": t, "row": row, "run": run, "kind": kind}


def test_stitches_before_and_total():
    assert progress.total_stitches(PASSES) == 168
    assert progress.stitches_before(PASSES, 1, 0) == 0
    assert progress.stitches_before(PASSES, 3, 1) == 30  # rows 1-2 (28) + first run of row 3 (2)
    assert progress.stitches_before(PASSES, 3, 3) == 42  # cursor past the last run of row 3
    with pytest.raises(ValueError):
        progress.stitches_before(PASSES, 13, 0)
    with pytest.raises(ValueError):
        progress.stitches_before(PASSES, 3, 4)


def test_summarize_sessions_pace_and_percent():
    doc = {
        "schema": 1,
        "pattern_id": "minimal",
        "chart_id": "sha256:" + "0" * 64,
        "cursor": {"row": 5, "run": 1},
        "started": "2026-09-12T18:00:00Z",
        "events": [
            ev("2026-09-12T18:00:00Z", 2, 0),
            ev("2026-09-12T18:05:00Z", 3, 0),
            ev("2026-09-12T18:10:00Z", 3, 1),
            ev("2026-09-12T19:00:00Z", 3, 2),
            ev("2026-09-12T19:02:00Z", 3, 1, "back"),
            ev("2026-09-12T19:04:00Z", 3, 2),
            ev("2026-09-13T10:00:00Z", 5, 0, "jump"),
            ev("2026-09-13T10:30:00Z", 5, 1),
        ],
    }
    s = progress.summarize(doc, PASSES)
    assert s == {
        "percent": 34.5,
        "stitches_done": 58,
        "total_stitches": 168,
        "sessions": [
            {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:10:00Z", "stitches": 30},
            {"start": "2026-09-12T19:00:00Z", "end": "2026-09-12T19:04:00Z", "stitches": 10},
            {"start": "2026-09-13T10:00:00Z", "end": "2026-09-13T10:30:00Z", "stitches": 18},
        ],
        "active_seconds": 2640,
        "stitches_per_hour": 79.1,
    }


def test_summarize_without_events():
    doc = {"cursor": {"row": 1, "run": 0}, "events": []}
    assert progress.summarize(doc, PASSES) == {
        "percent": 0.0,
        "stitches_done": 0,
        "total_stitches": 168,
        "sessions": [],
        "active_seconds": 0,
        "stitches_per_hour": None,
    }


def test_summarize_sorts_events_by_time():
    doc = {
        "cursor": {"row": 2, "run": 0},
        "events": [ev("2026-09-12T18:05:00Z", 2, 0, "back"), ev("2026-09-12T18:00:00Z", 3, 0)],
    }
    s = progress.summarize(doc, PASSES)
    assert s["sessions"] == [{"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:05:00Z", "stitches": 14}]


def test_from_legacy_code():
    d = progress.from_legacy_code("craigh-na-dun", 42, 3)
    assert d["schema"] == 1 and d["pattern_id"] == "craigh-na-dun" and d["chart_id"] is None
    assert d["cursor"] == {"row": 42, "run": 3} and d["events"] == []
