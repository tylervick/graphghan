"""Importers: OXS, CSV, PNG (one pixel per cell, or a picture of a chart) and the chart pages of a
PDF into a pattern folder (spec §5 of docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md).

`import_file` reads any of them into an `ImportResult` (a grid of palette indexes plus the
palette) without touching the disk; `write_pattern` validates it and writes the folder. A PDF
that this package wrote (`Creator` = graphghan) is stitched back together from its chart page
headers; any other PDF is read page by page by the raster grid reader and the largest grid wins
unless the caller picks one.
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pypdfium2 as pdfium
from PIL import Image

from . import prose as pr
from . import rasterchart as rc
from .chartdoc import CODE_RE, TECHNIQUE_ROWS, chart_id, validate_document
from .export import chart_png, palette_entries, rows_to_strings
from .exporters import read_csv, read_oxs, read_png
from .palette import Palette
from .pdf import CHART_HEADER, KEY_TITLE

HEADER_RE = re.compile(
    re.escape(CHART_HEADER)
    .replace(r"\{k\}", r"(?P<k>\d+)")
    .replace(r"\{n\}", r"(?P<n>\d+)")
    .replace(r"\{a\}", r"(?P<a>\d+)")
    .replace(r"\{b\}", r"(?P<b>\d+)")
    .replace(r"\{W\}", r"(?P<W>\d+)")
    .replace(r"\{c\}", r"(?P<c>\d+)")
    .replace(r"\{d\}", r"(?P<d>\d+)")
    .replace(r"\{H\}", r"(?P<H>\d+)")
)
KEY_RE = re.compile(r"^(?P<code>[A-Za-z]{1,3}) (?P<name>.+?) (?P<hex>#[0-9a-fA-F]{6})(?: (?P<yarn>.*))?$")
RENDER_SCALE = 4  # 288 dpi: a 10 pt cell is 40 px, a 0.3 pt line is a clean edge
MAX_FILE_BYTES = 200 * 1024 * 1024  # a pattern PDF is a few MB; the Orca bag, all photos, is 18 MB
TEMPLATES = Path(__file__).parent / "templates"


@dataclass
class ImportResult:
    grid: np.ndarray | None  # (height, width) palette indexes; None until the prose supplies them
    palette: list[dict]  # chart-format entries: code, name, hex, yarn, use
    source: str
    kind: str  # oxs | csv | pixels | raster | pdf | graphghan-pdf
    regions: list[str] = field(default_factory=list)  # every grid found, as text, chosen first
    warnings: list[str] = field(default_factory=list)
    meta: dict = field(default_factory=dict)  # title and friends when the source carries them

    @property
    def width(self) -> int:
        return 0 if self.grid is None else int(self.grid.shape[1])

    @property
    def height(self) -> int:
        return 0 if self.grid is None else int(self.grid.shape[0])

    @property
    def codes(self) -> list[str]:
        return [p["code"] for p in self.palette]

    @property
    def rows(self) -> list[str]:
        return [] if self.grid is None else rows_to_strings(self.grid, self.codes)

    @property
    def hexes(self) -> list[str]:
        return [p["hex"] for p in self.palette]


# ---------- helpers ----------


def _entries_from_toml(path: Path) -> list[dict]:
    return palette_entries(Palette.from_toml(path))


def _entries_from_hexes(hexes: list[str], names: list[str] | None = None) -> list[dict]:
    out = []
    for i, hx in enumerate(hexes):
        code = _code(i)
        name = names[i] if names and i < len(names) and names[i] else rc.name_colour(hx)
        out.append({"code": code, "name": name, "hex": hx, "yarn": {}, "use": ""})
    return out


def _code(i: int) -> str:
    """A, B, ..., Z, AA, AB, ...: 1-3 letters, never two that differ only by case."""
    letters = ""
    i += 1
    while i:
        i, r = divmod(i - 1, 26)
        letters = chr(ord("A") + r) + letters
    return letters


def _indexes(samples: np.ndarray, palette: list[dict] | None) -> tuple[np.ndarray, list[dict], list[str]]:
    if palette is not None:
        return rc.snap_to_palette(samples, [p["hex"] for p in palette]), palette, []
    idx, hexes, warnings = rc.cluster_palette(samples)
    return idx, _entries_from_hexes(hexes), warnings


def _oxs_palette(text: str, names: list[str]) -> list[dict]:
    """OXS palette items: `color` (RRGGBB), `name`, and `number`, which graphghan writes as the
    code (a floss system writes "DMC 310" there, so a number that is not a code is not used)."""
    root = ET.fromstring(text)
    items = sorted(
        (int(i.attrib["index"]), i.attrib) for i in root.find("palette") if int(i.attrib["index"]) != 0
    )
    hexes = ["#" + a["color"].lower() for _, a in items]
    numbers = [a.get("number", "") for _, a in items]
    entries = _entries_from_hexes(hexes, names)
    if all(CODE_RE.match(n) for n in numbers) and len(set(numbers)) == len(numbers):
        for entry, code in zip(entries, numbers, strict=True):
            entry["code"] = code
    return entries


def load_chart_png(path: str | Path, palette: Palette) -> np.ndarray:
    """The grid behind an imported pattern's design.py: chart.png, one pixel per cell."""
    return read_png(Image.open(path), palette_entries(palette))


