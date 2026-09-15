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
| Filet | **partly** — `chart.cell` withholds instead of miscounting | `filet.md` | Bella Coco free filet (UK) | shared edge posts; turning chain keyed on next row's first cell — the real per-cell arithmetic is #44 part 2 (`docs/superpowers/specs/2026-09-14-cell-cardinality-design.md`) |
| Overlay mosaic | **refuses on stitch, wrong on direction** | `mosaic.md` | Jera's Jamboree free chart (UK/US) | per-cell stitch not surfaced (#36); one-direction rows with fasten-off (#43 sibling) |
| Joined-round motifs | **partly** | `joined-rounds.md` | DROPS 120-3; The Loopy Lamb mosaic square | motif is not a grid (#37); join, counting starting chain, colour-change-at-join unstated (#43); a blanket of motifs is a grid whose cell is a motif (#44) |
| Spiral-round amigurumi | **refuses**, correctly | `amigurumi.md` | Supergurumi bunny | counts change every round (#37); spiral, no join (#43); non-stitch steps ("stuff the head") have no slot |
| Knit texture chart (k/p) | **partly** | `knit-texture.md` | DROPS 159-26, 221-45, 157-21 | `layers.stitch` not surfaced (#36); legend symbols are RS/WS pairs — documented rule suffices; repeats and edge stitches (#39) |
| Knit stranded | **works** for a panel; partly for a hat | `stranded-knit.md` | Spruce Hill, Tin Can Knits hats | chart repeats unrolled (#39); `hook` is the wrong word for needles (#32); crown decreases are shaping (#37) |
| Tunisian | **partly** — via explicit `passes` | `tunisian.md` | Make & Do Crew, KnitterKnotter blankets | two passes per grid row fit `passes`; return pass has no stitches but `run.count ≥ 1`; per-pass start chain rather than a turning chain |
| Cross-stitch | works (by construction; OXS export) | — | xstitchify rose PDF (139×200, 8 DMC) | key is Symbol → DMC number → name; our palette carries all three |
| Shaped tapestry panel | refuses | — | Orca bag (on-hand) | rows must sum to width (#37) |
| Motif-grid blanket (each cell one square) | **partly** | `joined-rounds.md` | Divine Debris *Glenda Ghost* (380 squares, 19×20 graph) | colour grid fits; a cell is a motif, not a stitch (#44); the motif itself is out of grid |

No row's verdict is "silently wrong" anymore, which is the point: filet moved to "partly" once
`chart.cell` let a reader withhold every stitch-derived number instead of computing it from the
wrong cardinality (`docs/superpowers/specs/2026-09-14-cell-cardinality-design.md`). What remains —
filet's real per-cell arithmetic, including a turning chain keyed on the next row's first cell — is
#44 part 2.

## What the probes agree on

Four genres (mosaic, Tunisian, joined rounds, amigurumi) each ask for a different thing at the
pass boundary — turn+chain, join+chain, fasten-off+rejoin, return pass, action-with-no-stitches.
That is one vocabulary, not five features. Phase 1 should shape `turning_chain` so this
vocabulary can grow under it (see `tunisian.md`).
