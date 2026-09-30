"""fixtures/bundle/*.graphghan must equal a fresh export of the pattern it stands for."""

import sys
from pathlib import Path

from graphghan.bundle import to_bundle

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "bundle"
sys.path.insert(0, str(FIX))

from generate import bundled_patterns, pieced_bundles  # noqa: E402


def test_every_pattern_has_a_matching_bundle_fixture():
    patterns = bundled_patterns(ROOT)
    assert patterns, "no pattern folder with a committed dist/chart.json"
    expected = set()
    for d in patterns:
        fixture = FIX / f"{d.name}.graphghan"
        expected.add(fixture.name)
        assert fixture.exists(), f"missing {fixture.name}; run uv run python fixtures/bundle/generate.py"
        assert fixture.read_bytes() == to_bundle(d), (
            f"{fixture.name} differs from a fresh export; regenerate it"
        )
    assert {p.name for p in FIX.glob("*.graphghan")} == expected | set(pieced_bundles(ROOT)), (
        "stale bundle fixture with no pattern"
    )


def test_the_pieced_bundle_matches_its_fixture_tree():
    for name, data in pieced_bundles(ROOT).items():
        fixture = FIX / name
        assert fixture.exists(), f"missing {name}; run uv run python fixtures/bundle/generate.py"
        assert fixture.read_bytes() == data, f"{name} differs from a fresh build; regenerate it"
