# site

Static viewer for the patterns in `../patterns`. Built by `build.py` into `dist/` (gitignored):

    uv run graphghan site build     # or: uv run python site/build.py
    uv run graphghan site serve     # http://127.0.0.1:8765/

Layout: `src/` is copied as-is; `pattern.html` is a template instantiated once per pattern at
`patterns/<slug>/index.html`; `sw.js` gets the precache list and build hash injected. Progress is
stored per pattern in `localStorage["graphghan:<slug>:progress"]`.

Each pattern also gets `pattern.json` (manifest: metadata, palette, every published chart with its
path and size) and a `charts/<variant>-<gauge>/` tree copied from the pattern's `dist/charts/`.
