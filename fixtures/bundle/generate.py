"""Regenerate fixtures/bundle/<slug>.graphghan from every pattern with a committed dist/.

Run: uv run python fixtures/bundle/generate.py
tests/test_bundle_fixtures.py fails if the committed files differ from a fresh generation.
"""

from __future__ import annotations

from pathlib import Path

from graphghan.bundle import to_bundle

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent


def bundled_patterns(root: Path) -> list[Path]:
    """Every pattern folder with a committed dist/chart.json, in slug order."""
    return [
        d
        for d in sorted((root / "patterns").iterdir())
        if (d / "pattern.toml").exists() and (d / "dist" / "chart.json").exists()
    ]


def main() -> None:
    for d in bundled_patterns(ROOT):
        out = OUT / f"{d.name}.graphghan"
        out.write_bytes(to_bundle(d))
        print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
