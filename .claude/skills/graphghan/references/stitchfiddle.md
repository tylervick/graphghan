# Stitch Fiddle import

Use when the crocheter wants the chart inside Stitch Fiddle (stitchfiddle.com).

1. Charts → Create new chart → Craft: Crochet → Project: **Crochet colorwork** → pick any yarn list
   (or "My own colors"). Continuing past this step accepts their terms and needs an account; do that
   part yourself, not via automation.
2. **Import picture** → upload `patterns/<slug>/dist/chart.png` (one pixel per stitch, exactly N flat colors).
3. Number of colors = N (the palette length); stitches on the longest side = the chart width (or
   height if taller). With an exact-pixel image the import lands 1:1 with no color guessing.
4. Chart settings → Size → gauge proportions: enter the gauge (e.g. 14 st × 16 rows per 4 in) so the
   preview shows the finished shape.
5. Their "Written instructions" should match `written-rows.txt` row for row; a mismatch means the
   stitch count entered at import was wrong.

Limits: free accounts allow charts up to 300 × 300 stitches and 50 colors; Premium 1,000 × 1,000
and 200 colors. Formats: .png, .jpg, .gif. The importer picks colors automatically, which is why
you never upload a photo: reduce to the palette first.
