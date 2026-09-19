import json
from pathlib import Path

import numpy as np
import pypdfium2 as pdfium
import pytest

from graphghan import exporters, importers
from graphghan.cli import main
from graphghan.export import decode_rows

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "chart-format"
CRAIGH_TOML = ROOT / "patterns" / "craigh-na-dun" / "pattern.toml"


def load(name):
    return json.loads((FIX / f"{name}.chart.json").read_text(encoding="utf-8"))


def grid(doc):
    return decode_rows(doc["rows"], [p["code"] for p in doc["palette"]])


def test_oxs_round_trips_with_its_own_palette(tmp_path):
    doc = load("two-letter-codes")
    src = tmp_path / "chart.oxs"
    src.write_text(exporters.to_oxs(doc), encoding="utf-8")
    result = importers.import_file(src)
    assert result.kind == "oxs" and np.array_equal(result.grid, grid(doc))
    assert [p["name"] for p in result.palette] == [p["name"] for p in doc["palette"]]
    assert result.codes == [p["code"] for p in doc["palette"]]  # graphghan writes the code as the OXS number
    assert result.hexes == [p["hex"].lower() for p in doc["palette"]]  # OXS has no case to keep
    assert result.rows == doc["rows"]


def test_csv_needs_a_palette_and_round_trips_with_one(tmp_path):
    doc = load("craigh-na-dun")
    src = tmp_path / "chart.csv"
    src.write_text(exporters.to_csv(doc), encoding="utf-8")
    with pytest.raises(ValueError, match="--palette"):
        importers.import_file(src)
    result = importers.import_file(src, palette_toml=CRAIGH_TOML)
    assert result.kind == "csv" and result.rows == doc["rows"]


def test_pixel_png_is_recognised_and_clustered(tmp_path):
    doc = load("craigh-na-dun")
    src = tmp_path / "chart.png"
    exporters.to_png(doc).save(src)
    result = importers.import_file(src)
    assert result.kind == "pixels" and result.grid.shape == grid(doc).shape
    assert sorted(result.hexes) == sorted(p["hex"] for p in doc["palette"])
    # Same picture, whatever the codes came out as.
    want = np.asarray(exporters.to_png(doc))
    got = np.array([tuple(int(h[i : i + 2], 16) for i in (1, 3, 5)) for h in result.hexes], dtype=np.uint8)[
        result.grid
    ]
    assert np.array_equal(got, want)
    with_palette = importers.import_file(src, palette_toml=CRAIGH_TOML)
    assert with_palette.rows == doc["rows"]


def test_picture_of_a_chart_page_is_read_as_a_raster(tmp_path):
    doc = load("craigh-na-dun")
    pdf = pdfium.PdfDocument(str(ROOT / "fixtures" / "import" / "craigh-na-dun-final-sc.pdf"))
    src = tmp_path / "page5.png"
    pdf[4].render(scale=3).to_pil().convert("RGB").save(src)  # Chart 1: columns 1-48, rows 1-62
    result = importers.import_file(src, palette_toml=CRAIGH_TOML)
    assert result.kind == "raster" and (result.width, result.height) == (48, 62)
    a = grid(doc)
    W, H = a.shape[1], a.shape[0]
    assert np.array_equal(result.grid, a[H - 62 : H, W - 48 : W])
    assert result.regions and result.regions[0].startswith("chosen: page 1 region 1")


def test_write_pattern_makes_a_folder_that_renders_and_checks(tmp_path):
    doc = load("two-letter-codes")
    src = tmp_path / "chart.oxs"
    src.write_text(exporters.to_oxs(doc), encoding="utf-8")
    result = importers.import_file(src)
    folder = importers.write_pattern(result, tmp_path / "two-letter", title="Two Letter")
    for name in (
        "pattern.toml",
        "chart.png",
        "design.py",
        "tests/test_design.py",
        "import-report.md",
        "CHANGELOG.md",
    ):
        assert (folder / name).exists(), name
    ok, output = importers.check_folder(folder, ROOT)
    assert ok, output
    rendered = json.loads((folder / "dist" / "chart.json").read_text())
    assert rendered["rows"] == doc["rows"]
    with pytest.raises(FileExistsError):
        importers.write_pattern(result, folder)
    assert importers.write_pattern(result, folder, force=True) == folder


def test_write_pattern_refuses_an_invalid_result(tmp_path):
    doc = load("two-letter-codes")
    src = tmp_path / "chart.oxs"
    src.write_text(exporters.to_oxs(doc), encoding="utf-8")
    result = importers.import_file(src)
    result.palette[0]["code"] = "toolong"
    with pytest.raises(ValueError, match="failed validation"):
        importers.write_pattern(result, tmp_path / "bad")
    assert not (tmp_path / "bad").exists()


def test_unknown_suffix_is_refused(tmp_path):
    src = tmp_path / "chart.txt"
    src.write_text("x")
    with pytest.raises(ValueError, match="not a .pdf"):
        importers.import_file(src)


def test_cli_import_writes_and_renders(tmp_path):
    doc = load("craigh-na-dun")
    src = tmp_path / "craigh.png"
    exporters.to_png(doc).save(src)
    into = tmp_path / "craigh-copy"
    assert (
        main(["import", str(src), "--into", str(into), "--palette", str(CRAIGH_TOML), "--title", "Copy"]) == 0
    )
    assert json.loads((into / "dist" / "chart.json").read_text())["rows"] == doc["rows"]
    assert main(["import", str(src), "--into", str(into), "--palette", str(CRAIGH_TOML)]) == 1  # exists


def test_cli_import_dry_run_writes_nothing(tmp_path):
    doc = load("two-letter-codes")
    src = tmp_path / "chart.oxs"
    src.write_text(exporters.to_oxs(doc), encoding="utf-8")
    assert main(["import", str(src), "--into", str(tmp_path / "nothing"), "--dry-run"]) == 0
    assert not (tmp_path / "nothing").exists()
