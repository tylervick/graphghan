# G3 checklist: what a format needs before other tools can adopt it

Derived from `post-mortems.md`. Each row names the mechanism, which surviving format has it, what
our format (schema 2) has today, and the smallest change that closes the gap. None of these are
Phase 1; all of them precede calling anything "1.0".

| # | Mechanism | Precedent | Ours today | Gap and smallest fix |
|---|---|---|---|---|
| 1 | **Tiny required core; everything else optional** | WIF: two sections required. knitout: header + ops | `schema`, `pattern.id/title/version`, `chart.id/width/height`, `palette`, `rows`, `gauge.stitches/rows/over`, `technique.type` | `gauge` is required for a chart that has no gauge (wall hangings state none). Make `gauge` optional; readers derive nothing when absent |
| 2 | **Contents manifest** — a reader knows what the file holds before parsing | WIF `[CONTENTS]` | none; a reader discovers `layers`, `passes`, `ext` by probing | Optional top-level `contains: ["layers","passes","instructions","foundation"]`. Cheap for writers, lets a reader skip or warn before it reads 189 rows |
| 3 | **Unknown keys are ignored** | WIF, knitout ("warn … but otherwise ignore") | stated: "readers MUST ignore unknown keys at every level" | Add "and SHOULD warn once" so a reader can tell the user a newer file has data it did not use |
| 4 | **Obsolete keys never error** | WIF marks obsolete keys and keeps them in the spec forever | nothing deprecated yet; no rule | Add the rule now, before the first deprecation: "a key removed from the schema stays documented as obsolete; readers MUST NOT reject it" |
| 5 | **Versioning reader rule** | knitout: "accept any version, warn if newer" | `schema` is `const 2`; a schema-3 file is rejected by JSON Schema validation and by `Chart.init` (`unsupportedSchema`) | Split *format* version from *validation*: readers accept any `schema` ≥ 2, warn if newer than they know, and validate against the newest schema they have. Writers always write the newest |
| 6 | **Namespaced vendor extensions with a registry** | WIF `[PRIVATE <SourceID> …]` + registered IDs | `ext.<vendor>` free-form; `ext.graphghan.report` | A registry file in the repo listing vendor names in use; a rule that a vendor name is a reverse-domain or a registered short id; a skip rule (already implied: it is a JSON object) |
| 7 | **Sparse data with declared defaults** | WIF: a thread looks like `[WARP]` unless overridden | `technique` defaults are documented (`start: bottom`, `first_side: RS`, `rs_direction: rtl`) but `chart.id` hashes `technique` *as written*, so two files with equal meaning and different explicitness have different ids | Either canonicalise `technique` before hashing (fill defaults) — a breaking change to ids — or state that writers MUST write `technique` fully. The second is cheaper and we already do it; document it |
| 8 | **Units declared once** | WIF `Units=` enum | `gauge.over.unit` (`in`/`cm`) | Fine. Note that hook sizes are free text (#32) |
| 9 | **Human-readable, one revision then frozen** | WIF 1.1 unchanged since 1997 | JSON, readable; schema 2 is one revision in | Freeze discipline: a changelog section in `chart-format.md` and a rule that additive optional keys do not bump `schema` |
| 10 | **A second implementer** | WIF: three vendors at v1.0, eleven at v1.1 | Python, PWA, Swift — all ours | Not a format change. The nearest external candidates are Crochetpop (has a row tracker, no public format) and Stitch Fiddle (export). An OXS-style route is also open: publish a converter from our JSON to what Pattern Keeper's PDF convention needs, which is how cross-stitch tools interoperate today |
| 11 | **Conformance others can run** | none of the precedents have one; OXS interop is by vendor testing | `fixtures/chart-format/` + `tests/test_conformance.py` + Swift `FixturesTests` | Package the fixtures and the expected sequences as a standalone download with a one-page "how to claim conformance"; the doc already describes the claim, nobody outside can run it |
| 12 | **Progress stays outside the chart** | OXS keeps per-stitch `marked` inside; we keep a separate document | deliberate | Keep. Note in the doc *why*: the chart is immutable and hashed; progress references it by id |

## Ordering

1, 3, 4, 5, 9 are documentation and small reader changes with no data migration; do them together
as "schema 2.1" wording in `chart-format.md`. 2 and 6 are additive keys. 7 is a statement of what
writers already do. 11 is packaging. 10 is the only one that needs another person, and it is the
one that decides whether G3 happens at all.
