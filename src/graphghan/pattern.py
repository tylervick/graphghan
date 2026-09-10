"""Pattern folders: pattern.toml metadata and design.py loading."""

from __future__ import annotations

import importlib.util
import tomllib
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType

from . import grid as gr
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
    dir: Path


def find_repo_root(start: str | Path | None = None) -> Path:
    p = Path(start or Path.cwd()).resolve()
    for cand in [p, *p.parents]:
        if (cand / "pyproject.toml").exists():
            return cand
    raise FileNotFoundError("no pyproject.toml found walking up from %s" % p)


def pattern_dir(slug: str, root: Path | None = None) -> Path:
    return (root or find_repo_root()) / "patterns" / slug


def load_pattern(pattern_dir: str | Path) -> PatternMeta:
    d = Path(pattern_dir).resolve()
    data = tomllib.loads((d / "pattern.toml").read_text())
    p = data["pattern"]
    gauges = {k: (float(v[0]), float(v[1])) for k, v in data.get("gauge", {}).items()}
    for name, (st, rows) in gauges.items():
        gr.register_gauge(name, st, rows)
    notes = {k: list(v) for k, v in data.get("notes", {}).items()}
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
        dir=d,
    )


def load_design(pattern_dir: str | Path) -> ModuleType:
    d = Path(pattern_dir).resolve()
    spec = importlib.util.spec_from_file_location("design_%s" % d.name.replace("-", "_"), d / "design.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
