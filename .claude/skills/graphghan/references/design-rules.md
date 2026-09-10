# Design rules (each with the reason it exists)

1. **No run shorter than 2 stitches** in plaid, bands, or frames. One-stitch runs double the color
   changes and look like noise in yarn. The plaid uses a priority rule (gold > red > blue > green)
   instead of twill hatching for exactly this reason; the sett rounds every stripe up to 2 cells.
2. **Lettering needs at least 11 rows per line**; a four-line quote gets 17 rows at sc and 12 at hdc.
   Below that, serifs and bowls collapse. Use the aspect-aware renderer (`graphghan.text.text_line`):
   it renders at 8× and box-filters to the cell aspect, so letters are not stretched at hdc.
   Metamorphous with `bold=0.035, threshold=0.42` is the proven face; true uncials break up.
3. **Words stay clear.** Nothing flanks a text line (mirrored dragonflies beside "and God!" read as
   mess); test that every text line's band across the panel holds only background and ink.
4. **Count changes per row.** Stitch counts mislead; a 244-wide plaid row at 40 changes is fine, a
   braid row at 120 is not. Report mean and busiest row for every option, and name what causes the peak.
5. **Interlace has handedness.** A two-strand twist is a screw thread: its mirror is the opposite
   twist, so a single strip can never be symmetric about its own middle. Make the *frame* symmetric
   (bottom = mirror of top, right = mirror of left) and say so. Anchor crossings to the corner edges
   with an odd number of half-periods so both ends of a strip look the same.
6. **Cells are not square.** sc cells are 0.29 in wide × 0.25 in tall. Draw in inches (`gr.cols`,
   `gr.rows`, inch-space masks) so circles are round on the blanket. The chart will still look
   slightly squatter along rows than along columns; that is the viewer, not the design.
7. **Discs clear silhouettes.** Place moons/suns relative to the hill top and beyond the last stone
   (`standing_stones` does this); assert `not (dilate(moon) & stones).any()` in the pattern tests.
8. **Prefer straight-edged motifs at hdc.** Knots and rings blur first when rows get tall; stones,
   text, bands, and dragonfly silhouettes survive.
9. **Simplify borders to cut rows, not the scene.** A braid strip is 3.5 in; a linked band is 2.5 in;
   the scene and the words are why the blanket exists.
10. **Hand-draw small things natively.** A thistle scaled down from a big bitmap turns into a cactus;
    draw a compact version at the target size (`thistle_small`).
11. **Show, then ask.** Options page with both gauges and numbers first; questions second. People
    choose from pictures and reject from numbers.
12. **Keep the finished design reproducible.** `render --check` must pass; if a motif changes,
    the pattern's tests and CHANGELOG change with it.
