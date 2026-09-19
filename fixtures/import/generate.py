"""Regenerate fixtures/import/<slug>-<key>.pdf from every committed chart.

Run: uv run python fixtures/import/generate.py
tests/test_import_fixtures.py fails if the committed files differ from a fresh generation.
"""

from __future__ import annotations

import json
from pathlib import Path

from graphghan.pdf import to_pdf
from graphghan.publish import committed_charts

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent


def fixture_path(slug: str, key: str) -> Path:
    return OUT / f"{slug}-{key}.pdf"


def main() -> None:
    for slug, key, path in committed_charts(ROOT):
        doc = json.loads(path.read_text(encoding="utf-8"))
        out = fixture_path(slug, key)
        out.write_bytes(to_pdf(doc))
        print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
