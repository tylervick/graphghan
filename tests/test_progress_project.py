from graphghan import progress, rowsdoc

ROWS = [
    {"label": "R 1", "from": 1, "to": 1, "count": 6, "text": "a"},
    {"label": "R 2 - R 4", "from": 2, "to": 4, "count": 6, "text": "b"},
]
RDOC = {"schema": 1, "id": rowsdoc.rows_id(ROWS), "piece": {"title": "Strip"}, "rows": ROWS}
MANIFEST = {
    "schema": 2,
    "id": "bag",
    "title": "Bag",
    "version": "1",
    "charts": [],
    "pieces": [
        {"id": "strip", "title": "Strip", "make": 2, "rows": "pieces/strip.rows.json", "rows_id": RDOC["id"]}
    ],
    "assembly": [{"title": "Sew up"}],
}


def doc(pieces, events, assembly_done=()):
    return {
        "schema": 2,
        "pattern_id": "bag",
        "pieces": pieces,
        "current": {"piece": "strip", "copy": 1},
        "assembly_done": list(assembly_done),
        "events": events,
    }


def ev(t, row, kind="advance", piece="strip", copy=1):
    return {"t": t, "piece": piece, "copy": copy, "row": row, "run": 0, "kind": kind}


def test_a_written_piece_counts_rows_done_before_the_cursor():
    d = doc(
        [
            {
                "piece": "strip",
                "copy": 1,
                "doc_id": RDOC["id"],
                "cursor": {"row": 3, "run": 0},
                "finished": None,
            }
        ],
        [],
    )
    s = progress.summarize_project(d, MANIFEST, {RDOC["id"]: RDOC})
    assert s["pieces"][0] == {
        "piece": "strip",
        "copy": 1,
        "kind": "rows",
        "rows_done": 2,
        "total_rows": 4,
        "percent": 50.0,
        "stitches_done": 12,
        "total_stitches": 24,
        "finished": False,
    }
    assert (s["pieces_done"], s["pieces_total"], s["assembly_done"], s["assembly_total"]) == (0, 2, 0, 1)


def test_the_finishing_advance_counts_the_last_row():
    events = [
        ev("2026-09-12T18:00:00Z", 2),
        ev("2026-09-12T18:01:00Z", 4, "jump"),
        ev("2026-09-12T18:02:00Z", 4),
    ]
    d = doc(
        [
            {
                "piece": "strip",
                "copy": 1,
                "doc_id": RDOC["id"],
                "cursor": {"row": 4, "run": 0},
                "finished": "2026-09-12T18:02:00Z",
            }
        ],
        events,
    )
    s = progress.summarize_project(d, MANIFEST, {RDOC["id"]: RDOC})
    assert s["pieces"][0]["rows_done"] == 4 and s["pieces"][0]["finished"] is True
    assert s["sessions"] == [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:02:00Z", "cells": 0, "rows": 4}
    ]
    assert s["pieces_done"] == 1
    assert s["stitches_per_hour"] is None  # written rows get no pace figure
