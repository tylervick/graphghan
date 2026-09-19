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
TEMPLATES = Path(__file__).parent / "templates"


@dataclass
class ImportResult:
    grid: np.ndarray  # (height, width) palette indexes
    palette: list[dict]  # chart-format entries: code, name, hex, yarn, use
    source: str
    kind: str  # oxs | csv | pixels | raster | pdf | graphghan-pdf
    regions: list[str] = field(default_factory=list)  # every grid found, as text, chosen first
    warnings: list[str] = field(default_factory=list)
    meta: dict = field(default_factory=dict)  # title and friends when the source carries them

    @property
    def width(self) -> int:
        return int(self.grid.shape[1])

    @property
    def height(self) -> int:
        return int(self.grid.shape[0])

    @property
    def codes(self) -> list[str]:
        return [p["code"] for p in self.palette]

    @property
    def rows(self) -> list[str]:
        return rows_to_strings(self.grid, self.codes)

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


def _looks_like_pixels(img: Image.Image) -> bool:
    """A 1-px-per-cell chart has no grid covering it; a picture of a chart does."""
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
) -> ImportResult:
    path = Path(path)
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
        idx, entries, regions, warnings = read_raster(
            iter_pages(path),
            lambda n: render_page(path, n),
            palette=palette,
            cells=cells,
            page=page,
            region=region,
            box=box,
        )
        return ImportResult(idx, entries, str(path), "pdf", regions, warnings)
    if suffix in (".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp"):
        img = Image.open(path).convert("RGB")
        pixels = mode == "pixels" or (mode == "auto" and cells is None and _looks_like_pixels(img))
        if pixels:
            if palette is not None:
                return ImportResult(read_png(img, palette), palette, str(path), "pixels")
            idx, hexes, warnings = rc.cluster_palette(np.asarray(img), radius=2.0)
            return ImportResult(idx, _entries_from_hexes(hexes), str(path), "pixels", [], warnings)
        idx, entries, regions, warnings = read_raster(
            [(1, img)], lambda _n: img, palette=palette, cells=cells, region=region, box=box
        )
        return ImportResult(idx, entries, str(path), "raster", regions, warnings)
    raise ValueError(f"cannot import {path.name}: not a .pdf, .png/.jpg, .oxs or .csv file")


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
    bottom = result.grid[-1]
    first = result.codes[int(np.bincount(bottom).argmax())]
    w, h = result.width, result.height
    lines = [
        "[pattern]",
        f"slug = {_toml_str(slug)}",
        f"title = {_toml_str(title)}",
        'dedication = ""',
        'quote = ""',
        'version = "0.1.0"',
        'stitch = "sc"',
        f"size_in = [{round(w / 3.5, 1)}, {round(h / 4.0, 1)}]  # IMPORTED: at the placeholder sc gauge below",
        'hook = ""  # IMPORTED: fill me',
        'yarn_weight = ""  # IMPORTED: fill me',
        f"first_row_color = {_toml_str(first)}",
        'author = ""  # IMPORTED: the source pattern\'s designer',
        'license = ""',
        "",
        f"# Imported from {source}. The chart lives in chart.png (one pixel per cell); the gauge below",
        "# is a placeholder until the source's own gauge is written in.",
        "[gauge]",
        "sc = [3.5, 4.0]",
        "",
    ]
    for p in result.palette:
        lines += [
            "[[colors]]",
            f"code = {_toml_str(p['code'])}",
            f"name = {_toml_str(p['name'])}",
            f"hex = {_toml_str(p['hex'])}",
            f"yarn = {_toml_str(p.get('yarn', {}).get('note', ''))}",
            f"use = {_toml_str(p.get('use', ''))}",
            "",
        ]
    lines += ["[notes]", "setup = []", "colors = []", "", "[publish]", 'charts = [["final", "sc"]]', ""]
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
