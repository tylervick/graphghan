import numpy as np
import pytest

from graphghan import grid as gr
from graphghan.motifs import CATALOG, bands, dragonfly, knots, plaid, rings, stones, thistle, twist

BG, FG, P2, P3 = 0, 1, 2, 3


@pytest.fixture(autouse=True)
def sc():
    gr.set_gauge("sc")


def _runs(row):
    out, prev, n = [], int(row[0]), 0
    for v in row:
        if int(v) == prev:
            n += 1
        else:
            out.append(n)
            prev, n = int(v), 1
    out.append(n)
    return out


def test_twist_is_inch_true_and_corner_anchored():
    arr, period = twist.twist_strip_in(161, 14, horizontal=True, bg=BG, fg=FG)
    assert arr.shape == (14, 161) and abs(period - 4.0) < 1e-9
    v, period_v = twist.twist_strip_in(152, 12, horizontal=False, bg=BG, fg=FG)
    assert v.shape == (152, 12) and abs(period_v - 4.0) < 1e-9
    gold = arr == FG
    assert gold[:, 0].sum() <= 5 and gold[:, -1].sum() <= 5  # strands converge at both corners
    assert not gold[0].any() and not gold[-1].any()  # margin rows stay background


def test_solomon_and_corner_block_have_four_crossings():
    _, n = knots.solomon_knot(21, 24, BG, FG)
    assert n == 4
    blk, n = knots.corner_block(25, 28, BG, FG)
    assert n == 4 and (blk[0] == FG).all() and (blk[:, 0] == FG).all()


def test_woven_x_block_has_cross():
    blk = knots.woven_x_block(18, 20, BG, FG)
    assert blk[9, 9] == FG and blk[2, 9] == BG


def test_rings_interlock():
    arr, n = rings.rings(BG, FG)
    assert n == 2 and (arr == FG).sum() > 60


def test_thistles():
    big = thistle.thistle(BG, P2, P3)
    small = thistle.thistle_small(BG, P2, P3)
    assert big.shape == (34, 19) and small.shape == (25, 19)
    assert (big == P2).sum() > 60 and (small == P2).sum() >= 30
    scaled = thistle.thistle_scaled(6.0, BG, P2, P3)
    assert scaled.shape[0] == gr.rows(6.0)
    icon = thistle.bloom_icon(BG, P2, FG)
    assert (icon == P2).any() and (icon == FG).any()


def test_dragonfly_is_symmetric_and_amber_is_outlined():
    d = dragonfly.dragonfly(40, 48, BG, FG, P2, FG, span=7.0)
    assert np.array_equal(d, d[:, ::-1]) and (d == FG).sum() > 100
    a = dragonfly.amber_drop(36, 44, BG, P2, FG)
    assert a[22, 18] == P2 and (a == FG).sum() > 40


def test_stones_moon_clear_of_stones():
    s = stones.standing_stones(170, 56, BG, P2, FG, P3)
    assert (s == FG).sum() > 150 and (s == P3).sum() > 60 and (s == P2).sum() > 800
    assert not (gr.dilate(s == P3) & (s == FG)).any()


def test_plaid_min_run_two():
    a = plaid.plaid(120, 80, 0, 0, {"G": BG, "B": FG, "Y": P2, "R": P3})
    for row in list(a) + list(a.T):
        assert min(_runs(row)) >= 2


def test_stripe_band():
    b = bands.stripe_band(30, 6, [(BG, 2), (FG, 2), (P2, 2)])
    assert b.shape == (6, 30) and (b[0] == BG).all() and (b[2] == FG).all() and (b[5] == P2).all()
    assert bands.stripe_band(30, 6, [(BG, 2), (FG, 2), (P2, 2)], horizontal=False).shape == (30, 6)


def test_catalog_renders():
    assert len(CATALOG) >= 8
    for _name, fn in CATALOG:
        arr, rgb = fn()
        assert arr.ndim == 2 and len(rgb) > int(arr.max())
