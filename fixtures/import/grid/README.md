# Grid reader fixtures

Synthetic chart pictures, drawn by `generate.py` exactly as `tests/test_rasterchart.py` draws
them, with the Python grid reader's answers recorded beside each (`<name>.json`: regions, cells
snapped to the drawing palette, and the clustered palette). The Swift port in
`ios/Packages/GraphghanCore` (`GridReaderTests`, `GridColoursTests`) is held to these answers; a
change to `rasterchart.py` that changes an answer must regenerate them (`uv run python
fixtures/import/grid/generate.py`) and the Swift port must follow. `tests/test_grid_fixtures.py`
fails when the committed files differ from a fresh generation.
