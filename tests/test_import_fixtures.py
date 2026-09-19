"""fixtures/import/*.pdf must equal a fresh export of the committed charts they stand for."""

import json
from pathlib import Path

from graphghan.pdf import to_pdf
from graphghan.publish import committed_charts

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "import"


def test_every_committed_chart_has_a_matching_fixture():
    charts = committed_charts(ROOT)
    assert charts, "no committed charts under patterns/*/dist/charts"
    expected = set()
    for slug, key, path in charts:
        fixture = FIX / f"{slug}-{key}.pdf"
        expected.add(fixture.name)
        assert fixture.exists(), f"missing {fixture.name}; run uv run python fixtures/import/generate.py"
        fresh = to_pdf(json.loads(path.read_text(encoding="utf-8")))
        assert fixture.read_bytes() == fresh, f"{fixture.name} differs from a fresh export; regenerate it"
    assert {p.name for p in FIX.glob("*.pdf")} == expected, "stale fixture PDF with no committed chart"
