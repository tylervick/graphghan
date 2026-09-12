# Corpus sources and how each is fetched

Raw text lives in `raw/` (gitignored — copyrighted). Only `corpus.csv` and this note are
committed. Every raw file starts with a `SOURCE:` line.

| Stratum | Source | Mechanics | Status |
|---|---|---|---|
| yarn-company | Yarnspirations (Red Heart, Bernat, Caron, Patons, Lily) | product page → `cdn.shopify.com/...pdf` → `pdftotext`; `fetch-yarnspirations.sh` | 4 fetched; the site then challenged every request from this IP (HTTP 429, "Verifying your connection"), including the `.json` endpoint. Remaining ~48 to be done through Chrome once `yarnspirations.com` is allowed in the extension |
| yarn-company | Lion Brand | product `.json` works (tags = catalogue taxonomy); PDFs are injected by JS from `cdn.accentuate.io` and not in the JSON | 1 PDF via a search-found URL; taxonomy captured |
| european | DROPS / Garnstudio | Chrome only (WebFetch and curl get 403); full text on page; `cid=17` = English (US/in), `cid=19` = English (UK/cm) — the same pattern in both term systems | 4 US + 2 UK twins; knit colourwork in progress |
| indie | Designer blogs (Make & Do Crew, Repeat Crafter Me, Meghan Makes Do, Nana's Crafty Home, Cypress Textiles, Freese-Works, Crochetverse, The Loopy Lamb, Joanna's Crochet, Daisy Farm Crafts) | `curl` + `tools/html2txt.py` | 14 pages (mix of patterns and tutorials; coder marks which) |
| indie | Ravelry | needs sign-in in the extension's Chrome window and `ravelry.com` allowed | blocked |
| on-hand | 10 purchased/free PDFs in ~/Downloads | `pdftotext` | 10 |
| cross-stitch | xstitchify free patterns | `curl` + html2txt | 1 page; PDF link needs sign-up — find another source |
| marketplace forms | LoveCrafts designer handbook | 404/500 on every URL tried | thin; FAQ says "Who is it for?" and "Type of pattern" are required |

## Rate limits and manners

- Yarnspirations: 8 s between requests was not enough; after ~5 requests the whole domain
  challenges. Do not hammer it. Chrome, or a 60 s cadence at most.
- DROPS: no limits hit at a handful per minute via Chrome; their terms forbid reproducing the
  complete pattern digitally, which is why `raw/` is never committed and coded rows carry only
  field values and short supporting quotes.
- Blogs: one request each; fine.

## Stratification target (from README.md)

At least three patterns per craft × technique × source cell where the cell exists in the wild.
Current gaps: joined-rounds and spiral-rounds (Yarnspirations amigurumi and granny patterns are
in the fetch list); knit stranded (DROPS 157-21, 120-3 pending); cross-stitch (need 3 charts);
Tunisian (Yarnspirations list pending); magazine/book (none yet).
