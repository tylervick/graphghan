# Revyl test definitions

Two tests, grouped as the `graphghan-pr-review` workflow and wired into
`pr_review.workflow_ids` in `../config.yaml`. They run on a pull request that
touches `ios/`, `fixtures/`, `schema/` or `ci.yml`, against the build the
`revyl-preview` CI job uploads.

**Do not write comments in the `.yaml` files beside this one.** `revyl test
create` and `revyl test push` round-trip them through the backend and write them
back re-serialised: every comment is dropped, the `_meta` block is prepended, and
folded scalars are flattened to one line. Measured here — the two files went from
110 and 130 lines to 36 and 45 on their first push, losing every word of
explanation. That is why this file exists. The CLI owns the YAML; prose lives
here.

## `pattern-feed-to-project`

Patterns tab → pattern detail → `Start project` → a project exists.

Every step crosses the network. `ios/Tests` runs against a stub HTTP client, so
it can prove the decoder handles a manifest but not that the app reaches
<https://graphghan.milo.cat/> at all. A feed URL typo, an ATS change, or a schema
bump published ahead of the app all ship green today.

The index and the manifest are separate fetches, which is why the test asserts on
the Chart summary (189 × 184 stitches × rows, 54 × 46 in, sc) rather than just on
the title — those four facts come from the manifest, not from the index row.

## `work-progress-persists`

Work a row → kill the app → the position is still there.

`ios/Tests` drives `ProjectService` against an **in-memory** SwiftData store, so
it proves the arithmetic and nothing about durability. The real store is in the
App Group container at `Library/Application Support/graphghan.store`, and the
failure this test exists for — progress held in view state, or written somewhere
the next launch does not read — looks perfect until you close the app. For an app
worked over weeks, losing the row counter loses the work.

It builds its own project rather than assuming one, so it can run first, alone,
or after the other test. The two use different project names for that reason.

## What a device walk corrected

Both tests were walked on a Revyl cloud device against build `main-b6fd058` (the
app as merged in #128) before any YAML was written. Five things reading the
source had got wrong, each of which would have produced a false failure:

| | |
|---|---|
| **`Start project` is two screens down** | Last element on the pattern detail screen, at y=1768 on a 956 pt device — under the Setup notes, the Colors notes and the Published charts list. It is in the accessibility tree the whole time, so a query finds it while a screenshot does not. Trust the query. |
| **The advance control is not "Done"** | It reads `+10`. Its accessibility label is `"0 of 189 single crochet in Gold, next ten"`. The large coloured card above it carries the same label and does the same thing. |
| **A run is worked in tens *within* a row** | Two taps moved the run `0 of 189` → `20 of 189` while the header stayed `Row 1 of 184`. The row number not moving is correct; asserting that it moves would be wrong. |
| **Starting a project switches tabs by itself** | Tapping Start lands on the Projects tab. A test that expects to navigate there fails a correct app. |
| **The sheet seeds Name with the *pattern's* name** | A project left at its default is called "Craigh na Dun Blanket" and cannot be told apart from the pattern it came from. Both tests rename. |

A cold launch briefly shows `Loading patterns…` while it re-reads the store and
re-fetches the feed. Transient, not a failure — `work-progress-persists` waits 3s
after `open_app` for exactly this.

## "Concurrency limit reached" is usually you

The org plan allows **one** execution at a time. A device session counts, a test
run counts, and so does the `proof_of_changes` run Revyl starts for a pull
request. When the slot is taken, `revyl test run` fails immediately with:

```
Concurrency limit reached for org <id> (1/1)
```

Two things make that message easy to misread, and both cost real time here once:

- **It does not say whose run holds the slot**, so it reads like someone else's.
  Retrying in a loop makes it worse rather than better: each attempt that gets
  through starts a run that holds the slot for the next two to three minutes, so
  a loop polling every two minutes collides with itself forever while appearing
  to be blocked from outside.
- **`revyl test history` lags the run.** A run that has started but not finished
  can still report "No executions found", which looks like confirmation that the
  blocker is external. Check again after it would have finished before concluding
  anything.

So: wait rather than retry, and check `revyl test history <name>` a few minutes
later before blaming anything. `revyl device stop --all` releases a session you
opened yourself.

This does not affect CI. Uploading a build consumes no slot, so `revyl-preview`
never contends; only the review that follows does, and nothing gates a merge on
it while `pr_review.strict_ci_check.build` is false.

## Working on them

```bash
mise x -- revyl test list                  # local vs remote sync state
mise x -- revyl test run <name>            # run one against the app's current build
mise x -- revyl test push <name> --force   # after editing the YAML
mise x -- revyl test report <name>         # what the last run actually did
```

Recreating the workflow changes its UUID, and `../config.yaml` has to change with
it; `revyl workflow list` prints the current one.
