"""A graphghan-made PDF reads its own prose into a valid prose.json (spec §6.4)."""

import json
from pathlib import Path

import jsonschema
import pytest

from graphghan import prose
from graphghan.pdfself import prose_from_own_pdf
from graphghan.publish import committed_charts

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "schema" / "import-prose.schema.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "slug,key,path", committed_charts(ROOT), ids=lambda v: v if isinstance(v, str) else ""
)
def test_own_pdf_reads_itself(slug, key, path):
    chart = json.loads(path.read_text(encoding="utf-8"))
    doc = prose_from_own_pdf(ROOT / "fixtures" / "import" / f"{slug}-{key}.pdf")
    jsonschema.validate(doc, SCHEMA)
    assert prose.check_prose(doc) == []
    p, g = chart["pattern"], chart["gauge"]
    assert doc["pattern"]["title"] == p["title"]
    assert doc["pattern"].get("dedication", "") == p.get("dedication", "")
    assert doc["pattern"].get("quote", "") == p.get("quote", "")
    assert doc["pattern"].get("author", "") == p.get("author", "")
    assert doc["gauge"]["stitches"] == g["stitches"] and doc["gauge"]["rows"] == g["rows"]
    assert doc["gauge"]["over"] == g["over"] and doc["gauge"]["hook"] == g["hook"]
    assert doc["gauge"].get("stitch_name") == g.get("stitch_name")
    if g.get("boundary"):
        assert doc["gauge"]["boundary"]["chain"] == g["boundary"]["chain"]
    assert [(e["code"], e["name"], e["hex"]) for e in doc["palette"]] == [
        (e["code"], e["name"], e["hex"]) for e in chart["palette"]
    ]
    assert (
        doc["chart"]["width"] == chart["chart"]["width"]
        and doc["chart"]["height"] == chart["chart"]["height"]
    )
    rows = doc["written_rows"]
    assert [r["row"] for r in rows] == list(range(1, chart["chart"]["height"] + 1))
    assert all(r["total"] == chart["chart"]["width"] for r in rows)
    assert prose.row_total_problems(rows, chart["chart"]["width"]) == []
    assert prose.meta_from_prose(doc)["gauge"] == (g["stitches"] / 4, g["rows"] / 4)
