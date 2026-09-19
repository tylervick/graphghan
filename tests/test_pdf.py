import json
import re
from pathlib import Path

import numpy as np
import pypdfium2 as pdfium
import pytest

from graphghan import pdf as pdfx
from graphghan.export import decode_rows
from graphghan.pdf import DIRECTION, to_pdf

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "chart-format"

HEADER_RE = re.compile(r"Chart (\d+) of (\d+): columns (\d+)-(\d+) of (\d+), rows (\d+)-(\d+) of (\d+)")


def load(name):
    return json.loads((FIX / f"{name}.chart.json").read_text(encoding="utf-8"))


def pages_text(data: bytes) -> list[str]:
    pdf = pdfium.PdfDocument(data)
    return [pdf[i].get_textpage().get_text_range().replace("\r\n", "\n") for i in range(len(pdf))]


@pytest.fixture(scope="module")
def craigh():
    doc = load("craigh-na-dun")
    return doc, to_pdf(doc)


def test_bytes_are_deterministic_and_small(craigh):
    doc, data = craigh
    assert data == to_pdf(doc)
    assert data.startswith(b"%PDF-") and len(data) < 1_000_000


def test_creator_marks_our_own_layout(craigh):
    _, data = craigh
    assert pdfium.PdfDocument(data).get_metadata_value("Creator") == "graphghan"


def test_cover_carries_the_pattern_metadata(craigh):
    _, data = craigh
    cover = pages_text(data)[0]
    assert "Craigh na Dun Blanket" in cover and "For Meaghan" in cover
    assert "Gauge: 14 sts and 16 rows = 4 in (single crochet, US terms)" in cover
    assert "Finished size: 54 x 46 in" in cover and "Stitches: 34,776" in cover
    assert "Foundation: chain 190, first stitch in chain 2 from the hook, in Gold (Y)" in cover


def test_key_rows_parse_off_the_hex(craigh):
    doc, data = craigh
    key = next(t for t in pages_text(data) if t.startswith(pdfx.KEY_TITLE))
    for entry in doc["palette"]:
        pattern = rf"^{entry['code']}\s+{re.escape(entry['name'])}\s+{entry['hex']}\s+{re.escape(entry['yarn']['note'])}$"
        assert re.search(pattern, key, re.M), (entry["code"], key)


def test_tiles_cover_the_chart_exactly_once(craigh):
    doc, data = craigh
    texts = pages_text(data)
    W, H = doc["chart"]["width"], doc["chart"]["height"]
    headers = [(HEADER_RE.match(t), t) for t in texts]
    headers = [(m, t) for m, t in headers if m]
    ks = [int(m.group(1)) for m, _ in headers]
    assert ks == list(range(1, len(ks) + 1)) and all(int(m.group(2)) == len(ks) for m, _ in headers)
    covered = np.zeros((H, W), dtype=int)
    for m, _ in headers:
        a, b, w, c, d, h = (int(m.group(i)) for i in range(3, 9))
        assert (w, h) == (W, H)
        covered[c - 1 : d, a - 1 : b] += 1
    assert covered.min() == 1 and covered.max() == 1
    assert DIRECTION in headers[0][1] and all(DIRECTION not in t for _, t in headers[1:])
    assert len(ks) == 12  # 189 x 184 at sc: 4 pages wide, 3 tall


def test_tile_cells_are_where_the_geometry_says(craigh):
    doc, data = craigh
    pdf = pdfium.PdfDocument(data)
    page_index = next(i for i in range(len(pdf)) if HEADER_RE.match(pdf[i].get_textpage().get_text_range()))
    scale = 3
    px = np.asarray(pdf[page_index].render(scale=scale).to_pil().convert("RGB"))
    codes = [p["code"] for p in doc["palette"]]
    rgb = [tuple(int(p["hex"][i : i + 2], 16) for i in (1, 3, 5)) for p in doc["palette"]]
    a = decode_rows(doc["rows"], codes)
    tiling = pdfx._Tiling(doc, len(codes))
    a0, b0, c0, d0 = tiling.tiles()[0]
    x0, x1, y0, y1 = tiling.grid_box(a0, b0, c0, d0)
    left = pdfx.MARGIN + pdfx.GUTTER
    top = pdfx.PAGE_H - pdfx.MARGIN - pdfx.TILE_HEADER - pdfx.NUMBER_BAND
    for i, j in ((0, 0), (x1 - x0 - 1, y1 - y0 - 1), (10, 30), (25, 45)):
        cx = (left + (i + 0.5) * pdfx.CELL_W) * scale
        cy = (pdfx.PAGE_H - (top - (j + 0.5) * tiling.cell_h)) * scale
        got = tuple(int(v) for v in px[int(cy), int(cx)])
        want = rgb[a[y0 + j, x0 + i]]
        assert max(abs(g - w) for g, w in zip(got, want, strict=True)) <= 6, (i, j, got, want)


def test_written_rows_are_the_export_lines(craigh):
    doc, data = craigh
    texts = pages_text(data)
    start = next(i for i, t in enumerate(texts) if t.startswith(pdfx.ROWS_TITLE))
    joined = "\n".join(texts[start:])
    assert "Row 1 (RS): 189 Y (189 sts)" in joined
    assert "Row 2 (WS): ch 1, turn, 189 Y (189 sts)" in joined
    assert f"Row {doc['chart']['height']} (WS):" in joined


def test_document_without_optional_keys_exports():
    doc = load("minimal-rows")
    for key in ("foundation", "instructions", "stats", "ext"):
        doc.pop(key, None)
    for key in ("dedication", "quote", "author", "license"):
        doc["pattern"].pop(key, None)
    for key in ("boundary", "hook", "yarn_weight", "stitch_name", "terms"):
        doc["gauge"].pop(key, None)
    data = to_pdf(doc)
    assert data.startswith(b"%PDF-")
    assert HEADER_RE.search("\n".join(pages_text(data)))


def test_tile_cell_kind_prints_no_stitch_count():
    doc = load("tiles-gauge")
    cover = pages_text(to_pdf(doc))[0]
    assert "Stitches:" not in cover and "Chart: " in cover


def test_refuses_rounds():
    with pytest.raises(ValueError, match="rows"):
        to_pdf(load("minimal-rounds"))
