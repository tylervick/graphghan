"""Every PDF in fixtures/import/ imports back to the chart it was exported from: zero drift."""

import json
from pathlib import Path

import pytest

from graphghan.importers import import_file
from graphghan.publish import committed_charts, drift_message

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "import"


@pytest.mark.parametrize(
    "slug,key,path", committed_charts(ROOT), ids=lambda v: v if isinstance(v, str) else ""
)
def test_pdf_round_trips_to_the_committed_chart(slug, key, path):
    doc = json.loads(path.read_text(encoding="utf-8"))
    result = import_file(FIX / f"{slug}-{key}.pdf", rows_source="grid")
    assert result.kind == "graphghan-pdf", result.kind
    fresh = {"rows": result.rows, "palette": [{"hex": h} for h in result.hexes]}
    committed = {"rows": doc["rows"], "palette": [{"hex": p["hex"]} for p in doc["palette"]]}
    assert drift_message(committed, fresh) is None
    assert result.warnings == []


@pytest.mark.parametrize(
    "slug,key,path", committed_charts(ROOT), ids=lambda v: v if isinstance(v, str) else ""
)
def test_pdf_round_trips_through_its_written_rows(slug, key, path):
    """The prose path (spec §6.4): our own PDF reads its written rows, they become the chart, and
    the grid cross-check finds nothing to say."""
    doc = json.loads(path.read_text(encoding="utf-8"))
    result = import_file(FIX / f"{slug}-{key}.pdf", rows_source="written")
    assert result.kind == "graphghan-pdf+rows"
    assert result.rows == doc["rows"] and result.hexes == [p["hex"] for p in doc["palette"]]
    assert result.meta["cross_check"] == f"{doc['chart']['height']} written rows, 0 disagree with the chart"
    assert [w for w in result.warnings if "against the chart" in w] == []
    assert result.meta["title"] == doc["pattern"]["title"] and result.meta["hook"] == doc["gauge"]["hook"]
