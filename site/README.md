# site

The published pattern feed: what https://graphghan.milo.cat/ serves and what the iOS app reads.
Built by `build.py` from `../patterns/*/dist` into `dist/` (gitignored):

    uv run graphghan site build     # or: uv run python site/build.py
    uv run graphghan site serve     # http://127.0.0.1:8765/

Output:

- `patterns/index.json` — one entry per pattern: identity, size, colours, preview, and the path
  to its manifest.
- `patterns/<slug>/pattern.json` — the manifest (schema 1): metadata, palette, and every published
  chart with its path, size and stats. The first chart is the default.
- `patterns/<slug>/chart.json`, `chart.png`, `preview.png`, `written-rows.txt` — the default chart,
  with the rest under `charts/<variant>-<gauge>/`.
- `schema/*.json` — served at the `$id` each schema claims.
- `index.html` — a static landing page, copied from `src/` as-is.

This is a data feed, not an application. The browser viewer that used to live here — the pattern
pages, the service worker, the offline progress store, and `app/data.js`, a hand-written JavaScript
mirror of `graphghan.chartdoc.sequence` — was retired in #78, leaving the sequencer with two
implementations (Python and `GraphghanCore`) instead of three. Anything added back under `src/` is
copied verbatim, so keep it inert.