def page_count(pdf_path: str | Path) -> int:
    return len(pdfium.PdfDocument(str(pdf_path)))


def render_page(pdf_path: str | Path, page_no: int, scale: int = RENDER_SCALE) -> Image.Image:
    """One page (1-based) as an RGB image; a page is about 8 megapixels at the default scale."""
    pdf = pdfium.PdfDocument(str(pdf_path))
    return pdf[page_no - 1].render(scale=scale).to_pil().convert("RGB")


def iter_pages(pdf_path: str | Path, scale: int = RENDER_SCALE) -> Iterator[tuple[int, Image.Image]]:
    """(page number, image) one page at a time, so a long PDF never sits in memory whole."""
    pdf = pdfium.PdfDocument(str(pdf_path))
    for i in range(len(pdf)):
        yield i + 1, pdf[i].render(scale=scale).to_pil().convert("RGB")


def page_texts(pdf_path: str | Path) -> list[str]:
    pdf = pdfium.PdfDocument(str(pdf_path))
    return [pdf[i].get_textpage().get_text_range().replace("\r\n", "\n") for i in range(len(pdf))]


def is_own_pdf(pdf_path: str | Path) -> bool:
    return pdfium.PdfDocument(str(pdf_path)).get_metadata_value("Creator") == "graphghan"


# ---------- our own PDF ----------


def read_key(texts: list[str]) -> list[dict]:
    """The palette from the key page(s): rows in the KEY_ROW grammar, parsed off their hex."""
    entries = []
    for text in texts:
        if not text.startswith(KEY_TITLE + "\n"):
            continue
        for line in text.splitlines()[1:]:
            m = KEY_RE.match(line.strip())
            if m:
                yarn = {"note": m.group("yarn")} if m.group("yarn") else {}
                entries.append(
                    {
                        "code": m.group("code"),
                        "name": m.group("name"),
                        "hex": m.group("hex"),
                        "yarn": yarn,
                        "use": "",
                    }
                )
    return entries


def stitch_own_pdf(pdf_path: str | Path) -> ImportResult:
    """Read a graphghan-made PDF back: tiles placed by their headers, palette from the key."""
    texts = page_texts(pdf_path)
    palette = read_key(texts)
    if not palette:
        raise ValueError(f"{pdf_path}: no key page in the graphghan layout")
    grid = None
    covered = None
    regions: list[str] = []
    warnings: list[str] = []
    for page_no, text in enumerate(texts, start=1):
        m = HEADER_RE.match(text)
        if not m:
            continue
        img = render_page(pdf_path, page_no)
        a, b, W, c, d, H = (int(m.group(g)) for g in ("a", "b", "W", "c", "d", "H"))
        if grid is None:
            grid = np.zeros((H, W), dtype=np.uint8)
            covered = np.zeros((H, W), dtype=bool)
        found = rc.find_regions(img)
        regions += [f"page {page_no} region {i + 1}: {r.describe()}" for i, r in enumerate(found)]
        if not found:
            raise ValueError(f"page {page_no}: header says a chart tile but no grid was found")
        region = found[0]
        if (region.cols, region.rows) != (b - a + 1, d - c + 1):
            raise ValueError(
                f"page {page_no}: header says {b - a + 1}x{d - c + 1} cells but the grid reads "
                f"{region.cols}x{region.rows}"
            )
        samples = rc.read_region(img, region)
        idx = rc.snap_to_palette(samples, [p["hex"] for p in palette])
        grid[H - d : H - c + 1, W - b : W - a + 1] = idx
        covered[H - d : H - c + 1, W - b : W - a + 1] = True
        warnings += [f"page {page_no}: {w}" for w in region.warnings]
    if grid is None:
        raise ValueError(f"{pdf_path}: no chart pages in the graphghan layout")
    if not covered.all():
        raise ValueError(f"{pdf_path}: {int((~covered).sum())} cells are on no chart page")
    title = pdfium.PdfDocument(str(pdf_path)).get_metadata_value("Title")
    return ImportResult(grid, palette, str(pdf_path), "graphghan-pdf", regions, warnings, {"title": title})


# ---------- any image or PDF ----------


def _pick(
    candidates: list[tuple[int, int, rc.Region]],
    page: int | None,
    region: int | None,
) -> tuple[int, int, rc.Region]:
    if not candidates:
        raise ValueError("no grid found on any page")
    if page is not None:
        candidates = [c for c in candidates if c[0] == page]
        if not candidates:
            raise ValueError(f"no grid found on page {page}")
    if region is not None:
        by_index = [c for c in candidates if c[1] == region]
        if not by_index:
            raise ValueError(f"no region {region} (have 1..{max(c[1] for c in candidates)})")
        return by_index[0]
    return max(candidates, key=lambda c: c[2].cells)


