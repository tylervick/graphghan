"""Border frames. Each paints into a Grid and returns the inner (cream panel) rect."""

from __future__ import annotations

from . import grid as gr
from .motifs import knots, thistle, twist


def twist_frame(g, W, H, bg, fg, edge_in=0.5, strip_in=3.5, corners="dot", margin_in=0.75):
    """Edge line in `fg`, inch-true braided twist (`fg` on `bg`) all round, inner `fg` line, `bg` margin.
    corners: "solid" (fg squares), "dot" (fg square, bg inset, fg dot), "cross" (bigger woven-X blocks)."""
    ex, ey = gr.cols(edge_in), gr.rows(edge_in)
    sx, sy = gr.cols(strip_in), gr.rows(strip_in)
    mx, my = gr.cols(margin_in), gr.rows(margin_in)
    g.rect(0, 0, W, H, fg)
    g.rect(ex, ey, W - ex, H - ey, bg)
    if corners == "cross":
        bw, bh, cx0, cy0 = ex + sx + 1 + mx, ey + sy + 1 + my, 0, 0
    else:
        bw, bh, cx0, cy0 = sx, sy, ex, ey
    top, _ = twist.twist_strip_in(W - 2 * (cx0 + bw), sy, horizontal=True, bg=bg, fg=fg)
    g.blit(top, cx0 + bw, ey)
    g.blit(top[::-1, :], cx0 + bw, H - ey - sy)
    side, _ = twist.twist_strip_in(H - 2 * (cy0 + bh), sx, horizontal=False, bg=bg, fg=fg)
    g.blit(side, ex, cy0 + bh)
    g.blit(side[:, ::-1], W - ex - sx, cy0 + bh)
    ix, iy = ex + sx, ey + sy
    g.rect(ix, iy, W - ix, H - iy, fg)
    g.rect(ix + 1, iy + 1, W - ix - 1, H - iy - 1, bg)
    for bx, h_flip in ((cx0, False), (W - cx0 - bw, True)):
        for by, v_flip in ((cy0, False), (H - cy0 - bh, True)):
            if corners == "cross":
                block = knots.woven_x_block(bw, bh, bg, fg)
                if h_flip:
                    block = block[:, ::-1]
                if v_flip:
                    block = block[::-1, :]
                g.blit(block, bx, by)
            elif corners == "dot":
                g.rect(bx, by, bx + bw, by + bh, fg)
                g.rect(bx + 2, by + 2, bx + bw - 2, by + bh - 2, bg)
                g.rect(bx + bw // 2 - 1, by + bh // 2 - 1, bx + bw // 2 + 1, by + bh // 2 + 1, fg)
            else:
                g.rect(bx, by, bx + bw, by + bh, fg)
    px0, py0 = ix + 1 + mx, iy + 1 + my
    return px0, py0, W - px0, H - py0


def link_frame(
    g, W, H, ground, rail, bloom, calyx, edge_color, edge_in=0.5, band_in=2.5, link_in=5.0, margin_in=0.5
):
    """A band of linked rectangles: `rail` rails and dividers on `ground`, a thistle bloom in every link."""
    ex, ey = gr.cols(edge_in), gr.rows(edge_in)
    bx, by = gr.cols(band_in), gr.rows(band_in)
    rx, ry = gr.cols(0.5), gr.rows(0.5)
    g.rect(0, 0, W, H, edge_color)
    g.rect(ex, ey, W - ex, H - ey, ground)
    for x0, y0, x1, y1 in (
        (ex, ey, W - ex, H - ey),
        (ex + bx - rx, ey + by - ry, W - ex - bx + rx, H - ey - by + ry),
    ):
        g.rect(x0, y0, x1, y0 + ry, rail)
        g.rect(x0, y1 - ry, x1, y1, rail)
        g.rect(x0, y0, x0 + rx, y1, rail)
        g.rect(x1 - rx, y0, x1, y1, rail)
    icon = thistle.bloom_icon(ground, bloom, calyx)
    ih, iw = icon.shape
    for y0 in (ey, H - ey - by):
        cy = (y0 + ry + y0 + by - ry) // 2
        x_start, x_end = ex + bx, W - ex - bx
        n = max(1, int(round((x_end - x_start) * gr.SW / link_in)))
        step = (x_end - x_start) / n
        g.rect(x_start - rx, y0, x_start, y0 + by, rail)
        g.rect(x_end, y0, x_end + rx, y0 + by, rail)
        for i in range(1, n):
            xx = int(round(x_start + i * step))
            g.rect(xx - rx // 2, y0, xx - rx // 2 + rx, y0 + by, rail)
        for i in range(n):
            cx = int(round(x_start + (i + 0.5) * step))
            g.blit(icon, cx - iw // 2, cy - ih // 2)
    for x0 in (ex, W - ex - bx):
        cx = (x0 + rx + x0 + bx - rx) // 2
        y_start, y_end = ey + by, H - ey - by
        n = max(1, int(round((y_end - y_start) * gr.SH / link_in)))
        step = (y_end - y_start) / n
        g.rect(x0, y_start - ry, x0 + bx, y_start, rail)
        g.rect(x0, y_end, x0 + bx, y_end + ry, rail)
        for i in range(1, n):
            yy = int(round(y_start + i * step))
            g.rect(x0, yy - ry // 2, x0 + bx, yy - ry // 2 + ry, rail)
        for i in range(n):
            cy = int(round(y_start + (i + 0.5) * step))
            g.blit(icon, cx - iw // 2, cy - ih // 2)
    for cx0 in (ex, W - ex - bx):
        for cy0 in (ey, H - ey - by):
            g.blit(icon, cx0 + bx // 2 - iw // 2, cy0 + by // 2 - ih // 2)
    mx, my = ex + bx + gr.cols(margin_in), ey + by + gr.rows(margin_in)
    return mx, my, W - mx, H - my
