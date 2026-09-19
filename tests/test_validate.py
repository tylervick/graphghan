from pathlib import Path

import numpy as np

from graphghan import validate
from graphghan.pattern import load_pattern

FIX = Path(__file__).parent / "fixtures" / "minimal"


def framed():
    a = np.zeros((8, 10), dtype=np.uint8)
    a[2:6, 2:8] = 1
    return a


def test_helpers():
    a = framed()
    assert validate.bad_rows(a, 10) == [] and validate.bad_rows(a, 9) == list(range(8))
    assert validate.used_indices(a) == {0, 1}
    assert validate.solid_edge(a, 0, 2, 2) and not validate.solid_edge(a, 1, 2, 2)
    assert validate.mirror_lr(a, 3) and validate.mirror_tb(a, 3)
    assert validate.changes_per_row(a) == [0, 0, 2, 2, 2, 2, 0, 0] and validate.min_run(a) == 2


def test_run_all_reports():
    meta = load_pattern(FIX)
    results = validate.run_all(framed(), meta)
    names = [r[0] for r in results]
    assert "row totals" in names and "palette closure" in names and "solid edge" in names
    assert all(ok for _, ok, _ in results)


def test_palette_codes_valid():
    assert validate.palette_codes_valid(["A", "Gd", "Kbl"])
    assert not validate.palette_codes_valid(["A", "ABCD"])


def test_shape_checks_are_opt_in(tmp_path):
    import shutil

    d = tmp_path / "plain"
    shutil.copytree(FIX, d)
    toml = (d / "pattern.toml").read_text()
    (d / "pattern.toml").write_text(toml[: toml.index("[checks]")])
    meta = load_pattern(d)
    assert meta.checks == {}
    a = framed()
    a[0, 0] = 1  # break the edge and the mirror: without [checks] nobody minds
    names = [r[0] for r in validate.run_all(a, meta)]
    assert "solid edge" not in names and not any(n.startswith("mirror") for n in names)
    assert all(ok for _, ok, _ in validate.run_all(a, meta))
    with_checks = load_pattern(FIX)
    assert with_checks.checks == {"solid_edge": 1, "first_row_solid": True, "mirror_lr": 2, "mirror_tb": 2}
    failed = [n for n, ok, _ in validate.run_all(a, with_checks) if not ok]
    assert "solid edge" in failed and "mirror left/right (outer 2 cols)" in failed


def test_checks_table_is_validated(tmp_path):
    import shutil

    import pytest

    d = tmp_path / "bad"
    shutil.copytree(FIX, d)
    toml = (d / "pattern.toml").read_text()
    (d / "pattern.toml").write_text(toml[: toml.index("[checks]")] + "[checks]\nsolid_edge = -1\n")
    with pytest.raises(ValueError, match=r"\[checks\].solid_edge"):
        load_pattern(d)
    (d / "pattern.toml").write_text(toml[: toml.index("[checks]")] + "[checks]\nround = true\n")
    with pytest.raises(ValueError, match="unknown keys"):
        load_pattern(d)
