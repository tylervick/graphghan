"""Motif families. CATALOG renders a sample of each for the skill's thumbnails."""

from . import bands, dragonfly, knots, plaid, rings, stones, thistle, twist  # noqa: F401

SAMPLE_RGB = [
    (30, 77, 58),
    (217, 162, 27),
    (242, 232, 213),
    (43, 47, 51),
    (107, 45, 92),
    (31, 58, 147),
    (139, 30, 45),
]
G, Y, C, K, P, B, R = range(7)


def _catalog():
    return [
        ("twist-strip", lambda: (twist.twist_strip_in(70, 14, bg=G, fg=Y)[0], SAMPLE_RGB)),
        ("solomon-knot", lambda: (knots.corner_block(25, 28, G, Y)[0], SAMPLE_RGB)),
        ("woven-x", lambda: (knots.woven_x_block(18, 20, G, Y), SAMPLE_RGB)),
        ("rings", lambda: (rings.rings(C, Y)[0], SAMPLE_RGB)),
        ("thistle", lambda: (thistle.thistle(C, P, G), SAMPLE_RGB)),
        ("thistle-small", lambda: (thistle.thistle_small(C, P, G), SAMPLE_RGB)),
        ("bloom-icon", lambda: (thistle.bloom_icon(G, P, Y), SAMPLE_RGB)),
        ("dragonfly", lambda: (dragonfly.dragonfly(40, 48, Y, K, C, K), SAMPLE_RGB)),
        ("amber-drop", lambda: (dragonfly.amber_drop(36, 44, C, Y, K), SAMPLE_RGB)),
        ("standing-stones", lambda: (stones.standing_stones(120, 50, C, G, K, Y), SAMPLE_RGB)),
        ("plaid", lambda: (plaid.plaid(96, 64, 0, 0, {"G": G, "B": B, "Y": Y, "R": R}), SAMPLE_RGB)),
        (
            "stripe-band",
            lambda: (bands.stripe_band(60, 10, [(G, 2), (B, 2), (G, 2), (Y, 2), (G, 2)]), SAMPLE_RGB),
        ),
    ]


CATALOG = _catalog()
