"""The on-device reader (spec §9): only where Apple's model answers; skipped everywhere else."""

import os
from pathlib import Path

import pytest

from graphghan import applereader as ar
from graphghan.prose import check_prose

ROOT = Path(__file__).resolve().parents[1]


def test_row_blocks_rejoin_wrapped_lines_and_skip_prose():
    text = "Written rows\nRow 1 (RS): 189 Y (189 sts)\nRow 2 (WS): ch 1, turn, 2 Y, 3 G,\n4 Y (9 sts)\nCraigh Page 17\n"
    assert ar._row_blocks(text) == [
        "Row 1 (RS): 189 Y (189 sts)",
        "Row 2 (WS): ch 1, turn, 2 Y, 3 G, 4 Y (9 sts)",
    ]


def test_clean_runs_drops_chains_and_maps_names():
    class R:
        def __init__(self, count, code):
            self.count, self.code = count, code

    runs = [R(1, "ch"), R(1, "turn"), R(9, "Black"), R(2, "White"), R(3, "White")]
    assert ar._clean_runs(runs, {"black": "A", "white": "B"}) == [["A", 9], ["B", 5]]
    assert ar._clean_runs([R(4, "Gd")], None) == [["Gd", 4]]


def test_available_answers_without_the_sdk(monkeypatch):
    import builtins

    real = builtins.__import__

    def no_sdk(name, *a, **k):
        if name == "apple_fm_sdk":
            raise ImportError
        return real(name, *a, **k)

    monkeypatch.setattr(builtins, "__import__", no_sdk)
    ok, reason = ar.available()
    assert not ok and "apple-fm-sdk is not installed" in reason


@pytest.mark.skipif(
    not os.environ.get("GRAPHGHAN_APPLE_TESTS") or not ar.available()[0],
    reason="set GRAPHGHAN_APPLE_TESTS=1 on a Mac with Apple Intelligence: this takes the model half an hour",
)
def test_reads_our_own_pdf_into_a_valid_document():
    doc = ar.prose_from_pdf(ROOT / "fixtures" / "import" / "craigh-na-dun-final-hdc.pdf")
    assert check_prose(doc) == []
    rows = doc["written_rows"]
    assert len(rows) >= 100 and rows[0]["row"] == 1 and rows[0]["runs"] == [["Y", 176]]
