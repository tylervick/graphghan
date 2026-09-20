"""The .graphghan bundle: what it carries, and that it carries it the same way twice."""

import io
import json
import zipfile
from pathlib import Path

import pytest

from graphghan.bundle import BUNDLE_EPOCH, BUNDLE_UPDATED, bundle_files, to_bundle
from graphghan.manifest import manifest, published_docs

ROOT = Path(__file__).resolve().parents[1]
PATTERN = ROOT / "patterns" / "craigh-na-dun"


def archive(data: bytes) -> zipfile.ZipFile:
    return zipfile.ZipFile(io.BytesIO(data))


def test_two_calls_give_identical_bytes():
    assert to_bundle(PATTERN) == to_bundle(PATTERN)


def test_it_carries_the_manifest_and_exactly_what_the_manifest_references():
    z = archive(to_bundle(PATTERN))
    doc = json.loads(z.read("pattern.json"))
    expected = {"pattern.json", doc["preview"]}
    for chart in doc["charts"]:
        expected.update([chart["path"], chart["preview"]])
    assert set(z.namelist()) == expected
    # and nothing unreferenced came along for the ride
    assert not [n for n in z.namelist() if n.endswith(("chart.png", "written-rows.txt", "preview-grid.png"))]


def test_every_file_is_the_committed_one():
    z = archive(to_bundle(PATTERN))
    for name in z.namelist():
        if name == "pattern.json":
            continue
        assert z.read(name) == (PATTERN / "dist" / name).read_bytes(), name


def test_the_manifest_is_the_site_manifest_with_a_fixed_updated():
    doc = json.loads(archive(to_bundle(PATTERN)).read("pattern.json"))
    site = manifest(published_docs(PATTERN), "2026-01-01T00:00:00Z")
    assert doc["updated"] == BUNDLE_UPDATED
    assert {k: v for k, v in doc.items() if k != "updated"} == {
        k: v for k, v in site.items() if k != "updated"
    }


def test_entries_are_stored_at_a_fixed_time_in_sorted_order():
    infos = archive(to_bundle(PATTERN)).infolist()
    assert [i.filename for i in infos] == sorted(i.filename for i in infos)
    for info in infos:
        assert info.compress_type == zipfile.ZIP_STORED, info.filename
        assert info.date_time == BUNDLE_EPOCH, info.filename
        assert info.external_attr == 0o644 << 16, info.filename
        assert info.create_system == 0, info.filename


def test_no_entry_is_compressed_so_the_bytes_do_not_depend_on_zlib():
    # The reason for ZIP_STORED: zlib's output is deterministic per build, not across builds, and
    # the committed fixture is diffed in CI on a different OS than it is generated on.
    for info in archive(to_bundle(PATTERN)).infolist():
        assert info.compress_size == info.file_size, info.filename


def test_a_pattern_without_a_committed_dist_is_refused(tmp_path):
    (tmp_path / "pattern.toml").write_text("")
    with pytest.raises(FileNotFoundError, match="graphghan render"):
        to_bundle(tmp_path)


def test_a_manifest_referencing_a_missing_file_is_refused(tmp_path):
    import shutil

    d = tmp_path / "craigh-na-dun"
    shutil.copytree(PATTERN, d)
    (d / "dist" / "charts" / "final-hdc" / "preview.png").unlink()
    with pytest.raises(FileNotFoundError, match="charts/final-hdc/preview.png"):
        bundle_files(d)