def _crop(img: Image.Image, box: tuple[float, float, float, float] | None) -> tuple[Image.Image, int, int]:
    if box is None:
        return img, 0, 0
    x0, y0, x1, y1 = (
        int(round(v * s)) for v, s in zip(box, (img.width, img.height, img.width, img.height), strict=True)
    )
    return img.crop((x0, y0, x1, y1)), x0, y0


def read_raster(
    pages: Iterator[tuple[int, Image.Image]] | list[tuple[int, Image.Image]],
    render: Callable[[int], Image.Image],
    *,
    palette: list[dict] | None = None,
    cells: tuple[int, int] | None = None,
    page: int | None = None,
    region: int | None = None,
    box: tuple[float, float, float, float] | None = None,
) -> tuple[np.ndarray, list[dict], list[str], list[str]]:
    """Every grid on every page; the chosen one sampled and clustered or snapped. Pages arrive one
    at a time and are dropped after their grids are noted; `render(page_no)` brings the chosen
    one back, so memory holds one page however long the PDF is."""
    candidates = []
    descriptions = []
    for page_no, img in pages:
        if page is not None and page_no != page:
            continue
        cropped, ox, oy = _crop(img, box)
        for i, r in enumerate(rc.find_regions(cropped), start=1):
            if ox or oy:
                r = rc.Region([x + ox for x in r.xs], [y + oy for y in r.ys], r.noise, r.warnings)
            candidates.append((page_no, i, r))
            descriptions.append(f"page {page_no} region {i}: {r.describe()}")
    page_no, i, chosen = _pick(candidates, page, region)
    img = render(page_no)
    descriptions.insert(0, f"chosen: page {page_no} region {i}")
    samples = rc.read_region(img, chosen, cells)
    idx, entries, warnings = _indexes(samples, palette)
    return idx, entries, descriptions, [f"page {page_no}: {w}" for w in chosen.warnings] + warnings


PIXEL_CHART_MAX = 512  # a 1-px-per-cell chart is at most this wide or tall; a picture of a chart is bigger


def _looks_like_pixels(img: Image.Image) -> bool:
    """A 1-px-per-cell chart is small and has no grid covering it; a picture of a chart is big, or
    has a grid over most of it."""
    if max(img.width, img.height) > PIXEL_CHART_MAX:
        return False
    regions = rc.find_regions(img)
    if not regions:
        return True
    x0, y0, x1, y1 = regions[0].bbox
    return (x1 - x0) * (y1 - y0) < 0.5 * img.width * img.height


def import_file(
    path: str | Path,
    *,
    palette_toml: str | Path | None = None,
    cells: tuple[int, int] | None = None,
    mode: str = "auto",
    page: int | None = None,
    region: int | None = None,
    box: tuple[float, float, float, float] | None = None,
    prose: dict | str | Path | None = None,
    rows_source: str = "auto",
) -> ImportResult:
    """Read the file into an ImportResult. `prose` is a prose.json document or its path; a
    graphghan-made PDF supplies its own when none is given. `rows_source` is auto (written rows
    when present), written, or grid."""
    if rows_source not in ("auto", "written", "grid"):
        raise ValueError(f"rows_source must be auto, written or grid, not {rows_source!r}")
    path = Path(path)
    size = path.stat().st_size
    if size > MAX_FILE_BYTES:
        raise ValueError(
            f"{path.name} is {size / 1_048_576:.0f} MB; the most import reads is {MAX_FILE_BYTES // 1_048_576} MB"
        )
    if isinstance(prose, (str, Path)):
        prose = pr.load_prose(prose)
    elif prose is not None:
        problems = pr.check_prose(prose)
        if problems:
            raise ValueError("prose.json: " + "; ".join(problems))
    result = _read_grid(
        path, palette_toml=palette_toml, cells=cells, mode=mode, page=page, region=region, box=box
    )
    if prose is None and result.kind == "graphghan-pdf" and rows_source != "grid":
        from .pdfself import prose_from_own_pdf  # local: pdfself imports this module

        prose = prose_from_own_pdf(path)
    if prose is not None:
        apply_prose(result, prose, rows_source)
    return result


