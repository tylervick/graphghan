from pathlib import Path

import numpy as np
import pytest

from graphghan import grid as gr
from graphghan import validate
from graphghan.pattern import load_design, load_pattern

HERE = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="module")
def chart():
    meta = load_pattern(HERE)
    design = load_design(HERE)
    g, report = design.build("sc", "final")
    return g.a, report, meta


def test_dimensions_and_limits(chart):
    a, _, _ = chart
    assert a.shape == (184, 189)


def test_generic_invariants(chart):
    a, _, meta = chart
    failures = [(n, d) for n, ok, d in validate.run_all(a, meta) if not ok]
    assert failures == []


def test_five_colors_only(chart):
    a, _, meta = chart
    assert {meta.palette.codes[i] for i in validate.used_indices(a)} == {"C", "K", "G", "P", "Y"}


def test_frame_corner_squares_mirror(chart):
    a, _, _ = chart
    ex, ey, sx, sy = gr.cols(0.5), gr.rows(0.5), gr.cols(3.5), gr.rows(3.5)
    tl = a[ey : ey + sy, ex : ex + sx]
    assert np.array_equal(tl, a[ey : ey + sy, -ex - sx : -ex][:, ::-1])
    assert np.array_equal(tl, a[-ey - sy : -ey, ex : ex + sx][::-1, :])


def test_panel_and_outside(chart):
    a, rep, meta = chart
    C, K, G, P, Y = (meta.palette[c] for c in "CKGPY")
    x0, y0, x1, y1 = rep["panel"]
    panel = a[y0:y1, x0:x1]
    assert set(np.unique(panel).tolist()) <= {C, K, G, P, Y} and (panel == C).mean() > 0.6
    outside = a.copy()
    outside[y0:y1, x0:x1] = C
    assert not (outside == K).any() and not (outside == P).any()


def test_scene(chart):
    a, rep, meta = chart
    K, G, Y = (meta.palette[c] for c in "KGY")
    x0, y0, x1, y1 = rep["scene"]
    scene = a[y0:y1, x0:x1]
    assert (scene == K).sum() > 150 and (scene == Y).sum() > 60 and (scene == G).sum() > 800
    assert not (gr.dilate(scene == Y) & (scene == K)).any()


def test_text_lines_clear(chart):
    a, rep, meta = chart
    C, K = meta.palette["C"], meta.palette["K"]
    px0, _, px1, _ = rep["panel"]
    for _lx0, ly0, _lx1, ly1 in rep["text"]:
        assert set(np.unique(a[ly0:ly1, px0:px1]).tolist()) <= {C, K}


def test_thistles_and_dragonfly(chart):
    a, rep, meta = chart
    K, P = meta.palette["K"], meta.palette["P"]
    (lx0, ly0, lx1, ly1), (rx0, ry0, rx1, ry1) = rep["thistles"]
    assert (a[ly0:ly1, lx0:lx1] == P).sum() >= 30
    assert np.array_equal(a[ly0:ly1, lx0:lx1], a[ry0:ry1, rx0:rx1][:, ::-1])
    dx0, dy0, dx1, dy1 = rep["dragonfly"]
    assert (a[dy0:dy1, dx0:dx1] == K).sum() > 60 and abs((dx0 + dx1) / 2 - a.shape[1] / 2) <= 1


def test_variants_build():
    design = load_design(HERE)
    load_pattern(HERE)
    for name in design.VARIANTS:
        g, _ = design.build("sc", name)
        assert g.a.shape == (184, 189)
    g, _ = design.build("hdc", "final")
    assert g.a.shape == (115, 176)
