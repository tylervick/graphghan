# Tool teardowns (RQ4): what existing tools store, and how they interoperate

Date: 2026-09-12, Stitch Fiddle and Crochetpop driven 2026-09-14 on Tyler's free accounts.
Method: public documentation, manuals, product pages, and — where marked "driven" — the tool
itself, read-only apart from one empty test chart left in the Stitch Fiddle account.

## Stitch Fiddle (driven; chart maker, web)

The crochet chart wizard's first question is the genre, and its list is an independent
statement of the axes that matter to a chart tool:

- Corner 2 corner crochet (C2C)
- Crochet colorwork
- Filet crochet
- Overlay mosaic crochet
- Free form
- Tunisian crochet colorwork
- Tunisian crochet with return pass
- Other: chart with general crochet stitch symbols

That is our representability matrix from a different direction. Tunisian appears twice —
"colorwork" (one cell one stitch) versus "with return pass" (two passes per row) — which is
exactly the passes-per-grid-row axis. Filet and C2C are separate because a cell is not a stitch.
Overlay mosaic is separate because a cell carries a stitch type.

**Driven (2026-09-12), wizard for "Crochet colorwork":**

- The wizard's own descriptions: C2C — "Crochet colorwork in diagonal direction, e.g. 2 or 3
  hdc/dc stitches" (tile cardinality is a *choice*, 2 or 3); Crochet colorwork — "graphgan,
  pixel crochet, picture crochet, tunisian colorwork, tapestry"; Overlay mosaic — "One color for
  one row and change color every row, starting on same side each time"; Tunisian with return
  pass — "Single color / chart with symbols only / with return pass".
- **Yarn step**: the palette is a *yarn line* with its colourways (Bernat Super Value 49
  colours, Caron One Pound 43, Red Heart Super Saver 64, Scheepjes Catona 150, Stylecraft Special
  DK 120 …) or "My own colors". So a chart's palette is brand + line + colourway — the same
  three fields our `palette[].yarn` carries.
- **How to start**: Empty · From picture · Create QR code · **.oxs (MacStitch / WinStitch)** ·
  **PNG pattern (1px)**. Those two imports are exactly our two exports (`graphghan export
  --format oxs|png`). Our charts already round-trip into the most-used chart tool.
- **Grid size**: width × height in stitches, with the stitch count shown (w×h — the same
  one-cell-one-stitch assumption, applied here to a genre where it holds).
- **Gauge**: "make a sample swatch … of 4 inch by 4 inch; how many horizontal stitches in 4
  inches; how many vertical stitches (rows) in 4 inches", inches or centimetres. Field for field
  our `gauge.stitches / rows / over {value, unit}` (claim 14, fourth independent source).

**Driven (2026-09-14), the editor itself** — an empty 20 × 20 "Crochet colorwork" chart on
Stylecraft Special DK, free tier (15 charts):

- **Craft comes first.** The home page asks "Choose your craft" before anything else: Crochet,
  Cross stitch, Knitting, Diamond painting, Fuse beads, Pixel macrame, Latch hook, Quilt,
  Pixelhobby, Pixel art / other. Chart settings carry `Craft: Crochet` and the project kind as
  two dropdowns. Fifth independent source for `pattern.craft` (#49).
- **Direction is a three-part setting**, identical in the chart settings and the progress
  tracker: *Project* (top/down · diagonal · left/right), *Direction* (bottom-to-top ·
  top-to-bottom), *Work* (always ← · always → · alternating starting right-to-left (RS) ·
  alternating starting left-to-right), with an animated "S = start of work" example. That is
  our `technique.start / first_side / rs_direction / turn` with one extra value we lack:
  **always one direction** — the mosaic / rejoin case. `boundary.kind: rejoin` is that value.
- **Nothing about a turning chain anywhere.** Not in settings, not in the tracker, not in the
  written export. The chart tool most graphghan makers design in has no field for it, which is
  why the number reaches the maker only through the designer's prose.
- **Written instructions (Premium)** are, in the gate's own example, colour runs and counts
  only: "Row 3: (Red) x 2, Blue (3 stitches)" — no stitch, no chain, no foundation. The most-
  used chart tool's text export is exactly our `written-rows.txt` *before* Phase 1. What Phase 1
  adds (chain, turn, stitch, foundation) is what Crochetpop's generator prints and Stitch
  Fiddle's does not.
- **Progress tracker** (free): *Track full rows · Track row stitch-by-stitch · Track row by
  group of stitches* — three cursor granularities, the third being our run; a position counter
  with ↑ ↓; darken all except the current row; auto-scroll; "move to start of row
  automatically"; click-to-set vs click-to-advance. Row numbers alternate sides (odd right, even
  left). This is the Work screen's model drawn by someone else: row, run, stitch.
