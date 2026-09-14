# Corpus sources and how each is fetched

Raw text lives in `raw/` (gitignored — copyrighted). Only `corpus.csv` and this note are
committed. Every raw file starts with a `SOURCE:` line.

| Stratum | Source | Mechanics | Status |
|---|---|---|---|
| yarn-company | Yarnspirations (Red Heart, Bernat, Caron, Patons, Lily) | product page → `cdn.shopify.com/...pdf` → `pdftotext`; `fetch-yarnspirations.sh` | 51 of 52 fetched (one product page returned HTTP 500). After ~5 rapid requests the site challenges every request (HTTP 429, "Verifying your connection"), including `.json`; the block lifted after ~1 h and a 20 s cadence completed the list. Coded in batches 6a–6c |
| yarn-company | Lion Brand | product `.json` works (tags = catalogue taxonomy); PDFs are injected by JS from `cdn.accentuate.io` and not in the JSON | 1 PDF via a search-found URL; taxonomy captured |
| european | DROPS / Garnstudio | Chrome only (WebFetch and curl get 403); full text on page; `cid=17` = English (US/in), `cid=19` = English (UK/cm) — the same pattern in both term systems | 4 US + 2 UK twins; knit colourwork in progress |
| indie | Designer blogs (Make & Do Crew, Repeat Crafter Me, Meghan Makes Do, Nana's Crafty Home, Cypress Textiles, Freese-Works, Crochetverse, The Loopy Lamb, Joanna's Crochet, Daisy Farm Crafts) | `curl` + `tools/html2txt.py` | 14 pages (mix of patterns and tutorials; coder marks which) |
| indie | Ravelry | signed in; pattern pages give craft, category, gauge, hook, yardage, sizes, **Crochet terminology**, attributes, and the designer's URL; pattern text is fetched from the designer's site with `curl` + html2txt (Ravelry downloads themselves need the session) | 9 designer pages (6 usable); `formats/ravelry-form.md` |
| european/UK | UK designer sites (Attic24 on Typepad, Crystals & Crochet, HanJan on Squarespace) | JS-only pages; `curl` gets 130-400 words | failed — UK stratum stays at 5 docs (Bella Coco ×2, Jera's, DROPS UK twins ×2) |
| on-hand | 10 purchased/free PDFs in ~/Downloads | `pdftotext` | 10 |
| cross-stitch | xstitchify free patterns | the page's `/download/pdf/` path serves the PDF to `curl` without an account → `pdftotext` | 1 chart (rose, 139×200, 8 DMC colours) |
| cross-stitch | DMC free patterns (signed in, 2026-09-14) | product page → "Pattern Only" → "Download Now" opens a 15-minute presigned S3 URL in a new tab (the Chrome extension reports the tab URL) → `curl` → `pdftotext`; also added to the account's Pattern Library. No direct PDF URL; the legacy `/media/.../patterns/pdf/<SKU>.pdf` path redirects | 5 charts (2 Easy, 1 Intermediate, 2 Advanced; PAT2174, PAT2168, PAT2173, PAT2027, PAT2026), bilingual EN/FR, `raw/dmc-*.txt` |
| indie | Tunisian (Make & Do Crew, KnitterKnotter ×2, TL Yarn Crafts) | `curl` + html2txt | 4 |
| indie | Overlay/inset mosaic (The Loopy Lamb ×2, Jera's Jamboree, Bella Coco, Juniper & Oakes) | `curl` + html2txt | 5 |
| indie | Filet (Bella Coco, Kristin Omdahl, Crochetpop) | `curl` + html2txt | 3 |
| indie | Amigurumi (Supergurumi, Once Upon a Cheerio, Craft Passion) + 3 how-tos | `curl` + html2txt | 6 |
| indie | Stranded knit hats (Handy Little Me, Tin Can Knits, Spruce Hill) | `curl` + html2txt; marlybird.com is JS-only (68 words) | 3 |
| indie | Tapestry (Truly Crochet, Treasurie, Two of Wands, Spotted Horse, LillaBjörn, Meghan Makes Do, KnitterKnotter roundup) | `curl` + html2txt | 7 |
| marketplace forms | LoveCrafts designer handbook | the handbook site itself returns a WordPress "critical error" in a real browser (2026-09-12); not an access problem | thin; FAQ says "Who is it for?" and "Type of pattern" are required. Ravelry's form is the primary marketplace source instead (`formats/ravelry-form.md`) |

## Rate limits and manners

- Yarnspirations: 8 s between requests was not enough; after ~5 requests the whole domain
  challenges. Do not hammer it. Chrome, or a 60 s cadence at most.
- DROPS: no limits hit at a handful per minute via Chrome; their terms forbid reproducing the
  complete pattern digitally, which is why `raw/` is never committed and coded rows carry only
  field values and short supporting quotes.
- Blogs: one request each; fine.

## Stratification target (from README.md)

At least three patterns per craft × technique × source cell where the cell exists in the wild.
Current gaps (after batch 4 sources): yarn-company coverage of mosaic/filet/Tunisian/rounds
(Yarnspirations, blocked on browser permission); magazine/book (none); cross-stitch has 6 charts after the DMC pull; knit stranded blankets (only hats so far). Ravelry indie designers (blocked on sign-in).
