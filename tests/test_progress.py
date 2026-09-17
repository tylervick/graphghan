import pytest

from graphghan import chartdoc, progress

ROWS = ["14A"] * 2 + ["2A10B2A"] * 8 + ["14A"] * 2
DOC = {"rows": ROWS, "technique": dict(chartdoc.TECHNIQUE_ROWS)}
PASSES = chartdoc.sequence(DOC)


def ev(t, row, run, kind="advance"):
    return {"t": t, "row": row, "run": run, "kind": kind}


def test_cells_before_and_total():
    assert progress.total_cells(PASSES) == 168
    assert progress.cells_before(PASSES, 1, 0) == 0
    assert progress.cells_before(PASSES, 3, 1) == 30  # rows 1-2 (28) + first run of row 3 (2)
    assert progress.cells_before(PASSES, 3, 3) == 42  # cursor past the last run of row 3
    with pytest.raises(ValueError):
        progress.cells_before(PASSES, 13, 0)
    with pytest.raises(ValueError):
        progress.cells_before(PASSES, 3, 4)


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
            ev("2026-09-13T10:15:00Z", 5, 1),
        ],
    }
    s = progress.summarize(doc, PASSES)
    assert s == {
        "percent": 34.5,
        "cells_done": 58,
        "total_cells": 168,
        "stitches_done": 58,
        "total_stitches": 168,
        "sessions": [
            {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:10:00Z", "cells": 30, "stitches": 30},
            {"start": "2026-09-12T19:00:00Z", "end": "2026-09-12T19:04:00Z", "cells": 10, "stitches": 10},
            {"start": "2026-09-13T10:00:00Z", "end": "2026-09-13T10:15:00Z", "cells": 18, "stitches": 18},
        ],
        "active_seconds": 1740,
        "stitches_per_hour": 120.0,
    }


def test_summarize_reports_cells_and_stitches_for_a_stitch_chart():
    doc = {
        "cursor": {"row": 5, "run": 1},
        "events": [
            ev("2026-09-12T18:00:00Z", 2, 0),
            ev("2026-09-12T18:05:00Z", 3, 0),
            ev("2026-09-12T18:10:00Z", 3, 1),
        ],
    }
    s = progress.summarize(doc, PASSES)
    assert s["total_cells"] == s["total_stitches"]
    assert s["cells_done"] == s["stitches_done"]
    assert s["sessions"][0]["cells"] == s["sessions"][0]["stitches"]


def test_summarize_withholds_stitch_numbers_for_a_non_stitch_kind():
    doc = {
        "cursor": {"row": 5, "run": 1},
        "events": [
            ev("2026-09-12T18:00:00Z", 2, 0),
            ev("2026-09-12T18:05:00Z", 3, 0),
            ev("2026-09-12T18:10:00Z", 3, 1),
        ],
    }
    s = progress.summarize(doc, PASSES, kind="block")
    assert "total_stitches" not in s
    assert "stitches_done" not in s
    assert "stitches_per_hour" not in s
    assert all("stitches" not in sess for sess in s["sessions"])
    # Progress itself is unchanged: cells done over cells total is the same arithmetic.
    assert s["percent"] == progress.summarize(doc, PASSES)["percent"]
    assert s["total_cells"] == progress.summarize(doc, PASSES)["total_cells"]


def test_summarize_without_events():
    doc = {"cursor": {"row": 1, "run": 0}, "events": []}
    assert progress.summarize(doc, PASSES) == {
        "percent": 0.0,
        "cells_done": 0,
        "total_cells": 168,
        "stitches_done": 0,
        "total_stitches": 168,
        "sessions": [],
        "active_seconds": 0,
        "stitches_per_hour": None,
    }


def test_summarize_single_event_session_has_no_pace():
    doc = {"cursor": {"row": 3, "run": 0}, "events": [ev("2026-09-12T18:00:00Z", 3, 0)]}
    s = progress.summarize(doc, PASSES)
    # one event is a session of zero length: its stitches still count, its pace is unknowable
    assert s["sessions"] == [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:00:00Z", "cells": 28, "stitches": 28}
    ]
    assert s["active_seconds"] == 0 and s["stitches_per_hour"] is None
    assert s["stitches_done"] == 28


def test_summarize_clamps_a_session_that_went_backwards():
    doc = {
        "cursor": {"row": 2, "run": 0},
        "events": [
            ev("2026-09-12T18:00:00Z", 3, 2),
            # an hour later, so a new session that starts at (3, 2) and frogs back to (2, 0)
            ev("2026-09-12T19:00:00Z", 2, 0, "back"),
            ev("2026-09-12T19:05:00Z", 2, 0, "back"),
        ],
    }
    s = progress.summarize(doc, PASSES)
    assert progress.cells_before(PASSES, 2, 0) < progress.cells_before(PASSES, 3, 2)
    assert [x["stitches"] for x in s["sessions"]] == [40, 0]  # not -26
    assert s["stitches_done"] == 14  # the cursor itself is free to move back


def test_summarize_sorts_events_by_time():
    doc = {
        "cursor": {"row": 2, "run": 0},
        "events": [ev("2026-09-12T18:05:00Z", 2, 0, "back"), ev("2026-09-12T18:00:00Z", 3, 0)],
    }
    s = progress.summarize(doc, PASSES)
    assert s["sessions"] == [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:05:00Z", "cells": 14, "stitches": 14}
    ]


def test_from_legacy_code():
    d = progress.from_legacy_code("craigh-na-dun", 42, 3)
    assert d["schema"] == 1 and d["pattern_id"] == "craigh-na-dun" and d["chart_id"] is None
    assert d["cursor"] == {"row": 42, "run": 3} and d["events"] == []


def test_cells_before_counts_the_stitch_offset():
    assert progress.cells_before(PASSES, 1, 0, 10) == 10
    assert progress.cells_before(PASSES, 3, 1, 5) == 35
    assert progress.cells_before(PASSES, 1, 1, 0) == 14  # the boundary position
    with pytest.raises(ValueError):
        progress.cells_before(PASSES, 1, 0, 14)  # a completed run is the next run at 0
    with pytest.raises(ValueError):
        progress.cells_before(PASSES, 1, 1, 1)  # nothing is worked at the boundary


def test_summarize_reads_stitch_from_cursor_and_events():
    doc = {
        "schema": 1,
        "pattern_id": "minimal",
        "chart_id": "sha256:" + "0" * 64,
        "cursor": {"row": 3, "run": 2},
        "events": [
            {"t": "2026-09-12T18:00:00Z", "row": 1, "run": 0, "stitch": 10, "kind": "advance"},
            {"t": "2026-09-12T18:00:30Z", "row": 1, "run": 1, "kind": "advance"},
            {"t": "2026-09-12T18:01:00Z", "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T18:01:30Z", "row": 1, "run": 1, "kind": "back"},
            {"t": "2026-09-12T18:02:00Z", "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T19:00:00Z", "row": 3, "run": 1, "stitch": 5, "kind": "jump"},
            {"t": "2026-09-12T19:03:00Z", "row": 3, "run": 2, "kind": "advance"},
        ],
    }
    s = progress.summarize(doc, PASSES)
    assert s["cells_done"] == 40
    assert [x["cells"] for x in s["sessions"]] == [14, 26]
    assert s["active_seconds"] == 300
    assert s["stitches_per_hour"] == 480.0
    assert s["percent"] == 23.8