def _read_grid(
    path: Path,
    *,
    palette_toml: str | Path | None = None,
    cells: tuple[int, int] | None = None,
    mode: str = "auto",
    page: int | None = None,
    region: int | None = None,
    box: tuple[float, float, float, float] | None = None,
) -> ImportResult:
    palette = _entries_from_toml(Path(palette_toml)) if palette_toml else None
    suffix = path.suffix.lower()
    if suffix == ".oxs":
        text = path.read_text(encoding="utf-8")
        names, grid = read_oxs(text)
        if palette is None:
            palette = _oxs_palette(text, names)
        return ImportResult(grid, palette, str(path), "oxs")
    if suffix == ".csv":
        if palette is None:
            raise ValueError("a CSV carries codes, not colours: pass --palette <pattern.toml>")
        return ImportResult(read_csv(path.read_text(encoding="utf-8"), palette), palette, str(path), "csv")
    if suffix == ".pdf":
        if mode == "auto" and is_own_pdf(path):
            return stitch_own_pdf(path)
        try:
            idx, entries, regions, warnings = read_raster(
                iter_pages(path),
                lambda n: render_page(path, n),
                palette=palette,
                cells=cells,
                page=page,
                region=region,
                box=box,
            )
        except ValueError as e:
            if not str(e).startswith("no grid found"):
                raise
            return ImportResult(None, [], str(path), "no-grid", [], [str(e)])
        return ImportResult(idx, entries, str(path), "pdf", regions, warnings)
    if suffix in (".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp"):
        img = Image.open(path).convert("RGB")
        pixels = mode == "pixels" or (mode == "auto" and cells is None and _looks_like_pixels(img))
        if pixels:
            if palette is not None:
                return ImportResult(read_png(img, palette), palette, str(path), "pixels")
            idx, hexes, warnings = rc.cluster_palette(np.asarray(img), radius=2.0)
            return ImportResult(idx, _entries_from_hexes(hexes), str(path), "pixels", [], warnings)
        try:
            idx, entries, regions, warnings = read_raster(
                [(1, img)], lambda _n: img, palette=palette, cells=cells, region=region, box=box
            )
        except ValueError as e:
            if not str(e).startswith("no grid found"):
                raise
            return ImportResult(None, [], str(path), "no-grid", [], [str(e)])
        return ImportResult(idx, entries, str(path), "raster", regions, warnings)
    raise ValueError(f"cannot import {path.name}: not a .pdf, .png/.jpg, .oxs or .csv file")


# ---------- the prose half ----------


def _match_palette(result: ImportResult, entries: list[dict]) -> list[str]:
    """Rewrite the grid's cluster indexes onto the prose palette's order. Entries with a hex claim
    the nearest cluster; without hexes the orders must simply agree. Returns warnings."""
    warnings: list[str] = []
    n_prose, n_grid = len(entries), len(result.palette)
    if n_prose == n_grid and all(e["hex"] for e in entries):
        grid_hexes = result.hexes
        d = np.linalg.norm(
            rc._to_lab(np.array([[int(h[i : i + 2], 16) for i in (1, 3, 5)] for h in grid_hexes]))[:, None, :]
            - rc._to_lab(np.array([[int(e["hex"][i : i + 2], 16) for i in (1, 3, 5)] for e in entries]))[
                None, :, :
            ],
            axis=2,
        )
        claim = [int(k) for k in d.argmin(axis=1)]  # each grid cluster's nearest prose entry
        if len(set(claim)) != n_grid:
            raise ValueError(
                "the key's colours do not pair one-to-one with the colours read off the chart: "
                + ", ".join(
                    f"{g} -> {entries[k]['code']} {entries[k]['hex']}"
                    for g, k in zip(grid_hexes, claim, strict=True)
                )
            )
        remap = np.array(claim, dtype=np.uint8)
        far = [g for g, k in zip(grid_hexes, claim, strict=True) if d[grid_hexes.index(g), k] > 25]
        if far:
            warnings.append(f"chart colours {far} are far from every key colour; check the key")
    elif n_prose == n_grid:
        warnings.append(
            "the key gives no colours; its entries were paired with the chart's colours in order of use"
        )
        remap = np.arange(n_grid, dtype=np.uint8)
    else:
        raise ValueError(
            f"the key has {n_prose} colours but the chart reads {n_grid}; add hex values to the key or fix the count"
        )
    result.grid = remap[result.grid]
    for k, e in enumerate(entries):
        if not e["hex"]:
            e["hex"] = result.palette[
                claim.index(k) if n_prose == n_grid and all(x["hex"] for x in entries) else k
            ]["hex"]
    result.palette = entries
    return warnings


def _covered(doc: dict, result: ImportResult, width: int, height: int) -> tuple[slice, slice] | None:
    """Which chart rows and columns the picture shows, as display-order slices, or None when the
    picture is the whole chart. A partial picture (a strip of rows 1-10) is described by
    chart.pages[].rows/cols; row 1 is at the bottom unless chart.row1 says top."""
    if (result.width, result.height) == (width, height):
        return slice(0, height), slice(0, width)
    pages = (doc.get("chart") or {}).get("pages") or []
    for page in pages:
        rows, cols = page.get("rows"), page.get("cols")
        if not rows or not cols:
            continue
        r0, r1 = sorted(int(v) for v in rows)
        c0, c1 = sorted(int(v) for v in cols)
        if (c1 - c0 + 1, r1 - r0 + 1) != (result.width, result.height):
            continue
        row1 = (doc.get("chart") or {}).get("row1", "bottom-right")
        ys = slice(height - r1, height - r0 + 1) if row1.startswith("bottom") else slice(r0 - 1, r1)
        xs = slice(width - c1, width - c0 + 1) if row1.endswith("right") else slice(c0 - 1, c1)
        return ys, xs
    return None


