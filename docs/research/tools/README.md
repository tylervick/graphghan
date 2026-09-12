# Tool teardowns (RQ4): what existing tools store, and how they interoperate

Date: 2026-09-12. Method: public documentation, manuals, and product pages. "Used" means the
tool was driven; "read" means documentation only. Chrome access to several tool sites is pending
extension permissions, so most entries are "read" for now and will be upgraded.

## Stitch Fiddle (read; chart maker, web)

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

## Crochetpop (read; chart + written-instruction generator, web)

Stores designs locally in the browser with optional cloud sync. Generates written row-by-row
instructions that *include the foundation chain and the turning chain* and use "standard stitch
abbreviations". Supports flat and in-the-round; granny squares written round by round. Has a
"Live Row Tracker" with hands-free audio — a direct analogue of our Work screen. Claims
deterministic validation that "every round's stitch math has to close", i.e. a tech-editor check
built in. No public file format found.

**For us:** the written output including turning chain and foundation is the same conclusion as
Phase 1. The stitch-math check is worth borrowing as a validator rule for shaped rows (#37).

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
- Driving Stitch Fiddle and Crochetpop once `stitchfiddle.com` / `crochetpop.app` are allowed in
  the Chrome extension: capture export formats, aspect-ratio and in-the-round settings.
- Row-counter apps (top three by installs): what per-project state they keep.
