"""Per-pattern palette: an ordered list of colors whose index is the cell value in the grid."""

from __future__ import annotations

import re
import tomllib
import warnings
from dataclasses import dataclass, field
from pathlib import Path

CODE_RE = re.compile(r"^[A-Za-z]{1,3}$")
YARN_KEYS = ("brand", "line", "colorway", "weight", "lot", "note")
THREAD_KEYS = ("system", "number")


@dataclass(frozen=True)
class Color:
    code: str
    name: str
    rgb: tuple[int, int, int]
    yarn: dict[str, str] = field(default_factory=dict)
    use: str = ""
    thread: dict[str, str] | None = None
    symbol: str = ""

    @property
    def hex(self) -> str:
        return "#%02x%02x%02x" % self.rgb


def parse_hex(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def _yarn(value) -> dict[str, str]:
    if not value:
        return {}
    if isinstance(value, str):
        return {"note": value}
    return {k: str(value[k]) for k in YARN_KEYS if value.get(k)}


def _thread(value) -> dict[str, str] | None:
    if not value:
        return None
    return {k: str(value[k]) for k in THREAD_KEYS if value.get(k)}


class Palette:
    def __init__(self, colors: list[Color]):
        self.colors = list(colors)
        for c in self.colors:
            if not CODE_RE.match(c.code):
                raise ValueError(f"invalid palette code {c.code!r}: must be 1-3 letters (^[A-Za-z]{{1,3}}$)")
        self._index = {c.code: i for i, c in enumerate(self.colors)}
        if len(self._index) != len(self.colors):
            raise ValueError("duplicate color codes in palette")
        folded: dict[str, str] = {}
        for c in self.colors:
            other = folded.setdefault(c.code.lower(), c.code)
            if other != c.code:
                warnings.warn(
                    f"palette codes {other!r} and {c.code!r} differ only by case; easy to misread at the hook",
                    stacklevel=2,
                )

    def __getitem__(self, code: str) -> int:
        return self._index[code]

    def __len__(self) -> int:
        return len(self.colors)

    def __contains__(self, code: str) -> bool:
        return code in self._index

    @property
    def codes(self) -> list[str]:
        return [c.code for c in self.colors]

    @property
    def rgb(self) -> list[tuple[int, int, int]]:
        return [c.rgb for c in self.colors]

    @property
    def names(self) -> list[str]:
        return [c.name for c in self.colors]

    def color(self, code: str) -> Color:
        return self.colors[self._index[code]]

    @classmethod
    def from_toml(cls, path: str | Path) -> Palette:
        data = tomllib.loads(Path(path).read_text())
        return cls(
            [
                Color(
                    c["code"],
                    c["name"],
                    parse_hex(c["hex"]),
                    _yarn(c.get("yarn")),
                    c.get("use", ""),
                    _thread(c.get("thread")),
                    c.get("symbol", ""),
                )
                for c in data["colors"]
            ]
        )


def load(design_file: str | Path) -> Palette:
    """Palette for the pattern whose design.py is `design_file` (pattern.toml sits beside it)."""
    return Palette.from_toml(Path(design_file).resolve().parent / "pattern.toml")
