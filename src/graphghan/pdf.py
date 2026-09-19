"""PDF export: a chart laid out the way patterns are sold (spec §4 of
docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md).

Pages: cover (title, dedication, quote, preview, materials, instructions), key, an overview when
the chart needs more than one tile, the chart tiled at a readable cell size, then the written
rows. Every string is real text; only the preview and the overview are images.

Three text grammars are read back by the importer and must not drift: `KEY_ROW`,
`CHART_HEADER` and `DIRECTION` below, plus the `export.written_rows` lines. Text extraction
collapses runs of spaces, so a key row is parsed off its `#rrggbb`, which cannot occur in a
name; the double spaces are for the eye. Output is
byte-reproducible (`invariant=1`, no dates, no package version) so committed fixture PDFs can
be drift-checked like `fixtures/chart-format/`.
"""

from __future__ import annotations

import io
import math

from reportlab.lib.pagesizes import letter
from reportlab.lib.utils import ImageReader, simpleSplit
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

from .chartdoc import cell_kind, finished_size
from .export import decode_rows, preview_image, rle_rows, written_rows
from .text import FONT_METAMORPHOUS

PAGE_W, PAGE_H = letter
MARGIN = 36.0
FOOTER = 12.0  # space above the bottom margin kept for the running footer
CELL_W = 10.0  # points per column on a chart tile; rows follow the gauge proportion
GUTTER = 22.0  # row-number gutter either side of a tile
NUMBER_BAND = 10.0  # column numbers above and below a tile
TILE_HEADER = 32.0

BODY = "Helvetica"
BOLD = "Helvetica-Bold"
ITALIC = "Helvetica-Oblique"
TITLE_FONT = "Metamorphous"

KEY_ROW = "{code}  {name}  {hex}  {yarn}"
CHART_HEADER = "Chart {k} of {n}: columns {a}-{b} of {W}, rows {c}-{d} of {H}"
DIRECTION = "Row 1 starts at the bottom right; odd rows are RS and read right to left."
KEY_TITLE = "Key"
ROWS_TITLE = "Written rows"


def _rgb(hex_str: str) -> tuple[float, float, float]:
    return tuple(int(hex_str[i : i + 2], 16) / 255 for i in (1, 3, 5))


def _num(v) -> str:
    return f"{float(v):g}"


def _yarn_text(entry: dict) -> str:
    yarn = entry.get("yarn") or {}
    parts = [yarn[k] for k in ("brand", "line", "colorway", "weight") if yarn.get(k)]
    if yarn.get("note"):
        parts.append(yarn["note"])
    return " ".join(parts)


def _register_fonts() -> None:
    if TITLE_FONT not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(TTFont(TITLE_FONT, str(FONT_METAMORPHOUS)))


class _Writer:
    """A top-down text cursor over the canvas with wrapping, page breaks and a running footer."""

    def __init__(self, c: canvas.Canvas, title: str):
        self.c = c
        self.title = title
        self.page_no = 0
        self.y = PAGE_H - MARGIN
        self._open = False
        self.new_page()

    def _footer(self) -> None:
        self.c.setFont(BODY, 7)
        self.c.setFillGray(0.35)
        self.c.drawString(MARGIN, MARGIN / 2, self.title)
        self.c.drawRightString(PAGE_W - MARGIN, MARGIN / 2, f"Page {self.page_no}")
        self.c.setFillGray(0)

    def new_page(self) -> None:
        if self._open:
            self._footer()
            self.c.showPage()
        self.page_no += 1
        self._open = True
        self.y = PAGE_H - MARGIN

    def finish(self) -> None:
        self._footer()
        self.c.showPage()
        self._open = False

    @property
    def bottom(self) -> float:
        return MARGIN + FOOTER

    def need(self, h: float) -> None:
        if self.y - h < self.bottom:
            self.new_page()

    def space(self, h: float) -> None:
        self.y -= h

    def text(
        self, s: str, font: str = BODY, size: float = 10, leading: float | None = None, x: float = MARGIN
    ):
        leading = leading or size * 1.3
        width = PAGE_W - MARGIN - x
        for line in simpleSplit(s, font, size, width) or [""]:
            self.need(leading)
            self.c.setFont(font, size)
            self.c.drawString(x, self.y - size, line)
            self.y -= leading

    def heading(self, s: str, size: float = 13) -> None:
        self.need(size * 2.2)
        self.space(size * 0.6)
        self.text(s, BOLD, size)
        self.space(2)


