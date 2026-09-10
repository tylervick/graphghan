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