def _match_by_rows(result: ImportResult, entries: list[dict], written: np.ndarray) -> list[str]:
    """Pair the chart's colour clusters with the key's codes by which code the written rows put
    in those cells (a majority vote per cluster); hexes come from the chart. Returns warnings."""
    warnings: list[str] = []
    codes = [e["code"] for e in entries]
    mapping: dict[int, int] = {}
    for g in range(len(result.palette)):
        cells = written[result.grid == g]
        if cells.size == 0:
            continue
        counts = np.bincount(cells, minlength=len(codes))
        k = int(counts.argmax())
        share = counts[k] / cells.size
        if share < 0.9:
            warnings.append(
                f"chart colour {result.palette[g]['hex']} is {codes[k]!r} in {share:.0%} of its cells and other "
                "codes elsewhere; the rows and the picture disagree there"
            )
        mapping[g] = k
    claimed = list(mapping.values())
    if len(set(claimed)) != len(claimed):
        dup = sorted({codes[k] for k in claimed if claimed.count(k) > 1})
        raise ValueError(
            f"two chart colours both read as {dup} in the written rows; the picture has more colours than the key, or a row is wrong"
        )
    unmatched = [result.palette[g]["hex"] for g in range(len(result.palette)) if g not in mapping]
    if unmatched:
        raise ValueError(
            f"chart colours {unmatched} fall on no written row; the picture and the rows do not line up"
        )
    for g, k in mapping.items():
        if not entries[k].get("hex"):
            entries[k]["hex"] = result.palette[g]["hex"]
        elif entries[k]["hex"].lower() != result.palette[g]["hex"].lower():
            warnings.append(
                f"key colour {entries[k]['code']} is {entries[k]['hex']}, the chart shows {result.palette[g]['hex']}"
            )
    for e in entries:
        if not e.get("hex"):  # a colour the picture does not show (a strip of the chart): placeholder
            e["hex"] = _placeholder_hex([x["hex"] for x in entries if x.get("hex")])
            warnings.append(
                f"key colour {e['code']} ({e['name']}) is on no row the picture shows and has no hex; "
                f"placeholder {e['hex']} written, fill it in"
            )
    remap = np.zeros(len(result.palette), dtype=np.uint8)
    for g, k in mapping.items():
        remap[g] = k
    result.grid = remap[result.grid]
    result.palette = entries
    return warnings


PLACEHOLDERS = ("#ff00ff", "#00ffff", "#ffff00", "#ff8000", "#8000ff", "#00ff80", "#ff0080", "#0080ff")


def _placeholder_hex(taken: list[str]) -> str:
    """A loud colour no other palette entry is near, so a placeholder is never mistaken for real."""
    have = (
        np.array([[int(h[i : i + 2], 16) for i in (1, 3, 5)] for h in taken]) if taken else np.zeros((0, 3))
    )
    for cand in PLACEHOLDERS:
        c = np.array([[int(cand[i : i + 2], 16) for i in (1, 3, 5)]])
        if not len(have) or np.linalg.norm(rc._to_lab(have) - rc._to_lab(c), axis=1).min() > 20:
            return cand
    return PLACEHOLDERS[-1]


def apply_prose(result: ImportResult, doc: dict, rows_source: str = "auto") -> None:
    """Fold the prose into the result: metadata, the written rows as the grid (cross-checked
    against the picture), and the palette paired with the key."""
    result.meta.update(pr.meta_from_prose(doc))
    entries = pr.palette_entries(doc)
    chart = doc.get("chart") or {}
    row1 = chart.get("row1", "bottom-right")
    result.meta["row1"] = row1
    rows = doc.get("written_rows") or []
    if result.grid is None:
        _rows_alone(result, entries, chart, rows, row1)
        return
    use_rows = bool(rows) and rows_source != "grid"
    clustered = (
        result.kind in ("raster", "pdf", "pixels")
        and bool(result.palette)
        and result.palette[0]["code"] == "A"
        and not any(p.get("yarn") for p in result.palette)
    )
    if use_rows:
        width = chart.get("width") or result.width
        height = chart.get("height") or result.height
        codes = [e["code"] for e in entries] if entries else result.codes
        written, problems = pr.written_to_grid(rows, codes, width, height, row1)
        if problems:
            raise ValueError("written rows: " + "; ".join(problems))
        covered = _covered(doc, result, width, height)
        if covered is None:
            raise ValueError(
                f"the picture reads {result.width}x{result.height} but the written rows give {width}x{height}; "
                "say which rows and columns the picture shows in chart.pages"
            )
        ys, xs = covered
        if entries and clustered:
            result.warnings += _match_by_rows(result, entries, written[ys, xs])
        elif entries:
            _names_by_code(result, entries)
        mismatches, error = pr.cross_check(written[ys, xs], result.grid, row1)
        if error:
            raise ValueError("written rows against the chart: " + error)
        result.warnings += [f"written rows against the chart: {m}" for m in mismatches]
        shown = ys.stop - ys.start
        partial = "" if shown == height else f" (the picture shows {shown} of the {height} rows)"
        result.meta["cross_check"] = (
            f"{len(rows)} written rows, {len(mismatches)} disagree with the chart{partial}"
        )
        result.grid = written
        result.kind = result.kind + "+rows"
    else:
        if entries and clustered:
            result.warnings += _match_palette(result, entries)
        elif entries:
            _names_by_code(result, entries)
        if rows:
            result.warnings += [
                f"written rows not used (--rows grid): {w}"
                for w in pr.row_total_problems(rows, result.width)
                + pr.row_number_problems(rows, result.height)
            ]
    if chart.get("no_stitch"):
        for p in result.palette:
            if p["hex"] and p["hex"].lower() == chart["no_stitch"].lower():
                p["use"] = p["use"] or "no stitch"


