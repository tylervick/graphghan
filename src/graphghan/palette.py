"""Per-pattern palette: an ordered list of colors whose index is the cell value in the grid."""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass
from pathlib import Path

_CODE_RE = re.compile(r"^[A-Za-z]$")


@dataclass(frozen=True)
class Color:
    code: str
    name: str
    rgb: tuple[int, int, int]
    yarn: str = ""
    use: str = ""

    @property
    def hex(self) -> str:
        return "#%02x%02x%02x" % self.rgb


def parse_hex(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


class Palette:
    def __init__(self, colors: list[Color]):
        self.colors = list(colors)
        for c in self.colors:
            if not _CODE_RE.match(c.code):
                raise ValueError(f"invalid palette code {c.code!r}: must be a single letter (^[A-Za-z]$)")
        self._index = {c.code: i for i, c in enumerate(self.colors)}
        if len(self._index) != len(self.colors):
            raise ValueError("duplicate color codes in palette")

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
    def from_toml(cls, path: str | Path) -> "Palette":
        data = tomllib.loads(Path(path).read_text())
        return cls(
            [
                Color(c["code"], c["name"], parse_hex(c["hex"]), c.get("yarn", ""), c.get("use", ""))
                for c in data["colors"]
            ]
        )


def load(design_file: str | Path) -> Palette:
    """Palette for the pattern whose design.py is `design_file` (pattern.toml sits beside it)."""
    return Palette.from_toml(Path(design_file).resolve().parent / "pattern.toml")
