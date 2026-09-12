# Format post-mortems: what lived, what died, and why (RQ5)

Date: 2026-09-12. Sources read in full are marked; second-hand ones are marked.

## WIF — Weaving Information File (lived; 1996, stable since 1997)

Read in full: spec v1.1, 20 April 1997 (tantradharma.com/maplehill/wif/wif1-1.txt).

**Origin.** v1.0 (March 1996) was written by three competing vendors — Patternland, Fiberworks
PCW, Swiftweave — who each had a proprietary format and agreed on a shared one. v1.1 (1997) came
out of an email list of eleven vendors; "while agreement may not have been unanimous on all
changes … no list participants expressed serious objection". It has not changed since, and every
major weaving program on every platform imports and exports it (wif-weave README, 2025).

**Design criteria, verbatim:** "1. It can evolve and change as the need arises, without
rendering earlier versions unreadable by new programs nor later versions unreadable by older
programs. 2. It can be understood by a human reader. 3. It can be read by any computer capable of
reading an ASCII text file." And: "Efficiency is sacrificed in favor of readability by humans.
Specifically, efficient bit sensitive numbers are abandoned in favor of comma separated arrays
understandable by a weaver."

**Mechanisms worth copying.**

- **A manifest of what the file contains.** `[CONTENTS]` lists every section present as a
  boolean. "WIF reader programs should set the default value for all sections to false prior to
  reading [CONTENTS]." A reader knows what it will find before parsing it, and can skip what it
  does not understand.
- **Layered, with a small required core.** Minimum requirements are two sections: `[WIF]`
  (version, date, developer contact, source program) and `[CONTENTS]`. Everything else is
  optional and a reader that only knows the core can still display something. Ours has the same
  shape (palette + rows is the core); WIF says so explicitly.
- **Namespaced private extensions.** `[PRIVATE <SourceID> <SectionName>]`, with a registry of
  source IDs so two vendors cannot collide, and a rule that lets a reader skip a private section
  without parsing it ("no line may begin with open brace"). Our `ext.<vendor>` is the same idea;
  WIF adds the registry and the skip rule.
- **Obsolete keys are never errors.** "Programs should not issue error messages upon reading
  obsolete keylines." Deprecated keys stay in the spec, marked, forever.
- **Defaults and sparse data.** A thread "looks like the characteristics specified in WARP and
  WEFT unless you find a keyline in a data section which says otherwise." Writers may omit
  values equal to the default. This is how a 30-year-old format stays small.
- **Order independence and case insensitivity**, stated as hard rules, with an appendix of
  *unofficial* programmer advice on a preferred order for fast sequential reads. Official rules
  and implementation tips are separated on purpose.
- **Units declared once** (`Units=` in `[WARP]`/`[WEFT]`, from a fixed enum) and all measures
  use them. Ours: `gauge.over.unit`.
- **Colours are a palette table with an explicit range** (`[COLOR PALETTE] Range=0,255`) and
  every colour reference is an index. Fiberworks writes 0-999 rather than 0-255 — a real
  interoperability wrinkle the spec anticipated by making the range explicit.

**Why it lived.** Competing vendors wrote it together, so every one of them had a reader on day
one. The required core was tiny. It changed once, then stopped. Readers were told exactly what
to do with what they did not understand.

**Limitations.** Copyright on the spec document itself is personal and restrictive; the
*format* is free to implement but the *document* may not be redistributed. Translations were
never implemented and were suspended at 1.1. Bitmap sections were reserved and never built. No
schema, no conformance suite — conformance is by vendor reputation.

**For us.** The lessons are structural, not syntactic: a contents manifest, a tiny required
core, a skip rule for unknown content, namespaced vendor extensions with a registry, obsolete
keys that never error, and — above all — at least one other implementer at the table before
the format is called 1.0.

## knitout (lived; 2017–, v0.6)

Read: spec page for version and extension rules. Second-hand: adoption.

CMU Textiles Lab. Machine-level instruction format for knitting machines, deliberately "low
level" with "no flow-control, abstractions, or grouping primitives". Governed on GitHub issues
and a feedback alias; extensions are namespaced (`X-*` headers, `x-*` opcodes) and listed on a
single extensions page with their originating backend.

Rules worth copying, verbatim: "Programs that write knitout should always use the latest
version of which they are aware." "Programs that read knitout must accept any version number,
but should warn if the version is later than one they support." "Programs that read knitout
files should warn upon encountering an extension header or opcode they do not support; but
should otherwise ignore the header or opcode."

**Why it lived.** A single well-funded lab with real machines, a reference toolchain, and
backends for two machine families; it is the output format of research tools people actually
want to use. Version numbers are integers and the reader rule is one sentence.

**Not our layer.** It describes needle operations, not a chart. Its versioning and
unknown-content rules are the transferable part.

## OXS — Open Cross Stitch (lived, narrowly; 2020–)

Read: format page. Second-hand: adoption list. History page unreachable.

XML, defined by one vendor (Ursa Software, MacStitch/WinStitch) "to handle Ursa Software's file
requirements", then opened. Adopted by Pattern Maker, KXStitch, DP Software, Cross Stitch Saga,
several mobile viewers, and used as the interchange format that PDF-to-chart converters emit.

**Why it lived.** The dominant desktop vendor published it and shipped it; Pattern Maker — the
other big one — read it; mobile apps needed something to import and had nothing else. It is a
one-vendor standard that others adopted because the alternative was reverse-engineering `.xsd`.

**Caveats.** Vendor-defined and vendor-evolved; a single-vendor spec can move under you. Per-
stitch `marked` puts progress inside the chart document, which we deliberately do not do (our
chart is immutable and hashed). We already export OXS; it is the right bridge for cross-stitch
tools and the wrong model for versioning.

## KnitML (died; ~2007–2009)

Second-hand only: SourceForge project page, a 2007 blog announcement, the k2g2 wiki.

XML for hand-knitting instructions, single author, begun as "a way to teach XMLSchema". What
resulted "is not an XML standard in the strict sense but rather a reference implementation …
implemented in Java." Last activity around 2009. No second implementer, no publisher adoption,
no tool a knitter would use daily.

**Why it died.** It modelled the hardest thing — free-form written instructions with repeats,
shaping and sizing — before anyone needed a machine-readable version of that, and the one
implementation was a Java library, not a thing a knitter runs. There was no chart-level
product pulling the format into existence.

## What this says for G3

| Lived | Died |
|---|---|
| Multiple implementers from day one (WIF) or one implementer everyone depends on (OXS, knitout) | One author, one implementation (KnitML) |
| Tiny required core, everything else optional | Modelled the hardest case first |
| Explicit rule for unknown and obsolete content | — |
| A product people used pulled the format along | A library nobody ran |
| Changed once, then froze (WIF) or versioned with a one-sentence reader rule (knitout) | — |

Our format already has: a small core, readers-must-ignore-unknown-keys, vendor `ext`, fixtures.
It does not yet have: a contents manifest, a rule for obsolete keys, a registry for `ext`
names, a stated versioning policy for readers ("accept any, warn if newer"), or a second
implementer outside this repo. Those are the G3 work, and none of them changes Phase 1.
