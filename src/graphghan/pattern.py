"""Pattern folders: pattern.toml metadata and design.py loading."""

from __future__ import annotations

import importlib.util
import tomllib
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType

from . import grid as gr
from .chartdoc import BOUNDARY_KINDS, CHAIN_COLORS
from .palette import Palette


@dataclass
class PatternMeta:
    slug: str
    title: str
    dedication: str
    quote: str
    version: str
    stitch: str
    size_in: tuple[float, float]
    hook: str
    yarn_weight: str
    first_row_color: str
    gauges: dict[str, tuple[float, float]]
    palette: Palette
    notes: dict[str, list[str]]
    publish: list[tuple[str, str]]
    instructions: list[dict]
    author: str
    license: str
    craft: str
    terms: str
    terms_also: str
    language: str
    stitches: dict[str, dict]
    dir: Path


def find_repo_root(start: str | Path | None = None) -> Path:
    p = Path(start or Path.cwd()).resolve()
    for cand in [p, *p.parents]:
        if (cand / "pyproject.toml").exists():
            return cand
    raise FileNotFoundError("no pyproject.toml found walking up from %s" % p)


def pattern_dir(slug: str, root: Path | None = None) -> Path:
    return (root or find_repo_root()) / "patterns" / slug


GAUGE_UNITS = ("stitches", "tiles", "repeats", "rounds")
STITCH_KEYS = ("boundary", "chain", "counts_as_stitch", "chain_color", "first_stitch_in", "name", "unit")


def _stitch_entry(key: str, raw: dict) -> dict:
    """One [stitch.<key>] table, normalised. Only authored keys survive; nothing is invented
    except boundary = "turn" when a chain is given without a kind (every chart we generate today
    is worked in turned rows)."""
    unknown = sorted(set(raw) - set(STITCH_KEYS))
    if unknown:
        raise ValueError(f"[stitch.{key}] has unknown keys {unknown}; allowed: {list(STITCH_KEYS)}")
    out: dict = {}
    if "boundary" in raw:
        if raw["boundary"] not in BOUNDARY_KINDS:
            raise ValueError(f"[stitch.{key}].boundary {raw['boundary']!r} is not one of {BOUNDARY_KINDS}")
        out["boundary"] = str(raw["boundary"])
    if "chain" in raw:
        chain = raw["chain"]
        if isinstance(chain, bool) or not isinstance(chain, int) or chain < 0:
            raise ValueError(f"[stitch.{key}].chain {chain!r} must be an integer >= 0")
        out["chain"] = chain
        out.setdefault("boundary", "turn")
    if "counts_as_stitch" in raw:
        if not isinstance(raw["counts_as_stitch"], bool):
            raise ValueError(f"[stitch.{key}].counts_as_stitch must be true or false")
        out["counts_as_stitch"] = raw["counts_as_stitch"]
    if "chain_color" in raw:
        if raw["chain_color"] not in CHAIN_COLORS:
            raise ValueError(
                f"[stitch.{key}].chain_color {raw['chain_color']!r} is not one of {CHAIN_COLORS}"
            )
        out["chain_color"] = str(raw["chain_color"])
    if "first_stitch_in" in raw:
        fsi = raw["first_stitch_in"]
        if isinstance(fsi, bool) or not isinstance(fsi, int) or fsi < 1:
            raise ValueError(f"[stitch.{key}].first_stitch_in {fsi!r} must be an integer >= 1")
        out["first_stitch_in"] = fsi
    if "name" in raw:
        out["name"] = str(raw["name"])
    if "unit" in raw:
        if raw["unit"] not in GAUGE_UNITS:
            raise ValueError(f"[stitch.{key}].unit {raw['unit']!r} is not one of {GAUGE_UNITS}")
        out["unit"] = str(raw["unit"])
    if "boundary" in out and "chain" not in out:
        raise ValueError(f"[stitch.{key}].boundary needs a chain (0 is legal)")
    return out


def load_pattern(pattern_dir: str | Path) -> PatternMeta:
    d = Path(pattern_dir).resolve()
    data = tomllib.loads((d / "pattern.toml").read_text())
    p = data["pattern"]
    gauges = {k: (float(v[0]), float(v[1])) for k, v in data.get("gauge", {}).items()}
    for name, (st, rows) in gauges.items():
        gr.register_gauge(name, st, rows)
    notes = {k: list(v) for k, v in data.get("notes", {}).items()}
    publish = [(str(v), str(g)) for v, g in data.get("publish", {}).get("charts", [])]
    if not publish:
        publish = [("final", p.get("stitch", "sc"))]
    instructions = []
    for key, title in (("setup", "Setup"), ("colors", "Colors")):
        if notes.get(key):
            instructions.append({"title": title, "text": "\n".join(notes[key])})
    for sec in data.get("instructions", []):
        instructions.append({"title": str(sec["title"]), "text": str(sec["text"])})
    stitches = {str(k): _stitch_entry(str(k), dict(v)) for k, v in data.get("stitch", {}).items()}
    for field, allowed in (
        ("terms", ("US", "UK")),
        ("terms_also", ("US", "UK")),
        ("craft", ("crochet", "knit", "tunisian", "cross-stitch")),
    ):
        if p.get(field, "") not in ("", *allowed):
            raise ValueError(f"[pattern].{field} {p[field]!r} is not one of {allowed}")
    return PatternMeta(
        slug=p["slug"],
        title=p["title"],
        dedication=p.get("dedication", ""),
        quote=p.get("quote", ""),
        version=p["version"],
        stitch=p.get("stitch", "sc"),
        size_in=tuple(float(x) for x in p["size_in"]),
        hook=p.get("hook", ""),
        yarn_weight=p.get("yarn_weight", ""),
        first_row_color=p.get("first_row_color", ""),
        gauges=gauges,
        palette=Palette.from_toml(d / "pattern.toml"),
        notes=notes,
        publish=publish,
        instructions=instructions,
        author=p.get("author", ""),
        license=p.get("license", ""),
        craft=p.get("craft", ""),
        terms=p.get("terms", ""),
        terms_also=p.get("terms_also", ""),
        language=p.get("language", ""),
        stitches=stitches,
        dir=d,
    )


def load_design(pattern_dir: str | Path) -> ModuleType:
    d = Path(pattern_dir).resolve()
    spec = importlib.util.spec_from_file_location("design_%s" % d.name.replace("-", "_"), d / "design.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