def _rows_alone(result: ImportResult, entries: list[dict], chart: dict, rows: list[dict], row1: str) -> None:
    """No picture of the chart anywhere: the written rows are the chart, checked by nothing but
    their own totals, and every colour must come from the key."""
    if not rows:
        raise ValueError(
            "no grid was found on any page and the prose has no written rows: nothing to build a chart from"
        )
    width, height = chart.get("width"), chart.get("height")
    if not width or not height:
        raise ValueError(
            "no grid was found on any page: chart.width and chart.height must be given with the written rows"
        )
    missing = [e["code"] for e in entries if not e.get("hex")]
    if not entries or missing:
        raise ValueError(
            f"no picture to take colours from: give every key colour a hex ({', '.join(missing) or 'no key at all'})"
        )
    written, problems = pr.written_to_grid(rows, [e["code"] for e in entries], width, height, row1)
    if problems:
        raise ValueError("written rows: " + "; ".join(problems))
    result.grid = written
    result.palette = entries
    result.kind = "rows"
    result.warnings = [w for w in result.warnings if not w.startswith("no grid found")]
    result.meta["cross_check"] = f"{len(rows)} written rows; no picture of the chart to check them against"


def _names_by_code(result: ImportResult, entries: list[dict]) -> None:
    """Codes came with the file (OXS, CSV, --palette, our own PDF): add names and yarn by code."""
    by_code = {e["code"]: e for e in entries}
    for p in result.palette:
        e = by_code.get(p["code"])
        if e:
            p["name"] = e["name"] or p["name"]
            p["yarn"] = e["yarn"] or p["yarn"]
            p["use"] = e["use"] or p["use"]


def stage_dir(repo_root: Path, source: Path) -> Path:
    return repo_root / "build" / "import" / source.stem


