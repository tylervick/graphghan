import warnings
from pathlib import Path

import pytest

from graphghan.palette import Color, Palette, load

FIX = Path(__file__).parent / "fixtures" / "minimal"


def test_color_hex():
    assert Color("A", "Alpha", (17, 34, 51)).hex == "#112233"


def test_palette_accepts_one_to_three_letters():
    pal = Palette([Color("A", "a", (0, 0, 0)), Color("Gd", "b", (1, 1, 1)), Color("Kbl", "c", (2, 2, 2))])
    assert pal.codes == ["A", "Gd", "Kbl"] and pal["Kbl"] == 2


@pytest.mark.parametrize("code", ["", "ABCD", "A1", "a-", "1"])
def test_palette_rejects_bad_codes(code):
    with pytest.raises(ValueError):
        Palette([Color(code, "x", (0, 0, 0))])


def test_palette_rejects_duplicates_and_warns_on_case_only_duplicates():
    with pytest.raises(ValueError):
        Palette([Color("A", "x", (0, 0, 0)), Color("A", "y", (1, 1, 1))])
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        Palette([Color("c", "x", (0, 0, 0)), Color("C", "y", (1, 1, 1))])
    assert any("differ only by case" in str(x.message) for x in w)


def test_palette_from_toml_orders_and_indexes():
    pal = Palette.from_toml(FIX / "pattern.toml")
    assert len(pal) == 2 and pal.codes == ["A", "B"]
    assert pal["A"] == 0 and pal["B"] == 1
    assert pal.rgb == [(17, 34, 51), (255, 255, 255)]
    assert pal.color("A").yarn == {"note": "any"} and pal.color("B").use == ""
    assert pal.color("A").thread is None and pal.color("A").symbol == ""


def test_palette_from_toml_structured_yarn_and_thread(tmp_path):
    (tmp_path / "pattern.toml").write_text(
        '[[colors]]\ncode = "Y"\nname = "Gold"\nhex = "#D9A21B"\nsymbol = "*"\n'
        '[colors.yarn]\nbrand = "Red Heart"\nline = "Super Saver"\ncolorway = "Gold"\nweight = "4"\n'
        '[colors.thread]\nsystem = "DMC"\nnumber = "783"\n'
    )
    c = Palette.from_toml(tmp_path / "pattern.toml").color("Y")
    assert c.yarn == {"brand": "Red Heart", "line": "Super Saver", "colorway": "Gold", "weight": "4"}
    assert c.thread == {"system": "DMC", "number": "783"} and c.symbol == "*"


def test_load_from_design_file():
    pal = load(str(FIX / "design.py"))
    assert pal.codes == ["A", "B"]