def _cover(w: _Writer, doc: dict, a, rgb) -> None:
    c = w.c
    p, g, chart = doc["pattern"], doc["gauge"], doc["chart"]
    w.text(p.get("title", ""), TITLE_FONT, 26, leading=32)
    if p.get("dedication"):
        w.text(p["dedication"], ITALIC, 12)
    if p.get("quote"):
        w.text('"' + p["quote"] + '"', ITALIC, 11)
    meta = [p.get("author", ""), p.get("license", ""), f"version {p['version']}" if p.get("version") else ""]
    w.text(" - ".join(m for m in meta if m), BODY, 9)
    w.space(8)

    img = preview_image(a, rgb, cw=4)
    max_w, max_h = PAGE_W - 2 * MARGIN, 250.0
    scale = min(max_w / img.width, max_h / img.height)
    iw, ih = img.width * scale, img.height * scale
    w.need(ih + 10)
    c.drawImage(ImageReader(img), MARGIN, w.y - ih, width=iw, height=ih)
    w.space(ih + 10)

    w.heading("Materials")
    if g.get("yarn_weight"):
        w.text(f"Yarn: {g['yarn_weight']}")
    if g.get("hook"):
        w.text(f"Hook: {g['hook']}")
    over = g.get("over", {})
    gauge = f"Gauge: {_num(g['stitches'])} sts and {_num(g['rows'])} rows = {_num(over.get('value', 4))} {over.get('unit', 'in')}"
    detail = [g.get("stitch_name") or g.get("stitch") or "", f"{g['terms']} terms" if g.get("terms") else ""]
    detail = [d for d in detail if d]
    if detail:
        gauge += f" ({', '.join(detail)})"
    w.text(gauge)
    size = finished_size(doc)
    if size:
        w.text(f"Finished size: {_num(size[0])} x {_num(size[1])} {size[2]}")
    w.text(f"Chart: {chart['width']} columns x {chart['height']} rows")
    if cell_kind(doc) == "stitch":
        w.text(f"Stitches: {chart['width'] * chart['height']:,}")
    foundation = doc.get("foundation")
    if isinstance(foundation, dict) and "chain" in foundation:
        line = f"Foundation: chain {foundation['chain']}"
        if foundation.get("first_stitch_in"):
            line += f", first stitch in chain {foundation['first_stitch_in']} from the hook"
        if foundation.get("note"):
            line += f", {foundation['note']}"
        w.text(line)

    w.heading("Colours")
    yards = (doc.get("stats") or {}).get("yards_est") or {}
    for entry in doc["palette"]:
        line = f"{entry['code']}  {entry['name']}"
        yarn = _yarn_text(entry)
        if yarn:
            line += f": {yarn}"
        if entry.get("use"):
            line += f" ({entry['use']})"
        if entry["code"] in yards:
            line += f", about {yards[entry['code']]:,} yd"
        w.text(line)

    for section in doc.get("instructions") or []:
        w.heading(section.get("title", ""), 12)
        for para in str(section.get("text", "")).split("\n"):
            if para.strip():
                w.text(para)


def _key(w: _Writer, doc: dict) -> None:
    c = w.c
    w.new_page()
    w.text(KEY_TITLE, BOLD, 14)
    w.space(6)
    for entry in doc["palette"]:
        w.need(30)
        c.setFillColorRGB(*_rgb(entry["hex"]))
        c.setStrokeGray(0)
        c.setLineWidth(0.5)
        c.rect(MARGIN, w.y - 13, 13, 13, stroke=1, fill=1)
        c.setFillGray(0)
        c.setFont(BODY, 10)
        row = KEY_ROW.format(
            code=entry["code"], name=entry["name"], hex=entry["hex"], yarn=_yarn_text(entry)
        ).rstrip()
        c.drawString(MARGIN + 20, w.y - 11, row)
        w.space(15)
        if entry.get("use"):
            c.setFont(BODY, 8)
            c.setFillGray(0.35)
            c.drawString(MARGIN + 20, w.y - 8, entry["use"])
            c.setFillGray(0)
            w.space(12)
        w.space(4)


