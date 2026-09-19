"""Real pattern files, never committed: fixtures/import/real/manifest.toml says what each should
import as; an absent file skips with its name."""

import hashlib
import re
import tomllib
from pathlib import Path

import pytest

from graphghan.importers import import_file

ROOT = Path(__file__).resolve().parents[1]
REAL = ROOT / "fixtures" / "import" / "real"
MANIFEST = tomllib.loads((REAL / "manifest.toml").read_text(encoding="utf-8"))["fixture"]


@pytest.mark.parametrize("entry", MANIFEST, ids=[e["id"] for e in MANIFEST])
def test_real_fixture(entry):
    path = REAL / entry["file"]
    if not path.exists():
        pytest.skip(f"real fixture {entry['file']} is absent; see fixtures/import/real/README.md")
    kwargs = dict(entry.get("kwargs", {}))
    if "cells" in kwargs:
        kwargs["cells"] = tuple(kwargs["cells"])
    if entry.get("prose"):
        prose_path = REAL / entry["prose"]
        if not prose_path.exists():
            pytest.skip(f"real prose {entry['prose']} is absent; see fixtures/import/real/README.md")
        kwargs["prose"] = prose_path
    if entry.get("unsupported"):
        result = import_file(path, **kwargs)
        assert result.kind == "no-grid" and result.grid is None
        assert any(w.startswith("no grid found") for w in result.warnings)
        return
    if entry.get("expect_error"):
        with pytest.raises(ValueError, match=re.escape(entry["expect_error"])):
            import_file(path, **kwargs)
        return
    result = import_file(path, **kwargs)
    assert (result.width, result.height, len(result.palette)) == (
        entry["width"],
        entry["height"],
        entry["colors"],
    )
    if entry.get("cross_check"):
        assert result.meta.get("cross_check") == entry["cross_check"]
    if entry.get("rows_sha256"):
        assert hashlib.sha256("\n".join(result.rows).encode()).hexdigest() == entry["rows_sha256"]
