import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "examples"))

from outlander_studies import STUDIES  # noqa: E402


def test_studies_build_under_200():
    for name, fn in STUDIES.items():
        g, report = fn("sc")
        assert g.a.shape[0] < 200 and g.a.shape[1] < 200, name
        assert "panel" in report
