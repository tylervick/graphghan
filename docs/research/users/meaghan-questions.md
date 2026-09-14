# User research: Meaghan working Craigh na Dun

Purpose: RQ1 — what must the chart carry so she can work it with no other document. Tyler runs
this and relays answers verbatim; paraphrase is marked as such. Nothing here is a test of her.
Every hesitation is a finding about the app, not about her.

## Part A: observation (one working session, 20-30 minutes)

Sit with her while she works from the app. Do not help unless she is stuck for more than a
minute. Write down, with a rough time, every time she:

1. Looks at anything other than the phone (the printed chart, the written rows, a note, a
   website, you).
2. Says or does anything like "wait, what do I…" — and what she then did.
3. Counts stitches back over what she has already made.
4. Reaches the end of a row: what she does before starting the next, in order (chain? turn?
   change colour? check something?).
5. Changes colour mid-row: what she does with the old yarn, and whether she carries or cuts.
6. Taps Back, and why.
7. Puts the phone down and uses a different tool (row counter, stitch marker, pen).

## Part B: questions (after the session, in her words)

Ask each, write the answer as close to verbatim as you can.

1. "When you start a new row, what do you do first — before the first stitch?"
2. "How do you know how many chains to make when you turn? Where did you learn that for this
   blanket?"
3. "Does the chain count as a stitch in this blanket? How do you know?"
4. "When you change colour at the end of a row, which colour do you chain in?"
5. "Is there anything you had to look up somewhere else — the PDF, a website, a video — that the
   app should have told you?"
6. "What is the most annoying thing about working from the phone?"
7. "What do you do when you lose your place?"
8. "Is there anything on the screen you never look at?"
9. "Is there anything you wish was on the screen that isn't?"
10. "If the app said 'sc' next to the number — would that help, or would you ignore it?"
11. "If the app said 'ch 1, turn' at the end of each row — would that help, or is it obvious?"
12. "What did you do before the first row — the foundation chain? Did you count it? How many
    times?"

## Part C: the printed pattern

Ask her to show you what she has printed or saved besides the app, and note what it is. If she
has annotated anything by hand, photograph it — hand annotations are the highest-value evidence
there is about what a pattern failed to say.

## Recording

Put the results in `meaghan-session-1.md` in this directory: Part A as a timed list, Part B as
question and answer, Part C as a list with photos. Mark anything paraphrased.

## When the notes come back

The session was deferred on 2026-09-14 (Meaghan away) and Phase 1 shipped without it, so the
answers land against a merged design, not a draft. Whoever picks them up:

1. Write `meaghan-session-1.md` in this directory as described above, verbatim, paraphrases marked.
2. Code Part B against `../claims.md`: questions 2–4 and 10–12 are first-hand evidence for claims 1–3
   (turning chain, counts-as, chain colour) and for the on-deck wording in
   `docs/superpowers/specs/2026-09-12-pattern-data-model-design.md` §6.4; questions 6–9 feed RQ4 and
   `community-threads.md`. Add a first-hand evidence line to each claim touched, a dated entry to
   `../log.md`, and mark RQ1's "done when" in `../README.md`.
3. Anything the answers change in the app is text only under Phase 1 (§6.4) — file an issue per
   change (the backlog is GitHub Issues) rather than editing the merged spec.
