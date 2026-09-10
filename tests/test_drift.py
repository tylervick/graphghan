from pathlib import Path

from graphghan.cli import main

ROOT = Path(__file__).resolve().parents[1]


def test_committed_dist_matches_code():
    for d in sorted((ROOT / "patterns").iterdir()):
        if (d / "pattern.toml").exists() and (d / "dist" / "chart.json").exists():
            assert main(["render", str(d), "--check"]) == 0, d.name