def stage_request(source: Path, result: ImportResult, into: Path, repo_root: Path) -> Path:
    """First run on a foreign file: rendered pages, their text, what the grid read, and what the
    skill must write into prose.json. Returns the staging folder."""
    folder = stage_dir(repo_root, source)
    (folder / "pages").mkdir(parents=True, exist_ok=True)
    texts: list[str] = []
    hints: list[str] = []
    boxes: dict[str, list[dict]] = {}

    def note_boxes(page_no: int, img: Image.Image) -> None:
        """Rows drawn as coloured boxes: their colours in order, at the saved image's half scale."""
        bands = rc.box_rows(img)
        if sum(1 for b in bands if b["label"]) >= 2:
            boxes[str(page_no)] = [
                {
                    "y": b["y"] // 2,
                    "h": b["h"] // 2,
                    "label": b["label"],
                    "boxes": [{"x": x["x"] // 2, "w": x["w"] // 2, "hex": x["hex"]} for x in b["boxes"]],
                }
                for b in bands
            ]
            hints.append(
                f"- page {page_no}: rows drawn as coloured boxes ({sum(1 for b in bands if b['label'])} rows)"
            )

    if source.suffix.lower() == ".pdf":
        texts = page_texts(source)
        for i, img in iter_pages(source):
            img.resize((img.width // 2, img.height // 2)).save(folder / "pages" / f"p{i:02d}.png")
            (folder / "pages" / f"p{i:02d}.txt").write_text(texts[i - 1], encoding="utf-8")
            low = texts[i - 1].lower()
            found = [
                w for w in ("key", "gauge", "hook", "row 1", "materials", "finished", "measure") if w in low
            ]
            if found:
                hints.append(f"- page {i}: mentions {', '.join(found)}")
            note_boxes(i, img)
    else:
        img = Image.open(source).convert("RGB")
        img.save(folder / "pages" / "p01.png")
        note_boxes(1, img.resize((img.width * 2, img.height * 2)))
    if boxes:
        (folder / "boxes.json").write_text(json.dumps(boxes, indent=1), encoding="utf-8")
    (folder / "grid.json").write_text(
        json.dumps(
            {
                "source": str(source),
                "width": result.width or None,
                "height": result.height or None,
                "palette": result.palette,
                "rows": result.rows or None,
                "regions": result.regions,
                "warnings": result.warnings,
            },
            indent=1,
        ),
        encoding="utf-8",
    )
    schema = Path(__file__).resolve().parents[2] / "schema" / "import-prose.schema.json"
    grid_line = (
        f"The grid reader found a {result.width} x {result.height} chart with {len(result.palette)} colours "
        "(see grid.json)."
        if result.grid is not None
        else "The grid reader found no chart on any page, so the written rows will be the chart: give"
        " `chart.width` and `chart.height` and a hex for every key colour."
    )
    request = (
        [
            f"# Import request: {source.name}",
            "",
            f"{grid_line} What it cannot read is the prose. Write `{folder / 'prose.json'}` in the",
            "`graphghan-import/1` shape (the contract is `.claude/skills/graphghan/references/import.md`;",
            f"the schema is `{schema}`), then run the same `graphghan import ... --into {into.name}` again.",
            "",
            "Read from the pages:",
            "",
            "- the colour key: every colour as the pattern names it, with its hex if printed or shown;",
            "- gauge (stitches and rows over a length), hook, yarn weight, finished size, title, designer;",
            "- the written rows, if the pattern has them: every row, runs in working order exactly as printed, and",
            "  the corner the chart's row 1 starts in (`chart.row1`), read off the chart's own numbering;",
            "- setup notes and colour notes worth keeping.",
            "",
            "Do not fix a row whose numbers do not add up: transcribe it as printed and let the import report it.",
            "",
            "Pages:",
            "",
        ]
        + (hints or ["- (no page mentions a key, gauge, or row 1 by word; look at the images)"])
        + (
            [
                "",
                "Rows drawn as coloured boxes: `boxes.json` lists, per page, every band of boxes with each box's",
                "colour in order (positions in the saved page images' pixels). A band with `label` true starts a",
                "row; one without continues the row above. Read the count printed in each box and pair it with",
                "that box's colour, in order, to make the row's runs; the colours are the key's hexes.",
            ]
            if boxes
            else []
        )
        + [
            "",
            f"Page images: `{folder / 'pages'}` (p01.png ...), text beside each as pNN.txt.",
        ]
    )
    (folder / "request.md").write_text("\n".join(request) + "\n", encoding="utf-8")
    return folder


# ---------- the pattern folder ----------


def document(result: ImportResult, slug: str, title: str) -> dict:
    """A minimal chart document for validation before anything is written."""
    rows = result.rows
    return {
        "schema": 2,
        "pattern": {"id": slug, "title": title, "version": "0.1.0"},
        "chart": {
            "id": chart_id(result.codes, rows, dict(TECHNIQUE_ROWS)),
            "width": result.width,
            "height": result.height,
        },
        "palette": result.palette,
        "rows": rows,
        "gauge": {"stitches": 14, "rows": 16, "over": {"value": 4, "unit": "in"}},
        "technique": dict(TECHNIQUE_ROWS),
    }


def problems(result: ImportResult, slug: str = "import", title: str = "Import") -> list[str]:
    out = validate_document(document(result, slug, title))
    used = set(int(v) for v in np.unique(result.grid))
    if not used <= set(range(len(result.palette))):
        out.append(
            f"grid uses palette indexes {sorted(used)} beyond the {len(result.palette)}-colour palette"
        )
    return out


def _toml_str(s: str) -> str:
    return json.dumps(s)


def pattern_toml(result: ImportResult, slug: str, title: str, source: str) -> str:
    meta = result.meta
    bottom = result.grid[-1]
    first = result.codes[int(np.bincount(bottom).argmax())]
    w, h = result.width, result.height
    stitch = meta.get("stitch", "sc")
    gauge = meta.get("gauge") or (3.5, 4.0)
    placeholder = "gauge" not in meta
    size = meta.get("size_in") or (round(w / gauge[0], 1), round(h / gauge[1], 1))
    lines = [
        "[pattern]",
        f"slug = {_toml_str(slug)}",
        f"title = {_toml_str(title)}",
        f"dedication = {_toml_str(meta.get('dedication', ''))}",
        f"quote = {_toml_str(meta.get('quote', ''))}",
        f"version = {_toml_str(meta.get('version', '0.1.0'))}",
        f"stitch = {_toml_str(stitch)}",
        f"size_in = [{size[0]}, {size[1]}]"
        + ("  # IMPORTED: at the placeholder gauge below" if placeholder and "size_in" not in meta else ""),
        f"hook = {_toml_str(meta.get('hook', ''))}" + ("" if meta.get("hook") else "  # IMPORTED: fill me"),
        f"yarn_weight = {_toml_str(meta.get('yarn_weight', ''))}"
        + ("" if meta.get("yarn_weight") else "  # IMPORTED: fill me"),
        f"first_row_color = {_toml_str(first)}",
        f"author = {_toml_str(meta.get('author', ''))}"
        + ("" if meta.get("author") else "  # IMPORTED: the source pattern's designer"),
        f"license = {_toml_str(meta.get('license', ''))}",
    ]
    for key in ("craft", "terms", "language"):
        if meta.get(key):
            lines.append(f"{key} = {_toml_str(meta[key])}")
    lines += [
        "",
        f"# Imported from {source}. The chart lives in chart.png (one pixel per cell).",
    ]
    if placeholder:
        lines.append("# The gauge below is a placeholder until the source's own gauge is written in.")
    lines += ["[gauge]", f"{stitch} = [{gauge[0]}, {gauge[1]}]", ""]
    if meta.get("boundary") or meta.get("stitch_name") or meta.get("unit"):
        lines.append(f"[stitch.{stitch}]")
        if meta.get("stitch_name"):
            lines.append(f"name = {_toml_str(meta['stitch_name'])}")
        b = meta.get("boundary") or {}
        if b:
            lines.append(f"boundary = {_toml_str(b['kind'])}")
            lines.append(f"chain = {int(b['chain'])}")
            if "counts_as_stitch" in b:
                lines.append(f"counts_as_stitch = {'true' if b['counts_as_stitch'] else 'false'}")
            if b.get("color"):
                lines.append(f"chain_color = {_toml_str(b['color'])}")
        if meta.get("unit"):
            lines.append(f"unit = {_toml_str(meta['unit'])}")
        lines.append("")
    for p in result.palette:
        yarn = p.get("yarn") or {}
        lines += [
            "[[colors]]",
            f"code = {_toml_str(p['code'])}",
            f"name = {_toml_str(p['name'])}",
            f"hex = {_toml_str(p['hex'])}",
        ]
        if len(yarn) == 1 and "note" in yarn:
            lines.append(f"yarn = {_toml_str(yarn['note'])}")
        elif yarn:
            lines.append("yarn = { " + ", ".join(f"{k} = {_toml_str(v)}" for k, v in yarn.items()) + " }")
        else:
            lines.append('yarn = ""')
        lines += [f"use = {_toml_str(p.get('use', ''))}", ""]
    notes = meta.get("notes") or {}
    lines += ["[notes]"]
    for key in ("setup", "colors"):
        items = notes.get(key) or []
        lines.append(f"{key} = [" + ", ".join(_toml_str(x) for x in items) + "]")
    lines += ["", "[publish]", f'charts = [["final", {_toml_str(stitch)}]]', ""]
    for sec in meta.get("instructions") or []:
        lines += [
            "[[instructions]]",
            f"title = {_toml_str(sec['title'])}",
            f"text = {_toml_str(sec['text'])}",
            "",
        ]
    return "\n".join(lines)


def report_md(result: ImportResult, folder: Path, title: str) -> str:
    lines = [
        f"# Import report: {title}",
        "",
        f"Source: `{result.source}` ({result.kind}). If this is someone else's pattern, this folder is",
        "for your own use and must not be committed or published.",
        "",
        f"Chart: {result.width} columns x {result.height} rows, {len(result.palette)} colours.",
        "",
        "## Palette",
        "",
    ]
    counts = np.bincount(result.grid.ravel(), minlength=len(result.palette))
    for i, p in enumerate(result.palette):
        lines.append(f"- `{p['code']}` {p['name']} {p['hex']}: {int(counts[i]):,} cells")
    if result.meta.get("cross_check"):
        lines += [
            "",
            "## Written rows",
            "",
            f"- {result.meta['cross_check']} (the written rows are the chart; the grid was the cross-check)",
        ]
    if result.meta.get("uncertain"):
        lines += ["", "## The reader was unsure of", ""] + [f"- {u}" for u in result.meta["uncertain"]]
    if result.regions:
        lines += ["", "## Grids found", ""] + [f"- {r}" for r in result.regions]
    lines += ["", "## Warnings", ""] + ([f"- {w}" for w in result.warnings] or ["- none"])
    lines += [
        "",
        "## Next",
        "",
        f"- `uv run graphghan render {folder.name}` then `uv run graphghan check {folder.name}`",
    ]
    return "\n".join(lines) + "\n"


def write_pattern(
    result: ImportResult, into: str | Path, title: str | None = None, force: bool = False
) -> Path:
    """Validate and write the pattern folder. Returns the folder."""
    folder = Path(into)
    slug = folder.name
    title = title or result.meta.get("title") or slug.replace("-", " ").title()
    bad = problems(result, slug, title)
    if bad:
        raise ValueError("import failed validation: " + "; ".join(bad))
    if folder.exists() and not force:
        raise FileExistsError(f"{folder} exists; pass --force to overwrite its files")
    (folder / "tests").mkdir(parents=True, exist_ok=True)
    (folder / "pattern.toml").write_text(pattern_toml(result, slug, title, Path(result.source).name))
    rgb = [tuple(int(p["hex"][i : i + 2], 16) for i in (1, 3, 5)) for p in result.palette]
    chart_png(result.grid, rgb, folder / "chart.png")
    subs = {"title": title, "sha": hashlib.sha256("\n".join(result.rows).encode()).hexdigest()}
    (folder / "design.py").write_text((TEMPLATES / "import-design.py.tmpl").read_text().format(**subs))
    (folder / "tests" / "test_design.py").write_text(
        (TEMPLATES / "import-test_design.py.tmpl").read_text().format(**subs)
    )
    (folder / "import-report.md").write_text(report_md(result, folder, title))
    (folder / "CHANGELOG.md").write_text(f"# {slug}\n\n## 0.1.0\nImported from {Path(result.source).name}.\n")
    return folder


def check_folder(folder: Path, repo_root: Path) -> tuple[bool, str]:
    """Render the folder's dist and run its tests; (ok, output)."""
    from .cli import main  # local import: cli imports this module

    ok = main(["render", str(folder)]) == 0
    r = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", str(folder / "tests")],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    ok = ok and r.returncode == 0
    return ok, r.stdout + r.stderr


def remove_folder(folder: Path) -> None:
    shutil.rmtree(folder, ignore_errors=True)
