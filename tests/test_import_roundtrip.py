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
    result = import_file(FIX / f"{slug}-{key}.pdf")
    assert result.kind == "graphghan-pdf", result.kind
    fresh = {"rows": result.rows, "palette": [{"hex": h} for h in result.hexes]}
    committed = {"rows": doc["rows"], "palette": [{"hex": p["hex"]} for p in doc["palette"]]}
    assert drift_message(committed, fresh) is None
    assert result.warnings == []
