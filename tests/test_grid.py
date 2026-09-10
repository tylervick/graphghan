import numpy as np
import pytest

from graphghan import grid as gr


@pytest.fixture(autouse=True)
def reset_gauge():
    gr.set_gauge("sc")
    yield
    gr.set_gauge("sc")


def test_default_gauge_and_conversions():
    assert gr.current_gauge() == (3.5, 4.0)
    assert gr.cols(4.0) == 14 and gr.rows(4.0) == 16
    assert abs(gr.SW - 1 / 3.5) < 1e-9 and gr.SH == 0.25


def test_set_gauge_by_name_and_pair():
    gr.set_gauge("hdc")
    assert gr.current_gauge() == (3.25, 2.5) and gr.rows(4.0) == 10
    gr.set_gauge((4.0, 4.0))
    assert gr.cols(1.0) == 4 and gr.rows(1.0) == 4


def test_register_gauge():
    gr.register_gauge("bulky", 2.75, 3.0)
    gr.set_gauge("bulky")
    assert gr.current_gauge() == (2.75, 3.0)


def test_grid_rect_and_blit():
    g = gr.Grid(10, 6, 0)
    g.rect(1, 1, 4, 3, 2)
    assert g.a[1:3, 1:4].tolist() == [[2, 2, 2], [2, 2, 2]] and g.a.sum() == 12
    patch = np.array([[7, 0], [0, 7]], dtype=np.uint8)
    g.blit(patch, 8, 4, transparent=0)
    assert g.a[4, 8] == 7 and g.a[4, 9] == 0 and g.a[5, 9] == 7


def test_circle_ring_is_round_in_inches():
    # 2 in radius ring: ~7 columns wide, 8 rows tall in cells
    m = gr.circle_ring(40, 40, 19.5, 19.5, 1.7, 2.0)
    ys, xs = np.where(m)
    assert 13 <= xs.max() - xs.min() + 1 <= 15
    assert 15 <= ys.max() - ys.min() + 1 <= 17


def test_weave_cuts_under_strand_only_inside_window():
    a = np.zeros((7, 7), bool); a[3, :] = True          # horizontal bar
    b = np.zeros((7, 7), bool); b[:, 3] = True          # vertical bar
    win = np.ones((7, 7), bool)
    a2, b2, found = gr.weave(a, b, [(win, True)])
    assert found == 1
    assert a2.sum() == 7                                # over strand untouched
    assert not b2[2, 3] and not b2[4, 3] and b2[0, 3]   # under strand loses the cells touching the bar


def test_curve_mask_in_is_symmetric():
    pts = [(x, 5.0) for x in np.arange(-1, 21, 0.05)]
    m = gr.curve_mask_in(20, 11, pts, 0.3, gr.SW, gr.SH)
    assert np.array_equal(m, m[:, ::-1])
    assert m[5].all() and m[4].all() and not m[2].any()
