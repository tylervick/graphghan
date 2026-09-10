import numpy as np
import pytest

from graphghan import Grid
from graphghan import grid as gr
from graphghan.compose import text_block
from graphghan.frame import link_frame, twist_frame
from graphghan.text import FONT_METAMORPHOUS

G, Y, C, K, P, R = range(6)


@pytest.fixture(autouse=True)
def sc():
    gr.set_gauge("sc")


@pytest.mark.parametrize("corners", ["solid", "dot", "cross"])
def test_twist_frame_edges_mirror_and_panel(corners):
    W, H = 189, 184
    g = Grid(W, H, G)
    x0, y0, x1, y1 = twist_frame(g, W, H, G, Y, corners=corners)
    a = g.a
    ex, ey = gr.cols(0.5), gr.rows(0.5)
    assert (a[:ey] == Y).all() and (a[-ey:] == Y).all() and (a[:, :ex] == Y).all() and (a[:, -ex:] == Y).all()
    sx, sy = gr.cols(3.5), gr.rows(3.5)
    assert np.array_equal(a[:, :ex + sx], a[:, W - ex - sx:][:, ::-1])
    assert np.array_equal(a[:ey + sy], a[H - ey - sy:][::-1])
    assert x0 == W - x1 and y0 == H - y1 and x1 - x0 > 140 and y1 - y0 > 130


def test_link_frame_panel_and_blooms():
    W, H = 120, 100
    g = Grid(W, H, G)
    x0, y0, x1, y1 = link_frame(g, W, H, G, Y, P, Y, R)
    assert (g.a[0] == R).all() and (g.a == P).sum() >= 8 * 4
    assert x0 == W - x1 and y0 == H - y1


def test_text_block_centres_lines():
    g = Grid(200, 100, C)
    boxes = text_block(g, ["Lord, you", "gave me"], 100, 10, 17, 20, FONT_METAMORPHOUS, K, C)
    assert len(boxes) == 2 and boxes[1][1] == 30
    for x0, y0, x1, y1 in boxes:
        assert abs((x0 + x1) / 2 - 100) <= 1 and (g.a[y0:y1, x0:x1] == K).any()
