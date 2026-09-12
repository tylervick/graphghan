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
Overlay mosaic is separate because a cell carries a stitch type. Export options, aspect ratio
and in-the-round settings still to be captured by driving the tool.

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

## Pending

- Chart Minder (429 on fetch; retry).
- knitCompanion (feature page).
- Driving Stitch Fiddle and Crochetpop once `stitchfiddle.com` / `crochetpop.app` are allowed in
  the Chrome extension: capture export formats, aspect-ratio and in-the-round settings.
- Row-counter apps (top three by installs): what per-project state they keep.
