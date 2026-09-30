import json
from pathlib import Path

from jsonschema import Draft202012Validator

from graphghan import rowsdoc

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "schema" / "rows.schema.json").read_text(encoding="utf-8"))

ENTRIES = [
    {"label": "R 1", "from": 1, "to": 1, "code": "A", "count": 6, "text": "(Black) ch 7, 6 sc [6]"},
    {"label": "R 2 - R 26", "from": 2, "to": 26, "count": 6, "text": "ch 1, turn, 6 sc [6]"},
    {
        "label": "R 27 - 86",
        "from": 27,
        "to": 86,
        "code": "B",
        "count": 6,
        "text": "(White) ch 1, turn, 6 sc [6]",
    },
]


def doc(entries=None, **extra):
    entries = entries if entries is not None else [dict(e) for e in ENTRIES]
    d = {
        "schema": 1,
        "id": rowsdoc.rows_id(entries),
        "piece": {"title": "Side panel"},
        "palette": [
            {"code": "A", "name": "Black", "hex": "#201b18"},
            {"code": "B", "name": "White", "hex": "#ffffff"},
        ],
        "rows": entries,
    }
    d.update(extra)
    return d


def test_a_closed_document_validates():
    assert rowsdoc.validate_rows_document(doc()) == []
    assert Draft202012Validator(SCHEMA).is_valid(doc())


def test_id_leaves_out_titles_and_absent_keys():
    a = doc()
    b = doc(piece={"title": "Something else"}, notes=[{"title": "", "text": "x"}])
    assert a["id"] == b["id"]
    # an absent key is left out, never null: the same entry with "code": None is a different id
    withnull = [dict(ENTRIES[1], code=None)]
    assert rowsdoc.rows_id([ENTRIES[1]]) != rowsdoc.rows_id(withnull)


def test_totals():
    assert rowsdoc.total_rows(doc()) == 86
    assert rowsdoc.total_stitches(doc()) == 86 * 6
    assert rowsdoc.stitches_before(doc(), 27) == 26 * 6


def test_pass_labels_count_within_a_range():
    d = doc()
    assert rowsdoc.pass_at(d, 1) == {
        "label": "R 1",
        "text": "(Black) ch 7, 6 sc [6]",
        "count": 6,
        "code": "A",
        "entry": 0,
    }
    assert rowsdoc.pass_at(d, 31)["label"] == "R 27 - 86 (5 of 60)"
    assert rowsdoc.pass_at(d, 87) is None and rowsdoc.pass_at(d, 0) is None


def test_open_ended_last_entry():
    entries = [
        {"label": "1.", "from": 1, "to": 1, "count": 6, "text": "ch 7, 6 sc"},
        {"label": "3.", "from": 2, "repeat": "until desired length", "count": 6, "text": "ch 1, turn, 6 sc"},
    ]
    d = doc(entries)
    assert rowsdoc.validate_rows_document(d) == []
    assert rowsdoc.total_rows(d) is None and rowsdoc.total_stitches(d) is None
    assert rowsdoc.pass_at(d, 57)["label"] == "3. (56)"


def test_a_gap_is_refused_by_row_number():
    entries = [dict(ENTRIES[0]), dict(ENTRIES[2])]
    problems = rowsdoc.validate_rows_document(doc(entries))
    assert any("row 2" in p for p in problems), problems


def test_an_open_entry_that_is_not_last_is_refused():
    entries = [dict(ENTRIES[0], to=None, repeat="until desired length"), dict(ENTRIES[1])]
    entries[0].pop("to")
    assert any("only the last" in p for p in rowsdoc.validate_rows_document(doc(entries)))


def test_an_entry_without_to_or_repeat_is_refused():
    entries = [dict(ENTRIES[0])]
    entries[0].pop("to")
    assert any("no `to`" in p for p in rowsdoc.validate_rows_document(doc(entries)))


def test_an_unknown_code_is_refused():
    entries = [dict(ENTRIES[0], code="Z")]
    assert any("'Z'" in p for p in rowsdoc.validate_rows_document(doc(entries)))


def test_a_wrong_id_is_refused():
    d = doc()
    d["id"] = "sha256:" + "0" * 64
    assert any("id" in p for p in rowsdoc.validate_rows_document(d))


def test_counts_are_optional_and_withhold_stitches():
    entries = [dict(ENTRIES[0]), dict(ENTRIES[1])]
    entries[1].pop("count")
    d = doc(entries)
    assert rowsdoc.validate_rows_document(d) == []
    assert rowsdoc.total_stitches(d) is None and rowsdoc.stitches_before(d, 3) is None
