"""A graphghan-made PDF reads its own prose (spec §6.4): the text layer is in the grammars
`graphghan/pdf.py` fixes, so the model's job is done here by regular expressions, producing the
same `prose.json` document (schema `graphghan-import/1`) the skill would. Everything downstream,
the assembler and the cross-check, is exercised the same way.
"""

from __future__ import annotations

import re
from pathlib import Path

import pypdfium2 as pdfium

from .importers import HEADER_RE, KEY_RE, page_texts
from .pdf import KEY_TITLE, ROWS_TITLE
from .prose import SCHEMA_ID

META_RE = re.compile(r"^(?:(?P<author>.+?) - )?(?:(?P<license>[A-Za-z0-9.+-]+) - )?version (?P<version>\S+)$")
GAUGE_RE = re.compile(
    r"^Gauge: (?P<st>[\d.]+) sts and (?P<rows>[\d.]+) rows = (?P<value>[\d.]+) (?P<unit>in|cm)(?: \((?P<detail>.*)\))?$"
)
SIZE_RE = re.compile(r"^Finished size: (?P<w>[\d.]+) x (?P<h>[\d.]+) (?P<unit>in|cm)$")
ROW_RE = re.compile(
    r"^Row (?P<row>\d+) \((?P<side>RS|WS)\): (?:ch (?P<chain>\d+), turn, |turn, )?(?P<runs>.*?) ?\((?P<total>\d+) sts\)$"
)
RUN_RE = re.compile(r"^(\d+) ([A-Za-z]{1,3})$")


def _num(s: str) -> float | int:
    f = float(s)
    return int(f) if f.is_integer() else f


def _cover(text: str, title: str) -> tuple[dict, dict, dict | None]:
    """pattern, gauge and finished_size from the cover page's text."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    pattern: dict = {"title": title}
    gauge: dict = {}
    size = None
    i = 1 if lines and lines[0] == title else 0
    # dedication, quote and the author line sit between the title and the Materials heading
    while i < len(lines) and lines[i] != "Materials":
        ln = lines[i]
        m = META_RE.match(ln)
        if m and (m.group("author") or m.group("license") or "version" in ln):
            if m.group("author"):
                pattern["author"] = m.group("author")
            if m.group("license"):
                pattern["license"] = m.group("license")
            pattern["version"] = m.group("version")
        elif ln.startswith('"') and ln.endswith('"'):
            pattern["quote"] = ln[1:-1]
        elif "dedication" not in pattern:
            pattern["dedication"] = ln
        i += 1
    for ln in lines[i:]:
        if ln.startswith("Yarn: "):
            gauge["yarn_weight"] = ln[6:]
        elif ln.startswith("Hook: "):
            gauge["hook"] = ln[6:]
        elif ln.startswith("Gauge: "):
            m = GAUGE_RE.match(ln)
            if m:
                gauge.update(
                    stitches=_num(m.group("st")),
                    rows=_num(m.group("rows")),
                    over={"value": _num(m.group("value")), "unit": m.group("unit")},
                )
                detail = [d.strip() for d in (m.group("detail") or "").split(",") if d.strip()]
                for d in detail:
                    if d.endswith(" terms"):
                        pattern["terms"] = d[: -len(" terms")]
                    else:
                        gauge["stitch_name"] = d
        elif ln.startswith("Finished size: "):
            m = SIZE_RE.match(ln)
            if m:
                size = {"width": _num(m.group("w")), "height": _num(m.group("h")), "unit": m.group("unit")}
        elif ln == "Colours":
            break
    return pattern, gauge, size


def _key(texts: list[str]) -> list[dict]:
    out = []
    for text in texts:
        if not text.startswith(KEY_TITLE + "\n"):
            continue
        for line in text.splitlines()[1:]:
            m = KEY_RE.match(line.strip())
            if m:
                entry = {"code": m.group("code"), "name": m.group("name"), "hex": m.group("hex")}
                if m.group("yarn"):
                    entry["yarn"] = {"note": m.group("yarn")}
                out.append(entry)
    return out


def _rows(texts: list[str], title: str) -> tuple[list[dict], dict]:
    """Written rows from the rows pages: wrapped lines rejoined, footers skipped."""
    footer = re.compile(rf"^{re.escape(title)} Page \d+$")
    rows: list[dict] = []
    boundary: dict = {}
    started = False
    for page_no, text in enumerate(texts, start=1):
        lines = [ln.strip() for ln in text.splitlines()]
        if not started:
            if lines and lines[0] == ROWS_TITLE:
                started = True
                lines = lines[1:]
            else:
                continue
        elif not lines or not lines[0].startswith("Row "):
            break  # a page after the rows that is not rows
        joined: list[tuple[int, str]] = []
        for ln in lines:
            if not ln or footer.match(ln):
                continue
            if ln.startswith("Row ") and re.match(r"^Row \d+ \((RS|WS)\):", ln):
                joined.append((page_no, ln))
            elif joined:
                joined[-1] = (joined[-1][0], joined[-1][1] + " " + ln)
        for pg, ln in joined:
            m = ROW_RE.match(ln)
            if not m:
                raise ValueError(f"page {pg}: cannot read written row {ln!r}")
            runs = []
            for part in m.group("runs").split(", "):
                r = RUN_RE.match(part.strip())
                if not r:
                    raise ValueError(f"page {pg}: cannot read run {part!r} in {ln!r}")
                runs.append([r.group(2), int(r.group(1))])
            entry = {
                "row": int(m.group("row")),
                "side": m.group("side"),
                "page": pg,
                "text": ln,
                "runs": runs,
                "total": int(m.group("total")),
            }
            rows.append(entry)
            if m.group("chain") is not None and not boundary:
                boundary = {"kind": "turn", "chain": int(m.group("chain"))}
    return rows, boundary


def prose_from_own_pdf(pdf_path: str | Path) -> dict:
    """The prose document a graphghan-made PDF describes."""
    texts = page_texts(pdf_path)
    title = pdfium.PdfDocument(str(pdf_path)).get_metadata_value("Title") or ""
    pattern, gauge, size = _cover(texts[0], title)
    palette = _key(texts)
    pages = []
    width = height = None
    for page_no, text in enumerate(texts, start=1):
        m = HEADER_RE.match(text)
        if m:
            a, b, c, d = (int(m.group(g)) for g in ("a", "b", "c", "d"))
            width, height = int(m.group("W")), int(m.group("H"))
            pages.append({"page": page_no, "region": 1, "cols": [a, b], "rows": [c, d]})
    rows, boundary = _rows(texts, title)
    if boundary:
        gauge["boundary"] = boundary
    doc: dict = {"schema": SCHEMA_ID, "pattern": pattern}
    if gauge:
        doc["gauge"] = gauge
    if size:
        doc["finished_size"] = size
    if palette:
        doc["palette"] = palette
    chart: dict = {"row1": "bottom-right"}
    if pages:
        chart.update(pages=pages, width=width, height=height)
    doc["chart"] = chart
    if rows:
        doc["written_rows"] = rows
    return doc
