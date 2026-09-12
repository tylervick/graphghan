# Proposal: revise Phase 1 in the design note (not yet applied)

Status: proposed 2026-09-12, awaiting a decision. The design note's Phase 1 stands as written
until this is accepted; nothing here is implemented.

## Why revise

The design note's Phase 1 was written before the corpus. Four batches (55 usable patterns), the
genre probes, Ravelry's form and pattern pages, and Stitch Fiddle's wizard agree on three things
the current Phase 1 gets narrowly right and could get generally right at the same cost.

## 1. `turning_chain` → `boundary`

**Now:** `gauge.turning_chain: { count, counts_as_stitch, color }`.

**Evidence:** every genre probe wanted something different at the end of a pass — rows turn and
chain; joined rounds join with a slip stitch then chain; overlay mosaic fastens off and re-joins
the next colour; Tunisian never turns and opens each pass with its own chain; amigurumi does
nothing at all (spiral). One pattern (The Loopy Lamb) ends rounds with a reverse-slip-stitch
colour change whose closing chain is in the next colour. These are one vocabulary.

**Proposed:**

```json
"gauge": {
  "boundary": {
    "kind": "turn",            // turn | join | rejoin | spiral | return
    "chain": 1,                // chains made at the boundary; 0 allowed
    "counts_as_stitch": false, // default false
    "color": "next"            // optional: next | current
  }
}
```

Phase 1 implements `kind: "turn"` only; readers show nothing for other kinds until they
understand them. The field is still in `gauge`, still unhashed, still additive. Cost over the
current shape: one enum key. Benefit: #43 (joined vs spiral), mosaic's rejoin and Tunisian's
per-pass chain land as values, not new fields.

**What the UI says** is unchanged for `turn`: "ch 1, turn". For the rest, later.

## 2. `gauge.unit`

**Now:** `gauge.stitches` and `gauge.rows` are counts of stitches and rows.

**Evidence:** four corpus C2C patterns state gauge in tiles ("5.5 tiles = 4 in"); Ravelry's form
has a *repeats* gauge unit; Bernat states C2C gauge in sc it never uses. Without a unit, a C2C
chart's finished-size derivation is wrong or the author lies in the field.

**Proposed:** `gauge.unit: "stitches" | "repeats" | "tiles"`, default `stitches`. Readers that do
not understand a unit do not derive size. Additive, unhashed, one line of doc.

## 3. `pattern.craft` and `gauge.terms_also`

**Evidence:** Ravelry, Lion Brand's tags and LoveCrafts all key on craft first; we have no such
field and `technique.type` only implies crochet. Ravelry records terminology as `US`, `UK`, or
`both US and UK`; two corpus patterns give both. A single-valued `terms` enum forbids what the
catalogue records.

**Proposed:** `pattern.craft: "crochet" | "knit" | "tunisian" | "cross-stitch"` (unhashed; the
site manifest gains it too), `pattern.language` (BCP 47; Ravelry lists 5,107 "Universal – no
written language" patterns and ~12% non-English), and `gauge.terms_also: "UK"` for a document
that spells both. Readers spell out from `terms` only.

## 4. Two things the corpus says *not* to do

- Do not derive `boundary.color`; it is stated in 3 of 32 row patterns. Show it only when present.
- Do not promote `care` (#35): 1 of 55 patterns carries it.

## Effect on the implementation plan

Field names in `docs/superpowers/specs/2026-09-12-pattern-data-model-design.md` §6.1–6.4 change
(`turning_chain` → `boundary` with `kind`), `pattern.toml` gains `craft` and `terms_also`, and the
Swift `TurningChain` type becomes `Boundary`. Tests listed in §6.5 are unchanged in shape. No
chart id moves.
