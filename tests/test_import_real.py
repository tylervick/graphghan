"""Real pattern files, never committed: fixtures/import/real/manifest.toml says what each should
import as; an absent file skips with its name."""

import hashlib
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
    if entry.get("unsupported"):
        with pytest.raises(ValueError, match="no grid found"):
            import_file(path, **entry.get("kwargs", {}))
        return
    result = import_file(path, **entry.get("kwargs", {}))
    assert (result.width, result.height, len(result.palette)) == (
        entry["width"],
        entry["height"],
        entry["colors"],
    )
    if entry.get("rows_sha256"):
        assert hashlib.sha256("\n".join(result.rows).encode()).hexdigest() == entry["rows_sha256"]
