"""Craigh na Dun Blanket: standing stones, the quote, thistles, a dragonfly, braided gold border."""
from __future__ import annotations

from graphghan import Grid, palette
from graphghan import grid as gr
from graphghan.compose import text_block
from graphghan.frame import twist_frame
from graphghan.motifs import dragonfly, stones, thistle
from graphghan.text import FONT_METAMORPHOUS

PAL = palette.load(__file__)
C, K, G, P, Y = (PAL[c] for c in "CKGPY")

QUOTE = ["Lord, you gave me", "a rare woman,", "and God!", "I loved her well."]
TEXT_ROWS = {"sc": 17, "hdc": 12, "dc": 9}
TEXT_GAP = {"sc": 3, "hdc": 2, "dc": 1}
SIZE_IN = (54.0, 46.0)

VARIANTS = {
    "final": {"corners": "dot", "foot": "dragonfly"},
    "plain-foot": {"corners": "dot", "foot": "plain"},
    "solid-corners": {"corners": "solid", "foot": "dragonfly"},
    "cross-corners": {"corners": "cross", "foot": "dragonfly"},
}


def build(gauge_key: str = "sc", variant: str = "final"):
    opts = VARIANTS[variant]
    gr.set_gauge(gauge_key)
    W, H = gr.cols(SIZE_IN[0]), gr.rows(SIZE_IN[1])
    g = Grid(W, H, G)
    x0, y0, x1, y1 = twist_frame(g, W, H, G, Y, corners=opts["corners"])
    g.rect(x0, y0, x1, y1, C)
    cx = (x0 + x1) // 2
    size, pitch = TEXT_ROWS[gauge_key], TEXT_ROWS[gauge_key] + TEXT_GAP[gauge_key]
    text_h = 3 * pitch + size
    bottom_rows = gr.rows(6.5 if opts["foot"] == "dragonfly" else 6.0)
    gap = gr.rows(0.8)
    scene_h = max(gr.rows(9.0), min(gr.rows(14.0), (y1 - y0) - text_h - bottom_rows - 3 * gap))
    g.blit(stones.standing_stones(x1 - x0, scene_h, C, G, K, Y), x0, y0)
    text_top = y0 + scene_h + gap
    boxes = text_block(g, QUOTE, cx, text_top, size, pitch, FONT_METAMORPHOUS, K, C)
    text_bottom = text_top + text_h
    th = thistle.thistle_scaled(min(6.5, (y1 - gr.rows(0.4) - (text_bottom + gap)) * gr.SH), C, P, G)
    thh, thw = th.shape
    ty = y1 - gr.rows(0.4) - thh
    lx, rx = x0 + gr.cols(1.2), x1 - gr.cols(1.2) - thw
    g.blit(th, lx, ty, transparent=C)
    g.blit(th[:, ::-1], rx, ty, transparent=C)
    report = {"panel": (x0, y0, x1, y1), "scene": (x0, y0, x1, y0 + scene_h), "text": boxes,
              "text_bottom": text_bottom, "thistles": [(lx, ty, lx + thw, ty + thh), (rx, ty, rx + thw, ty + thh)]}
    if opts["foot"] == "dragonfly":
        span = 6.5
        dw, dh = gr.cols(span + 0.6), gr.rows(5.6)
        df = dragonfly.dragonfly(dw, dh, C, K, K, K, span=span)
        room = y1 - gr.rows(0.4) - (text_bottom + gap)
        if dh > room:
            df = df[(dh - room) // 2:(dh - room) // 2 + room]
        dy = y1 - gr.rows(0.4) - df.shape[0]
        g.blit(df, cx - dw // 2, dy, transparent=C)
        report["dragonfly"] = (cx - dw // 2, dy, cx - dw // 2 + dw, y1 - gr.rows(0.4))
    return g, report
