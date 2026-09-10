from graphghan import Grid, palette
from graphghan import grid as gr

PAL = palette.load(__file__)
VARIANTS = {"final": {}}


def build(gauge_key="sc", variant="final"):
    gr.set_gauge(gauge_key)
    W, H = gr.cols(4.0), gr.rows(3.0)
    g = Grid(W, H, PAL["A"])
    g.rect(2, 2, W - 2, H - 2, PAL["B"])
    return g, {"panel": (2, 2, W - 2, H - 2)}
