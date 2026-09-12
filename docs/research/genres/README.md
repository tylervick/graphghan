# Genre probes: the representability matrix as a test log (RQ3)

Each row is backed by a probe note in this directory that hand-encodes a real published pattern
in the current format and records exactly where it fails. Verdicts:

- **works** — the current format carries everything the pattern states for working order.
- **refuses** — the format cannot open it for work and says so (acceptable).
- **silently wrong** — the format accepts it and then reports false numbers (unacceptable).
- **partly** — opens and works, with a stated gap.

| Genre | Verdict | Probe | Real source | Fails on |
|---|---|---|---|---|
| Tapestry / intarsia graphghan, rows | **works** | `tapestry.md` | Red Heart RHC0502 (Yarnspirations) | first row in a different stitch from the body (note only) |
| C2C | **refuses** (+ manifest silently wrong) | `c2c.md` | Bernat BRC0302 (Yarnspirations) | `stitches = w×h` in `pattern.json` and `stats`; tile gauge; two turning chains (#18, #44) |
| Filet | **silently wrong** | `filet.md` | Bella Coco free filet (UK) | block ≠ stitch; shared edge posts; turning chain keyed on next row's first cell (#44) |
| Overlay mosaic | **refuses on stitch, wrong on direction** | `mosaic.md` | Jera's Jamboree free chart (UK/US) | per-cell stitch not surfaced (#36); one-direction rows with fasten-off (#43 sibling) |
| Joined-round granny | partly | — (from DROPS 120-3 in corpus) | DROPS 120-3 | join and counting starting chain unstated (#43) |
| Spiral-round amigurumi | pending | — | PlanetJune / amigurumi.today (fetching) | — |
| Knit texture chart (k/p) | partly | — (DROPS 159-26, 221-45 in corpus) | DROPS | `layers.stitch` not surfaced; RS/WS symbol rule now documented (#36) |
| Knit stranded | pending | — | Spruce Hill / Handy Little Me hats (fetched) | — |
| Tunisian | pending | — | Yarnspirations Tunisian list (blocked) | — |
| Cross-stitch | works (by construction; OXS export) | — | xstitchify rose (needs the PDF) | — |
| Shaped tapestry panel | refuses | — | Orca bag (on-hand) | rows must sum to width (#37) |

The single "silently wrong" is filet. Every probe should either move it to "refuses" (a `cells`
declaration that readers honour) or be the reason #44 is implemented.
