from pathlib import Path

import pytest

from graphghan.palette import Color, Palette, load

FIX = Path(__file__).parent / "fixtures" / "minimal"


def test_color_hex():
    assert Color("A", "Alpha", (17, 34, 51)).hex == "#112233"


def test_palette_rejects_multi_char_code():
    with pytest.raises(ValueError):
        Palette([Color("BG", "x", (0, 0, 0))])


def test_palette_from_toml_orders_and_indexes():
    pal = Palette.from_toml(FIX / "pattern.toml")
    assert len(pal) == 2 and pal.codes == ["A", "B"]
    assert pal["A"] == 0 and pal["B"] == 1
    assert pal.rgb == [(17, 34, 51), (255, 255, 255)]
    assert pal.color("A").yarn == "any" and pal.color("B").use == ""


def test_load_from_design_file():
    pal = load(str(FIX / "design.py"))
    assert pal.codes == ["A", "B"]
