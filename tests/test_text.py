from graphghan import grid as gr
from graphghan.text import FONT_METAMORPHOUS, text_line


def test_line_height_is_exact_and_glyphs_present():
    gr.set_gauge("sc")
    arr, asc, desc = text_line(
        "Lord", 17, color=1, bg=0, font_path=FONT_METAMORPHOUS, bold=0.035, threshold=0.42
    )
    assert arr.shape[0] == 17 and asc + desc == 17 and 10 <= asc <= 15
    assert (arr == 1).sum() > 60 and arr[:, 0].any() and arr[:, -1].any()  # trimmed to ink


def test_width_follows_cell_aspect():
    gr.set_gauge("sc")
    w_sc = text_line("woman", 12, 1, 0, FONT_METAMORPHOUS)[0].shape[1]
    gr.set_gauge("hdc")
    w_hdc = text_line("woman", 12, 1, 0, FONT_METAMORPHOUS)[0].shape[1]
    gr.set_gauge("sc")
    # hdc rows are 1.6x taller than sc rows, so the same 12-row line is physically taller and wider
    assert w_hdc > w_sc * 1.4


def test_empty_text_returns_background_column():
    gr.set_gauge("sc")
    arr, asc, desc = text_line("", 12, 1, 0, FONT_METAMORPHOUS)
    assert arr.shape == (12, 1) and (arr == 0).all() and asc + desc == 12


def test_whitespace_text_returns_background_column():
    gr.set_gauge("sc")
    arr, asc, desc = text_line("   ", 12, 1, 0, FONT_METAMORPHOUS)
    assert arr.shape == (12, 1) and (arr == 0).all() and asc + desc == 12
