"""Exporters from a schema 2 chart document to interchange formats: 1-px PNG, OXS, CSV.

Each `to_*` takes the JSON document (a dict) and each `read_*` turns the exported form back into
a (height, width) uint8 grid of palette indexes, which is what the round-trip tests compare.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

from .export import decode_rows, generator_version


def _codes(doc) -> list[str]:
    return [p["code"] for p in doc["palette"]]


def _rgb(hex_str: str) -> tuple[int, int, int]:
    return tuple(int(hex_str[i : i + 2], 16) for i in (1, 3, 5))


def _grid(doc) -> np.ndarray:
    return decode_rows(doc["rows"], _codes(doc))


def _num(v: float) -> str:
    return f"{v:g}"


# ---------- PNG: one pixel per stitch ----------


def to_png(doc) -> Image.Image:
    rgb = [_rgb(p["hex"]) for p in doc["palette"]]
    if len(set(rgb)) != len(rgb):
        raise ValueError("PNG export needs distinct palette colors (two palette entries share a hex)")
    return Image.fromarray(np.array(rgb, dtype=np.uint8)[_grid(doc)], "RGB")


def read_png(img: Image.Image, palette: list[dict]) -> np.ndarray:
    lookup = {_rgb(p["hex"]): i for i, p in enumerate(palette)}
    px = np.asarray(img.convert("RGB"))
    out = np.zeros(px.shape[:2], dtype=np.uint8)
    for y in range(px.shape[0]):
        for x in range(px.shape[1]):
            key = tuple(int(v) for v in px[y, x])
            if key not in lookup:
                raise ValueError(f"pixel ({x}, {y}) color {key} is not in the palette")
            out[y, x] = lookup[key]
    return out


# ---------- CSV: one code per cell ----------


def to_csv(doc) -> str:
    codes = _codes(doc)
    return "\n".join(",".join(codes[c] for c in row) for row in _grid(doc)) + "\n"


def read_csv(text: str, palette: list[dict]) -> np.ndarray:
    idx = {p["code"]: i for i, p in enumerate(palette)}
    rows = [line.split(",") for line in text.splitlines() if line.strip()]
    out = []
    for y, row in enumerate(rows):
        cells = []
        for x, c in enumerate(row):
            if c not in idx:
                raise ValueError(f"row {y} column {x}: unknown code {c!r}")
            cells.append(idx[c])
        out.append(cells)
    return np.array(out, dtype=np.uint8)


# ---------- OXS: Open Cross Stitch (Ursa Software) ----------

_OXS_TAIL = ("partstitches", "backstitches", "ornaments_inc_knots_and_beads", "commentboxes")


def to_oxs(doc) -> str:
    p, c, g = doc["pattern"], doc["chart"], doc["gauge"]
    per = g["over"]["value"]
    per_in = per if g["over"]["unit"] == "in" else per / 2.54
    root = ET.Element("chart")
    ET.SubElement(
        root,
        "format",
        comments01="Open Cross Stitch (OXS) written by graphghan",
        comments02="Full stitches only. Palette index 0 is the cloth. x and y are 0-based from the top-left cell.",
    )
    ET.SubElement(
        root,
        "properties",
        oxsversion="1.0",
        software="graphghan",
        software_version=generator_version(),
        chartheight=str(c["height"]),
        chartwidth=str(c["width"]),
        charttitle=p.get("title", ""),
        author=p.get("author", ""),
        copyright=p.get("license", ""),
        instructions="",
        stitchesperinch=_num(g["stitches"] / per_in),
        stitchesperinch_y=_num(g["rows"] / per_in),
        palettecount=str(len(doc["palette"]) + 1),
    )
    pal = ET.SubElement(root, "palette")
    ET.SubElement(pal, "palette_item", index="0", number="cloth", name="cloth", color="FFFFFF")
    for i, item in enumerate(doc["palette"], start=1):
        thread = item.get("thread")
        number = f"{thread['system']} {thread['number']}" if thread else item["code"]
        ET.SubElement(
            pal,
            "palette_item",
            index=str(i),
            number=number,
            name=item["name"],
            color=item["hex"][1:].upper(),
            symbol=item.get("symbol") or item["code"],
            strands="2",
        )
    full = ET.SubElement(root, "fullstitches")
    a = _grid(doc)
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            ET.SubElement(full, "stitch", x=str(x), y=str(y), palindex=str(int(a[y, x]) + 1))
    for tag in _OXS_TAIL:
        ET.SubElement(root, tag)
    ET.indent(root)
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n"


def read_oxs(text: str) -> tuple[list[str], np.ndarray]:
    root = ET.fromstring(text)
    props = root.find("properties").attrib
    w, h = int(props["chartwidth"]), int(props["chartheight"])
    names = {int(i.attrib["index"]): i.attrib.get("name", "") for i in root.find("palette")}
    a = np.zeros((h, w), dtype=np.uint8)
    for s in root.find("fullstitches"):
        a[int(s.attrib["y"]), int(s.attrib["x"])] = int(s.attrib["palindex"]) - 1
    return [names[i] for i in sorted(names) if i != 0], a
