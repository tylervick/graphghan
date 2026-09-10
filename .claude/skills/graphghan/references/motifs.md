# Motif catalog

All functions take explicit palette indices and sizes in inches (cells via `gr.cols/gr.rows`).
Thumbnails are rendered at sc gauge, 10 px per stitch, by `graphghan catalog`.
Place a motif with `g.blit(arr, x, y, transparent=bg)`; fill rectangles with `g.rect(x0, y0, x1, y1, color)`;
both are `Grid` methods.

**Returns:** most motif functions return a bare array. Four return a tuple `(array, n)`: `twist_strip_in`
returns `(arr, period_in)`; `corner_block`, `solomon_knot`, and `rings` return `(arr, crossings)`.

| motif | call | use it for | notes |
|---|---|---|---|
| ![](../assets/twist-strip.png) twist strip | `motifs.twist.twist_strip_in(length, thick, horizontal, period_in=4.0, amp_in=1.0, radius_in=0.3, bg, fg, fit=True)` | braided border strips | inch-true; crossings every 2 in; fitted so a crossing lands on both corners; use through `frame.twist_frame` |
| ![](../assets/solomon-knot.png) corner block (Solomon's knot in a gold frame) | `motifs.knots.corner_block(w, h, bg, fg, outline=2)` | corner blocks ≥ 6 in | fg outline around a `solomon_knot`; blurs at hdc |
| Solomon's knot (bare) | `motifs.knots.solomon_knot(w, h, bg, fg, half=2.4, r_out=1.05, stroke=0.6)` | the interlaced rings alone, no outline frame | two interlaced stadium (oval) rings, one horizontal one vertical; `corner_block` wraps this with an outline |
| ![](../assets/woven-x.png) woven X | `motifs.knots.woven_x_block(w, h, bg, fg, outline=2, bar_in=0.6)` | saltire corners | reads at any gauge |
| ![](../assets/rings.png) rings | `motifs.rings.rings(bg, fg, r_in=1.1, r_out=1.75, gap_in=1.9)` | wedding rings on a panel | 2 crossings, left ring over at top |
| ![](../assets/thistle.png) thistle | `motifs.thistle.thistle(bg, head, leaf)` | 8.5 in tall thistle (19 × 34 cells at sc) | hand-drawn; scale only via `thistle_scaled` |
| ![](../assets/thistle-small.png) thistle, compact | `motifs.thistle.thistle_small(bg, head, leaf)` | ≤ 6.5 in thistles | native small drawing; `thistle_scaled` picks it under 7 in |
| ![](../assets/bloom-icon.png) bloom icon | `motifs.thistle.bloom_icon(bg, head, calyx)` | a thistle in each link of a linked band | 4 × 4 cells at sc |
| ![](../assets/dragonfly.png) dragonfly | `motifs.dragonfly.dragonfly(w, h, bg, body, wing_fill, wing_line, span=7.0, cx=None, cy=None)` | dragonfly silhouettes/outlines | solid wings (`wing_fill == wing_line`) read best under 6 in; `cx`/`cy` default to the canvas centre, pass cell coordinates to override |
| ![](../assets/amber-drop.png) amber drop | `motifs.dragonfly.amber_drop(w, h, bg, fill, line, a=4.3, b=4.9, edge=0.42)` | the "dragonfly in amber" emblem | blit the dragonfly onto it with `bg` = the drop's fill |
| ![](../assets/standing-stones.png) standing stones | `motifs.stones.standing_stones(w, h, bg, hill, stone, moon)` | Craigh na Dun scene across a panel | moon placed clear of stones; needs ≥ 9 in height |
| ![](../assets/plaid.png) plaid | `motifs.plaid.plaid(w, h, phase_x, phase_y, colors, sett=SETT_DEFAULT, priority=("Y", "R", "B", "G"))` | tartan-colored grounds | `colors` is required: a dict mapping sett code → palette index, e.g. `{"G": G, "B": B, "Y": Y, "R": R}`; `sett` is `[(code, inches), ...]`; priority rule, min 2-stitch stripes; busy: ~40 changes per full row |
| ![](../assets/stripe-band.png) stripe band | `motifs.bands.stripe_band(length, thick, seq, horizontal)` | zero-change frame bands | seq = [(color, cells), …] |

Frames (`graphghan.frame`): `twist_frame(g, W, H, bg, fg, edge_in=0.5, strip_in=3.5, corners="dot"|"solid"|"cross", margin_in=0.75)`
and `link_frame(g, W, H, ground, rail, bloom, calyx, edge_color, ...)`; both return the panel rect.
Lettering: `compose.text_block(g, lines, x_center, y_top, size, pitch, font_path, color, bg, bold=0.035, threshold=0.42)`
returns the per-line `(x0, y0, x1, y1)` boxes that become `report["text"]`.