class _Tiling:
    """How the chart splits across pages: balanced tiles, working order (bottom right first)."""

    def __init__(self, doc: dict, n_colors: int):
        g = doc["gauge"]
        self.W, self.H = doc["chart"]["width"], doc["chart"]["height"]
        self.cell_h = CELL_W * float(g["stitches"]) / float(g["rows"])
        self.key_lines = math.ceil(n_colors / 4)
        self.key_strip = 10.0 * self.key_lines + 8
        usable_w = PAGE_W - 2 * MARGIN - 2 * GUTTER
        usable_h = PAGE_H - MARGIN - FOOTER - MARGIN - TILE_HEADER - 2 * NUMBER_BAND - self.key_strip
        max_cols = max(1, int(usable_w // CELL_W))
        max_rows = max(1, int(usable_h // self.cell_h))
        self.nx = math.ceil(self.W / max_cols)
        self.ny = math.ceil(self.H / max_rows)
        self.cols_per = math.ceil(self.W / self.nx)
        self.rows_per = math.ceil(self.H / self.ny)

    def tiles(self) -> list[tuple[int, int, int, int]]:
        """(a, b, c, d): chart columns a..b and rows c..d, 1-based, in working order."""
        out = []
        for ty in range(self.ny):
            c0, c1 = ty * self.rows_per + 1, min((ty + 1) * self.rows_per, self.H)
            for tx in range(self.nx):
                a0, a1 = tx * self.cols_per + 1, min((tx + 1) * self.cols_per, self.W)
                out.append((a0, a1, c0, c1))
        return out

    def grid_box(self, a: int, b: int, c: int, d: int) -> tuple[int, int, int, int]:
        """Grid indexes (x0, x1, y0, y1), half-open, for chart columns a..b and rows c..d."""
        return self.W - b, self.W - a + 1, self.H - d, self.H - c + 1


def _draw_runs(c: canvas.Canvas, sub, rgb, left: float, top: float, cw: float, ch: float) -> None:
    for j, row in enumerate(rle_rows(sub)):
        x = left
        y = top - (j + 1) * ch
        for color, n in row:
            c.setFillColorRGB(*[v / 255 for v in rgb[color]])
            c.rect(x, y, n * cw, ch, stroke=0, fill=1)
            x += n * cw


def _overview(w: _Writer, doc: dict, a, rgb, tiling: _Tiling) -> None:
    c = w.c
    w.new_page()
    w.text("Overview", BOLD, 14)
    w.text(f"The chart on the following pages, {tiling.nx} pages wide and {tiling.ny} tall.", BODY, 9)
    w.space(8)
    max_w = PAGE_W - 2 * MARGIN
    max_h = w.y - w.bottom - 4
    ratio = tiling.cell_h / CELL_W
    cw = min(max_w / tiling.W, max_h / (tiling.H * ratio))
    ch = cw * ratio
    left, top = MARGIN, w.y
    _draw_runs(c, a, rgb, left, top, cw, ch)
    c.setStrokeGray(0)
    c.setLineWidth(0.8)
    c.setFont(BOLD, 8)
    for k, (a0, b0, c0, d0) in enumerate(tiling.tiles(), start=1):
        x0, x1, y0, y1 = tiling.grid_box(a0, b0, c0, d0)
        bx, by = left + x0 * cw, top - y1 * ch
        bw, bh = (x1 - x0) * cw, (y1 - y0) * ch
        c.rect(bx, by, bw, bh, stroke=1, fill=0)
        label = f"Chart {k}"
        tw = pdfmetrics.stringWidth(label, BOLD, 8) + 6
        c.setFillColorRGB(1, 1, 1)
        c.rect(bx + bw / 2 - tw / 2, by + bh / 2 - 6, tw, 12, stroke=1, fill=1)
        c.setFillGray(0)
        c.drawCentredString(bx + bw / 2, by + bh / 2 - 3, label)


def _tile(w: _Writer, doc: dict, a, rgb, tiling: _Tiling, k: int, n: int, span) -> None:
    c = w.c
    a0, b0, c0, d0 = span
    x0, x1, y0, y1 = tiling.grid_box(a0, b0, c0, d0)
    ncols, nrows = x1 - x0, y1 - y0
    cw, ch = CELL_W, tiling.cell_h
    w.new_page()
    c.setFont(BOLD, 11)
    c.drawString(
        MARGIN,
        PAGE_H - MARGIN - 11,
        CHART_HEADER.format(k=k, n=n, a=a0, b=b0, W=tiling.W, c=c0, d=d0, H=tiling.H),
    )
    if k == 1:
        c.setFont(BODY, 8)
        c.drawString(MARGIN, PAGE_H - MARGIN - 24, DIRECTION)
    left = MARGIN + GUTTER
    top = PAGE_H - MARGIN - TILE_HEADER - NUMBER_BAND
    _draw_runs(c, a[y0:y1, x0:x1], rgb, left, top, cw, ch)
    bottom = top - nrows * ch
    right = left + ncols * cw
    # Grid lines: bold every 10 counted from column 1 (right edge) and row 1 (bottom edge), so
    # the bold lines land on the same multiples on every page.
    for i in range(ncols + 1):
        col_from_right = tiling.W - (x0 + i)
        bold = col_from_right % 10 == 0
        c.setStrokeGray(0 if bold else 0.55)
        c.setLineWidth(0.9 if bold else 0.3)
        c.line(left + i * cw, bottom, left + i * cw, top)
    for j in range(nrows + 1):
        row_from_bottom = tiling.H - (y0 + j)
        bold = row_from_bottom % 10 == 0
        c.setStrokeGray(0 if bold else 0.55)
        c.setLineWidth(0.9 if bold else 0.3)
        c.line(left, top - j * ch, right, top - j * ch)
    c.setStrokeGray(0)
    c.setLineWidth(0.9)
    c.rect(left, bottom, ncols * cw, nrows * ch, stroke=1, fill=0)
    # Numbers: columns 1 at the right; odd rows on the right, even on the left.
    c.setFillGray(0)
    c.setFont(BODY, 5)
    for i in range(ncols):
        label = str(tiling.W - (x0 + i))
        cx = left + (i + 0.5) * cw
        c.drawCentredString(cx, top + 3, label)
        c.drawCentredString(cx, bottom - 7, label)
    for j in range(nrows):
        row_no = tiling.H - (y0 + j)
        cy = top - (j + 0.5) * ch - 1.8
        if row_no % 2 == 1:
            c.drawString(right + 4, cy, str(row_no))
        else:
            c.drawRightString(left - 4, cy, str(row_no))
    # Key strip, under the bottom column numbers.
    ky = bottom - NUMBER_BAND - 12
    col_w = (PAGE_W - 2 * MARGIN) / 4
    c.setFont(BODY, 7)
    for idx, entry in enumerate(doc["palette"]):
        kx = MARGIN + (idx % 4) * col_w
        kyy = ky - (idx // 4) * 10
        c.setFillColorRGB(*_rgb(entry["hex"]))
        c.setLineWidth(0.4)
        c.rect(kx, kyy - 1, 7, 7, stroke=1, fill=1)
        c.setFillGray(0)
        c.drawString(kx + 10, kyy, f"{entry['code']}  {entry['name']}")


def _rows(w: _Writer, doc: dict, a, codes: list[str]) -> None:
    c = w.c
    w.new_page()
    w.text(ROWS_TITLE, BOLD, 14)
    w.space(6)
    lines = written_rows(a, codes, boundary=doc["gauge"].get("boundary"))
    size, leading = 8, 10.5
    col_w = (PAGE_W - 2 * MARGIN - 14) / 2
    top = w.y
    col, y = 0, top
    c.setFont(BODY, size)
    for line in lines:
        wrapped = simpleSplit(line, BODY, size, col_w)
        needed = leading * len(wrapped)
        if y - needed < w.bottom:
            if col == 0:
                col, y = 1, top
            else:
                w.new_page()
                c.setFont(BODY, size)
                col, y, top = 0, w.y, w.y
        x = MARGIN + col * (col_w + 14)
        for i, part in enumerate(wrapped):
            c.drawString(x + (10 if i else 0), y - size, part)
            y -= leading
    w.y = w.bottom  # the cursor is no longer meaningful; force the next section onto a new page


def to_pdf(doc: dict) -> bytes:
    """A printable pattern for a schema 2 chart document, as PDF bytes. Deterministic."""
    technique = doc.get("technique") or {}
    if technique.get("type") != "rows":
        raise ValueError("PDF export lays out row-worked charts only (technique.type must be 'rows')")
    _register_fonts()
    codes = [p["code"] for p in doc["palette"]]
    rgb = [tuple(int(p["hex"][i : i + 2], 16) for i in (1, 3, 5)) for p in doc["palette"]]
    a = decode_rows(doc["rows"], codes)
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=letter, invariant=1, pageCompression=1)
    p = doc["pattern"]
    c.setTitle(p.get("title", ""))
    c.setAuthor(p.get("author", ""))
    c.setSubject(f"{p.get('id', '')} {doc['chart'].get('id', '')}".strip())
    c.setCreator("graphghan")
    w = _Writer(c, p.get("title", ""))
    _cover(w, doc, a, rgb)
    _key(w, doc)
    tiling = _Tiling(doc, len(codes))
    spans = tiling.tiles()
    if len(spans) > 1:
        _overview(w, doc, a, rgb, tiling)
    for k, span in enumerate(spans, start=1):
        _tile(w, doc, a, rgb, tiling, k, len(spans), span)
    _rows(w, doc, a, codes)
    w.finish()
    c.save()
    return buf.getvalue()
