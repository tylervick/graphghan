"""Regenerate fixtures/bundle/<slug>.graphghan from every pattern with a committed dist/.

Run: uv run python fixtures/bundle/generate.py
tests/test_bundle_fixtures.py fails if the committed files differ from a fresh generation.
"""

from __future__ import annotations

from pathlib import Path

from graphghan.bundle import to_bundle, zip_files

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
CHART_FORMAT = Path(__file__).resolve().parents[1] / "chart-format"


def bundled_patterns(root: Path) -> list[Path]:
    """Every pattern folder with a committed dist/chart.json, in slug order."""
    return [
        d
        for d in sorted((root / "patterns").iterdir())
        if (d / "pattern.toml").exists() and (d / "dist" / "chart.json").exists()
    ]


def pieced_bundles(root: Path) -> dict[str, bytes]:
    """Bundles of the hand-built pieced fixtures (the Python writes no pieced pattern, #214): the
    fixture tree zipped as it stands, less the progress files a bundle does not carry."""
    tree = root / "fixtures" / "chart-format" / "pieces-basic"
    files = {
        p.relative_to(tree).as_posix(): p.read_bytes()
        for p in sorted(tree.rglob("*"))
        if p.is_file() and not p.name.startswith("progress")
    }
    return {"pieces-basic.graphghan": zip_files(files)}


def main() -> None:
    for d in bundled_patterns(ROOT):
        out = OUT / f"{d.name}.graphghan"
        out.write_bytes(to_bundle(d))
        print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size:,} bytes)")
    for name, data in pieced_bundles(ROOT).items():
        out = OUT / name
        out.write_bytes(data)
        print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
