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
| Spiral-round amigurumi | **refuses**, correctly | `amigurumi.md` | Supergurumi bunny | counts change every round (#37); spiral, no join (#43); non-stitch steps ("stuff the head") have no slot |
| Knit texture chart (k/p) | partly | — (DROPS 159-26, 221-45 in corpus) | DROPS | `layers.stitch` not surfaced; RS/WS symbol rule now documented (#36) |
| Knit stranded | **works** for a panel; partly for a hat | `stranded-knit.md` | Spruce Hill, Tin Can Knits hats | chart repeats unrolled (#39); `hook` is the wrong word for needles (#32); crown decreases are shaping (#37) |
| Tunisian | **partly** — via explicit `passes` | `tunisian.md` | Make & Do Crew, KnitterKnotter blankets | two passes per grid row fit `passes`; return pass has no stitches but `run.count ≥ 1`; per-pass start chain rather than a turning chain |
| Cross-stitch | works (by construction; OXS export) | — | xstitchify rose PDF (139×200, 8 DMC) | key is Symbol → DMC number → name; our palette carries all three |
| Shaped tapestry panel | refuses | — | Orca bag (on-hand) | rows must sum to width (#37) |

The single "silently wrong" is filet. Every probe should either move it to "refuses" (a `cells`
declaration that readers honour) or be the reason #44 is implemented.

## What the probes agree on

Four genres (mosaic, Tunisian, joined rounds, amigurumi) each ask for a different thing at the
pass boundary — turn+chain, join+chain, fasten-off+rejoin, return pass, action-with-no-stitches.
That is one vocabulary, not five features. Phase 1 should shape `turning_chain` so this
vocabulary can grow under it (see `tunisian.md`).
