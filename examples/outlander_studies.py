"""Option studies from the Outlander blanket project, kept as worked examples of the motifs."""

from __future__ import annotations

from graphghan import Grid
from graphghan import grid as gr
from graphghan.compose import text_block
from graphghan.frame import link_frame, twist_frame
from graphghan.motifs import dragonfly, knots, plaid, rings, stones, thistle, twist
from graphghan.palette import Color, Palette
from graphghan.text import FONT_METAMORPHOUS

PAL = Palette(
    [
        Color("C", "Cream", (242, 232, 213)),
        Color("K", "Charcoal", (43, 47, 51)),
        Color("G", "Deep Green", (30, 77, 58)),
        Color("P", "Purple", (107, 45, 92)),
        Color("B", "Royal Blue", (31, 58, 147)),
        Color("R", "Burgundy", (139, 30, 45)),
        Color("Y", "Gold", (217, 162, 27)),
    ]
)
C, K, G, P, B, R, Y = (PAL[c] for c in "CKGPBRY")
QUOTE = ["Lord, you gave me", "a rare woman,", "and God!", "I loved her well."]
TEXT_ROWS = {"sc": 17, "hdc": 12}
TEXT_GAP = {"sc": 3, "hdc": 2}


def _text(g, cx, top, gauge):
    size, pitch = TEXT_ROWS[gauge], TEXT_ROWS[gauge] + TEXT_GAP[gauge]
    return text_block(g, QUOTE, cx, top, size, pitch, FONT_METAMORPHOUS, K, C), 3 * pitch + size


def dragonfly_in_amber(gauge="sc"):
    gr.set_gauge(gauge)
    W, H = gr.cols(50.0), gr.rows(49.0)
    g = Grid(W, H, G)
    x0, y0, x1, y1 = twist_frame(g, W, H, G, Y, corners="dot", margin_in=0.25)
    g.rect(x0, y0, x1, y1, C)
    cx = (x0 + x1) // 2
    aw, ah = gr.cols(11.0), gr.rows(11.8)
    amber = dragonfly.amber_drop(aw, ah, C, Y, K, a=5.1, b=5.6)
    df = dragonfly.dragonfly(aw, ah, Y, K, C, K, span=8.0)
    amber[df != Y] = df[df != Y]
    ay, ax = y0 + gr.rows(0.6), cx - aw // 2
    g.blit(amber, ax, ay)
    th = thistle.thistle_scaled(8.5, C, P, G)
    thh, thw = th.shape
    ty, tx = ay + (ah - thh) // 2, ax - gr.cols(1.2) - thw
    g.blit(th, tx, ty, transparent=C)
    g.blit(th[:, ::-1], x1 - (tx - x0) - thw, ty, transparent=C)
    boxes, text_h = _text(g, cx, ay + ah + gr.rows(1.0), gauge)
    room = y1 - gr.rows(0.5) - (ay + ah + gr.rows(1.0) + text_h + gr.rows(0.6))
    knot_in = min(6.5, room * gr.SH)
    if knot_in >= 2.5:
        kw, kh = gr.cols(knot_in), gr.rows(knot_in)
        s = knot_in / 5.0
        knot, _ = knots.solomon_knot(
            kw, kh, C, Y, half=2.4 * s, r_out=1.05 * s, stroke=0.6 * s if s > 0.8 else 0.5
        )
        g.blit(knot, cx - kw // 2, y1 - gr.rows(0.5) - kh)
    return g, {"panel": (x0, y0, x1, y1), "text": boxes}


def highland_tartan(gauge="sc"):
    gr.set_gauge(gauge)
    W, H = gr.cols(56.0), gr.rows(48.0)
    g = Grid(W, H, G)
    ex, ey = gr.cols(0.5), gr.rows(0.5)
    px, py = gr.cols(2.75), gr.rows(2.75)
    sx, sy = gr.cols(3.5), gr.rows(3.5)
    qx, qy = gr.cols(2.0), gr.rows(2.0)
    gx, gy = gr.cols(0.75), gr.rows(0.75)
    g.blit(plaid.plaid(W, H, 0, 0, {"G": G, "B": B, "Y": Y, "R": R}), 0, 0)
    g.rect(0, 0, W, ey, Y)
    g.rect(0, H - ey, W, H, Y)
    g.rect(0, 0, ex, H, Y)
    g.rect(W - ex, 0, W, H, Y)
    tx0, ty0 = ex + px, ey + py
    top, _ = twist.twist_strip_in(W - 2 * tx0, sy - 2, horizontal=True, bg=G, fg=Y)
    for yy in (ty0, H - ty0 - sy):
        g.rect(tx0, yy, W - tx0, yy + sy, Y)
        g.blit(top, tx0, yy + 1)
    side, _ = twist.twist_strip_in(H - 2 * ty0, sx - 2, horizontal=False, bg=G, fg=Y)
    for xx in (tx0, W - tx0 - sx):
        g.rect(xx, ty0, xx + sx, H - ty0, Y)
        g.blit(side, xx + 1, ty0)
    cw, chh = gr.cols(6.0), gr.rows(6.0)
    bx, by = int(round(tx0 + sx / 2.0 - cw / 2.0)), int(round(ty0 + sy / 2.0 - chh / 2.0))
    block, _ = knots.corner_block(cw, chh, G, Y)
    for xx in (bx, W - bx - cw):
        for yy in (by, H - by - chh):
            g.blit(block, xx, yy)
    mx, my = tx0 + sx + qx, ty0 + sy + qy
    g.rect(mx, my, W - mx, H - my, G)
    x0, y0, x1, y1 = mx + gx, my + gy, W - mx - gx, H - my - gy
    g.rect(x0, y0, x1, y1, C)
    cx = (x0 + x1) // 2
    boxes, text_h = _text(g, cx, y0 + gr.rows(0.8), gauge)
    ring, _ = rings.rings(C, Y)
    rh, rw = ring.shape
    g.blit(ring, cx - rw // 2, y1 - gr.rows(0.5) - rh)
    return g, {"panel": (x0, y0, x1, y1), "text": boxes}


def link_border(gauge="sc"):
    gr.set_gauge(gauge)
    W, H = gr.cols(54.0), gr.rows(46.0)
    g = Grid(W, H, G)
    x0, y0, x1, y1 = link_frame(g, W, H, G, Y, P, Y, R)
    g.rect(x0, y0, x1, y1, C)
    cx = (x0 + x1) // 2
    scene_h = gr.rows(12.0)
    g.blit(stones.standing_stones(x1 - x0, scene_h, C, G, K, Y), x0, y0)
    boxes, _ = _text(g, cx, y0 + scene_h + gr.rows(0.8), gauge)
    return g, {"panel": (x0, y0, x1, y1), "text": boxes}


STUDIES = {
    "dragonfly-in-amber": dragonfly_in_amber,
    "highland-tartan": highland_tartan,
    "link-border": link_border,
}
