# Real importer fixtures

Pattern PDFs and chart images that belong to other people. They are gitignored here; only
`manifest.toml` (ids, sources, expected dimensions and, once eyeballed, the hash of the imported
rows) and this note are committed. `tests/test_import_real.py` skips any entry whose file is
absent and says which one.

Where the files come from:

- `docs/research/corpus/pdf/` in a checkout that has run `fetch-yarnspirations.sh` (the
  Yarnspirations set) or holds the ten on-hand PDFs (see `docs/research/corpus/sources.md`).
  Copy the file named in the manifest into this folder.
- `mdc-c2c-santa-blanket.pdf` is the free graph download linked from the Make & Do Crew page
  in the manifest.

To pin a new entry: run `uv run graphghan import <file> --into <slug> --dry-run`, look at the
preview against the PDF, then write the width, height, colour count and the sha256 of the
imported run strings (`hashlib.sha256("\n".join(result.rows).encode())`) into the manifest.
An entry with `unsupported` set documents a layout the grid reader does not read; its test
asserts only that the import refuses.

An entry with `prose` names a `<id>.prose.json` beside the file: the written rows, key, gauge
and sizes as read from the pattern's text by the graphghan skill (see
`.claude/skills/graphghan/references/import.md`). It is derived from the pattern and gitignored
too. `cross_check` pins what the written rows said against the grid; `expect_error` pins a
defect the pattern really has (a row printed twice, a shaped row that cannot sum to the width),
which the import must report by row number rather than fix.

The Outlander tapestry is the stretch case: its rows are printed as coloured boxes with a count
in each (pages 3-10), and its chart is a raster image (page 11). The first run's `boxes.json`
supplied the box colours; the counts were read by eye; the row totals, the pattern's own
per-colour Total row, and the chart page all agree with the transcription. The second entry
points the grid reader at the FAQ page, where there is no grid, to pin the rows-alone path.
