# Graphghan

Read `README.md` for what the repo is and how to run it. `ios/README.md` covers the app.

## Backlog

GitHub Issues is the only backlog. Nothing goes in a TODO file or a spec's follow-ons list
without an issue behind it.

- When Tyler says "log that", "note that for later", "add to the backlog", or describes a bug
  or idea that is not the current task, file an issue with `gh issue create` right then. Do not
  wait for the task to finish, and do not put it in a commit.
- Search first: `gh issue list --search "<words>" --state all`. If one exists, comment on it
  instead of opening another.
- Labels: one type (`bug` or `enhancement`), one area (`ios`, `python`, `site`, `skill`,
  `format`), and for enhancements one stage:
  - `idea`: a sentence. May never happen.
  - `shaped`: what, why, rough size, and what it waits on are written down.
  - `spec`: a design doc exists under `docs/superpowers/specs/`; the issue links to it and the
    doc links back. Ready for `superpowers:writing-plans`.
  - Add `blocked` when it cannot start yet and say why in the body.
- Body shape for enhancements: What, Why, Rough size, Waits on (the Idea template). Bugs:
  Steps, Where, Notes.
- Picking one up: brainstorm from the issue text, move the label to `spec` when the design doc
  lands, and put `Closes #N` in the PR body so the merge closes it.
- A spec's non-goals or follow-ons section lists issue numbers, not prose.
