import json
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
import pytest

from graphghan import exporters
from graphghan.export import decode_rows

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "chart-format"


def load(name):
    return json.loads((FIX / f"{name}.chart.json").read_text(encoding="utf-8"))


def grid(doc):
    return decode_rows(doc["rows"], [p["code"] for p in doc["palette"]])


@pytest.mark.parametrize("name", ["two-letter-codes", "craigh-na-dun"])
def test_png_round_trip(name):
    doc = load(name)
    img = exporters.to_png(doc)
    assert img.size == (doc["chart"]["width"], doc["chart"]["height"]) and img.mode == "RGB"
    assert np.array_equal(exporters.read_png(img, doc["palette"]), grid(doc))


def test_png_requires_distinct_colors():
    doc = load("two-letter-codes")
    doc["palette"][1]["hex"] = doc["palette"][0]["hex"]
    with pytest.raises(ValueError):
        exporters.to_png(doc)


def test_read_png_rejects_foreign_color():
    doc = load("two-letter-codes")
    img = exporters.to_png(doc)
    img.putpixel((0, 0), (1, 2, 3))
    with pytest.raises(ValueError):
        exporters.read_png(img, doc["palette"])


@pytest.mark.parametrize("name", ["two-letter-codes", "craigh-na-dun"])
def test_csv_round_trip(name):
    doc = load(name)
    text = exporters.to_csv(doc)
    lines = text.splitlines()
    assert len(lines) == doc["chart"]["height"] and lines[0].count(",") == doc["chart"]["width"] - 1
    assert lines[0].startswith("Gd,Gd,Gd,Gd,Gd,Gd,Gd,G,G,Y") if name == "two-letter-codes" else True
    assert np.array_equal(exporters.read_csv(text, doc["palette"]), grid(doc))


def test_read_csv_names_the_bad_cell():
    doc = load("two-letter-codes")
    text = exporters.to_csv(doc).replace("Y", "Q", 1)  # row 0, column 9
    with pytest.raises(ValueError, match=r"row 0 column 9: unknown code 'Q'"):
        exporters.read_csv(text, doc["palette"])


@pytest.mark.parametrize("name", ["two-letter-codes", "craigh-na-dun"])
def test_oxs_round_trip(name):
    doc = load(name)
    text = exporters.to_oxs(doc)
    names, a = exporters.read_oxs(text)
    assert names == [p["name"] for p in doc["palette"]]
    assert np.array_equal(a, grid(doc))


def test_oxs_structure():
    doc = load("two-letter-codes")
    doc["palette"][1]["thread"] = {"system": "DMC", "number": "783"}
    root = ET.fromstring(exporters.to_oxs(doc))
    assert root.tag == "chart" and [c.tag for c in root] == [
        "format",
        "properties",
        "palette",
        "fullstitches",
        "partstitches",
        "backstitches",
        "ornaments_inc_knots_and_beads",
        "commentboxes",
    ]
    props = root.find("properties").attrib
    assert (
        props["chartwidth"] == "12"
        and props["chartheight"] == "2"
        and props["charttitle"] == "Two-letter codes"
    )
    assert (
        props["stitchesperinch"] == "3.5"
        and props["stitchesperinch_y"] == "4"
        and props["palettecount"] == "5"
    )
    items = list(root.find("palette"))
    assert items[0].attrib["index"] == "0" and items[0].attrib["number"] == "cloth"
    assert items[1].attrib == {
        "index": "1",
        "number": "G",
        "name": "Color G",
        "color": "1E4D3A",
        "symbol": "G",
        "strands": "2",
    }
    assert items[2].attrib["number"] == "DMC 783"
    stitches = list(root.find("fullstitches"))
    assert len(stitches) == 24 and stitches[0].attrib == {
        "x": "0",
        "y": "0",
        "palindex": "2",
    }  # top-left is Gd


def test_oxs_gauge_in_cm():
    doc = load("two-letter-codes")
    doc["gauge"] = {"stitches": 10, "rows": 10, "over": {"value": 10, "unit": "cm"}}
    props = ET.fromstring(exporters.to_oxs(doc)).find("properties").attrib
    assert props["stitchesperinch"] == "2.54" and props["stitchesperinch_y"] == "2.54"