- **Download types**: png, jpg, gif, pdf, docx, odt, xlsx, **png (1 px pattern)**, **oxs**, svg,
  eps, wmf, emf. Both of our exports are also its exports, so the round-trip is symmetric.
  Layout options: legend before/after chart, grid lines, paper, margins (Premium).
- **Versioning**: "Backups (previous versions)" per chart and a *Check for updates* action —
  "The software and the chart are on the latest version" — so a shared chart can change under a
  follower, the same problem `ProjectService.versionNotice` answers.
- Gauge in the editor is a per-yarn preset or "(none)"; the wizard's swatch dialog stays the
  only place gauge is entered.

## Crochetpop (driven; chart + written-instruction generator, web)

Stores designs in the browser, a free account syncs them. Export is **SVG of the chart**, Print,
and "Save as PDF" — no data format. Driven 2026-09-14 through the pattern library's *work* view
(the generated rows, with the walkthrough advanced two rows) and the lesson walkthroughs.

- **"One source design exports to four grid techniques"** — filet, SC pixel, C2C ("diagonal
  blocks of 3 double crochets"), granny pixel — "the underlying grid stays the same" and "the
  tool recalculates gauge and stitch counts". Its FAQ gives the size consequence outright:
  "50×50 cells finishes about 12.5 × 10 in worked in single crochet, and 40 × 40 in worked
  corner-to-corner." That is the chart-is-technique-agnostic finding (RQ3), the non-square sc
  cell, and the `gauge.unit` problem (#48) in one paragraph.
- **The generated rows put the chain at the start of the row, with "counts as", and key it on
  the first cell.** Filet Rose, verbatim: "Foundation: Ch 89" · "Row 1: 1 dc in 8th ch from hook
  (3 ch = 1st dc, 2 ch = 1st space, sk 2 ch). (ch 2, sk 2 ch, 1 dc in next ch) × 27. (28 sp, 85
  sts)" · "Row 2: Ch 5 (counts as dc + first sp), turn. sk 2 sts, 1 dc in next st …". The ch 5 is
  ch 3 for the dc plus ch 2 for the space the next row opens with — the filet rule from
  `genres/filet.md`, implemented by a generator. The DC washcloth lesson prints "R2: Ch 3 (counts
  as first dc), 9 dc (10)" and teaches the skill under the name **"Turning Chain Counts as
  Stitch"** — our field, as a beginner lesson title.
- **Rounds**: the granny square prints "Ch 3 (counts as first dc) … Join with sl st to top of
  beg ch-3" (`boundary.kind: join`); the flat coaster prints "R2 [Color B] inc 6 (12)" with no
  boundary text at all (`spiral`); the hand-written heart says "do not turn, right side facing"
  and joins with "Sl st to the top of the beginning ch-3". Three kinds, one generator (#43).
- **Per-row stitch counts as checkpoints**: every row ends "(85 sts)"; the work view says
  "Checkpoint — count this row before Row Done. Expect 85 sts" and "Whole row · 85 sts · running
  85 / 85 ✓", with "Work right → left (right side)" / "Work left → right (wrong side)" per row,
  "row 2 above = next · rows below = just worked", a "Work in sections" splitter, Row/Stitch
  ± steppers, notes, "Pin current stitch", and an Audio Mode. The stitch-math check is a
  validator rule worth borrowing for shaped rows (#37); the direction line per row is ours.
- **Colour per row in brackets** — "[Color A] 6 sc in ring" — and a colour legend that maps
  Color A/B/C to hexes: the palette-role idea from #34, in the generated text.
- Abbreviation keys carry both systems inline: "sc — single crochet (UK: double crochet)" —
  the `terms_also` case (#49) as practised by a generator that never asks which system you use.
- Stitch charts use standard crochet symbols and draw the turning chain as a column of chain
  ovals at the alternating row start, so **in symbol-chart form the turning chain is visible;
  in a colour grid it is not** — the gap Phase 1 fills for grid charts.

## Stitchmastery (read; knitting chart editor, desktop — manual v2015)

Native file is `.knit` (proprietary). The key holds entries for **stitch types, yarns (colours)
and borders** — three legend classes in one key, which is a cleaner statement of what a chart
legend is than ours. Exports chart images, and written instructions as plain TXT only, driven by
"stylesheets" that control phrasing; "Include colour in written instructions" is an option. It
also goes the other way: File > New Chart Diagram from Written Instructions.

**For us:** written-instruction output is a first-class, styled artifact, not an afterthought;
and the reverse direction (text to chart) is how a knitter without a chart tool would enter a
pattern. Neither direction has a public format; TXT out is the interchange.

## Pattern Keeper (read; PDF chart marker, mobile)

Reads designers' PDF charts and lets the stitcher mark progress, park threads and search for
symbols. Automatic grid detection "often fails"; the user edits grid rectangles by hand, tells
it about page overlaps and duplicate charts, and picks a chart size. Image-based charts are not
searchable. Backstitch and fractional stitches unsupported. It maintains a list of "supported
designers" — compatibility is per vendor.

Ursa Software (MacStitch/WinStitch) ships an **"Export to PDF for Pattern Keeper"** option
which sets: TrueType symbols; clear grid lines; symbols not too small; key with "Number" and
"Name" column headings; key never word-wrapped; a Blend column when blends exist; and embedded
hints about which pages carry the chart.

**For us:** this is the most important interoperability finding in the teardowns. In cross-
stitch, the working-app-to-chart-tool interface is not a data format; it is a **PDF layout
convention negotiated between two vendors**, with a per-designer compatibility list. That is the
failure mode a real interchange format exists to prevent, and the reason Pattern Keeper users
still need OXS-aware tools. It is also the strongest argument for G3: the demand for a parseable
chart is proven by people reverse-engineering PDFs to get one.

## Lion Brand (read; catalogue taxonomy from the Shopify product JSON)

Every pattern carries structured tags: `pattern-craft_Crochet`, `pattern-skill-level_Level 2 -
Easy (Beginner+)`, `pattern-yarn-weight_6 Super Bulky`, `project-type_Afghan/Blanket`,
`made-for_Baby`, `fiber_Acrylic`, `yarn-used_Hometown - 135`, `pattern-type_Paid`. Skill level
is a four-level scale with their own labels ("Level 2 - Easy (Beginner+)"), yarn weight uses the
CYC number and name. This is a large publisher's catalogue vocabulary for RQ2; it aligns with
CYC on yarn weight and diverges on skill-level labels.

## DMC (driven 2026-09-14; catalogue taxonomy and pattern delivery)

The pattern catalogue (2,243 free and paid patterns) filters on **Craft** — Embroidery 1,057 ·
Cross Stitch 705 · Crochet 170 · Craft 162 · Punch Needle 61 · Tapestry and needlepoint 19 ·
Knitting 13 · Macrame 12 · Felting 5 — and **Level**: Intermediate 1,251 · Easy 639 · Beginner
192 · Advanced 122. Craft first, again (#49). The level scale is four steps with its own labels
and ordering (Beginner below Easy), a third labelling of the same idea after CYC's
Basic/Easy/Intermediate/Complex and Lion Brand's "Level 2 - Easy (Beginner+)" (#33: store the
publisher's label, map to CYC only when the publisher does).

Delivery: a free pattern is a **$0 cart checkout** ("Pattern Only — Free" / "Add thread —
$13.80 … Make it a Kit"), after which the PDF sits in the account's downloads; there is no
direct PDF URL (the legacy `/media/.../patterns/pdf/<SKU>.pdf` path redirects). The pattern
*is* a product with a SKU (`PAT2174`) and the kit is the pattern plus "pre-calculated shades and
quantities of thread" — DMC sells the yarn-amounts table (#34) as the upsell. Cross-stitch
corpus rows from DMC wait on Tyler running that checkout (`docs/research/log.md`).

## knitCompanion (read; PDF-based project keeper, mobile)

Works from the designer's PDF, not from a chart model. Per project it keeps: row and stitch
markers (with width, colour, transparency), up to six simple counters plus linked and "smart"
counters (name, direction, min/max), colour highlights per page, text and audio notes per page,
project notes, a timer, ruler measurements and video links. Imports PDFs from anywhere and
images converted to PDF; "kCDesigns" are pre-configured PDFs sold by the vendor. Exports are
whole projects (`.kc`) to cloud storage or other apps — a backup, not an interchange. No shared
format.

**For us:** the most-used working app for knitters stores *annotations on a PDF*: counters,
markers, highlights. Its "one-tap markers" for charted patterns is the closest thing to our
cursor. Everything it knows about the pattern it learned by the user drawing rectangles on a
page. Same conclusion as Pattern Keeper: the working-app layer runs on PDFs because there is no
data to run on.

## Pending

- Chart Minder (429 on fetch; retry).
- DMC cross-stitch PDFs for the corpus (five or so): need a $0 "Pattern Only" checkout per
  pattern in Tyler's account, then the files from his downloads into `corpus/raw/`.
- Row-counter apps (top three by installs): what per-project state they keep.
