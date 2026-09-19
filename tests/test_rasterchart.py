"""The raster grid reader on images drawn here: no PDF, no real pattern."""

import numpy as np
import pytest
from PIL import Image, ImageDraw

from graphghan import rasterchart as rc

PALETTE = ["#f2e8d5", "#2b2f33", "#1e4d3a", "#d9a21b"]
RGB = [tuple(int(h[i : i + 2], 16) for i in (1, 3, 5)) for h in PALETTE]


def pattern(w, h):
    rng = np.random.default_rng(w * 1000 + h)
    a = rng.integers(0, len(PALETTE), size=(h, w))
    a[:, :3] = 1  # a solid stripe of the line-coloured cells, where lines hide
    a[-2:, :] = 3
    return a


def draw_chart(a, cell=24, origin=(80, 60), numbers=True, symbols=False, bold_every=10, line=(140, 140, 140)):
    h, w = a.shape
    ox, oy = origin
    img = Image.new("RGB", (ox * 2 + w * cell, oy * 2 + h * cell), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for y in range(h):
        for x in range(w):
            d.rectangle(
                [ox + x * cell, oy + y * cell, ox + (x + 1) * cell, oy + (y + 1) * cell], fill=RGB[a[y, x]]
            )
            if symbols and (x + y) % 3 == 0:
                cx, cy = ox + (x + 0.5) * cell, oy + (y + 0.5) * cell
                d.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], outline=(0, 0, 0), width=2)
    for x in range(w + 1):
        bold = (w - x) % bold_every == 0
        d.line(
            [(ox + x * cell, oy), (ox + x * cell, oy + h * cell)],
            fill=(0, 0, 0) if bold else line,
            width=3 if bold else 1,
        )
    for y in range(h + 1):
        bold = (h - y) % bold_every == 0
        d.line(
            [(ox, oy + y * cell), (ox + w * cell, oy + y * cell)],
            fill=(0, 0, 0) if bold else line,
            width=3 if bold else 1,
        )
    if numbers:
        for x in range(w):
            d.text((ox + x * cell + 6, oy - 14), str(w - x), fill=(0, 0, 0))
        for y in range(h):
            d.text((ox - 24, oy + y * cell + 6), str(h - y), fill=(0, 0, 0))
    return img


def test_one_grid_with_bold_lines_numbers_and_a_hidden_stripe():
    a = pattern(37, 29)
    img = draw_chart(a)
    regions = rc.find_regions(img)
    assert len(regions) == 1
    r = regions[0]
    assert (r.cols, r.rows) == (37, 29)
    assert abs(r.pitch[0] - 24) < 0.5 and abs(r.pitch[1] - 24) < 0.5
    samples = rc.read_region(img, r)
    idx = rc.snap_to_palette(samples, PALETTE)
    assert np.array_equal(idx, a)


def test_two_grids_side_by_side_are_two_regions():
    left, right = pattern(12, 20), pattern(15, 20)
    a = draw_chart(left)
    b = draw_chart(right)
    img = Image.new("RGB", (a.width + b.width, a.height), (255, 255, 255))
    img.paste(a, (0, 0))
    img.paste(b, (a.width, 0))
    regions = rc.find_regions(img)
    assert sorted((r.cols, r.rows) for r in regions) == [(12, 20), (15, 20)]
    for r in regions:
        want = left if r.cols == 12 else right
        assert np.array_equal(rc.snap_to_palette(rc.read_region(img, r), PALETTE), want)


def test_symbols_over_colour_are_ignored():
    a = pattern(16, 12)
    img = draw_chart(a, cell=32, symbols=True)
    (r,) = rc.find_regions(img)
    assert np.array_equal(rc.snap_to_palette(rc.read_region(img, r), PALETTE), a)


def test_a_page_of_text_has_no_grid():
    img = Image.new("RGB", (800, 1000), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for i in range(50):
        d.text(
            (40, 20 + i * 19),
            "Row %d: ch 1, turn, 8 A, 14 B, 8 A (30 sts) and more words here" % i,
            fill=(0, 0, 0),
        )
    assert rc.find_regions(img) == []


def test_a_photo_is_not_a_chart():
    rng = np.random.default_rng(1)
    noise = rng.integers(0, 255, size=(600, 600, 3), dtype=np.uint8)
    img = Image.fromarray(noise)
    d = ImageDraw.Draw(img)
    for k in range(0, 600, 30):  # a fence of lines over the noise
        d.line([(k, 0), (k, 599)], fill=(0, 0, 0), width=2)
        d.line([(0, k), (599, k)], fill=(0, 0, 0), width=2)
    assert rc.find_regions(img) == []


def test_cells_override_must_agree_with_the_lines():
    a = pattern(20, 10)
    img = draw_chart(a)
    (r,) = rc.find_regions(img)
    assert rc.read_region(img, r, cells=(20, 10)).shape == (10, 20, 3)
    with pytest.raises(ValueError, match="--cells 30x10"):
        rc.read_region(img, r, cells=(30, 10))


def test_snap_refuses_a_foreign_colour_by_cell():
    samples = np.zeros((2, 3, 3), dtype=np.uint8)
    samples[:, :] = RGB[0]
    samples[1, 2] = (255, 0, 255)
    with pytest.raises(ValueError, match=r"column 3, row 2"):
        rc.snap_to_palette(samples, PALETTE)


def test_cluster_orders_codes_by_frequency_and_flags_bleed():
    a = pattern(30, 30)
    a[:, :] = 0
    a[:10, :] = 2
    a[0, 0] = 1  # a single stray cell
    samples = np.array(RGB, dtype=np.uint8)[a]
    idx, hexes, warnings = rc.cluster_palette(samples)
    assert hexes[0] == PALETTE[0] and hexes[1] == PALETTE[2] and hexes[2] == PALETTE[1]
    assert np.array_equal(idx == 0, a == 0) and np.array_equal(idx == 1, a == 2)
    assert warnings and "1 cell" in warnings[0]


def test_colour_names():
    assert rc.name_colour("#d9a21b") == "gold" and rc.name_colour("#ffffff") == "white"
