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


def test_pdf_pages_are_rendered_one_at_a_time(monkeypatch):
    """A long PDF never sits in memory whole: pages stream through the grid search and only the
    chosen page is rendered again."""
    from graphghan import importers as imp

    live = []
    real = imp.iter_pages

    def counting(path, scale=imp.RENDER_SCALE):
        for page_no, img in real(path, scale):
            live.append(page_no)
            yield page_no, img

    monkeypatch.setattr(imp, "iter_pages", counting)
    monkeypatch.setattr(imp, "is_own_pdf", lambda _p: False)
    pdf = ROOT / "fixtures" / "import" / "craigh-na-dun-final-hdc.pdf"
    result = imp.import_file(pdf, page=5)
    assert (result.width, result.height) == (44, 39)
    assert live == list(range(1, imp.page_count(pdf) + 1))


def test_an_oversized_file_is_refused(tmp_path, monkeypatch):
    from graphghan import importers as imp

    monkeypatch.setattr(imp, "MAX_FILE_BYTES", 10)
    src = tmp_path / "big.csv"
    src.write_text("A,A,A,A,A,A,A,A\n")
    with pytest.raises(ValueError, match="the most import reads is 0 MB"):
        imp.import_file(src)


def test_cli_stages_a_request_for_a_foreign_pdf_and_consumes_the_prose(tmp_path, monkeypatch):
    """The two-run flow (spec §6.1) on our own PDF disguised as a foreign one."""
    import shutil

    from graphghan.pdfself import prose_from_own_pdf

    src = tmp_path / "foreign.pdf"
    shutil.copy(ROOT / "fixtures" / "import" / "craigh-na-dun-final-hdc.pdf", src)
    monkeypatch.setattr("graphghan.importers.is_own_pdf", lambda _p: False)
    monkeypatch.setattr("graphghan.cli.find_repo_root", lambda *a, **k: tmp_path)
    into = tmp_path / "patterns" / "foreign"
    # First run: the grid is read (the largest tile), the prose is staged, nothing is written.
    assert main(["import", str(src), "--into", str(into), "--page", "5"]) == 0
    staged = tmp_path / "build" / "import" / "foreign"
    assert (staged / "request.md").exists() and (staged / "grid.json").exists()
    assert (staged / "pages" / "p05.png").exists() and (staged / "pages" / "p05.txt").exists()
    assert not into.exists()
    # The skill writes prose.json; here our own reader stands in for it, restricted to the tile.
    doc = prose_from_own_pdf(src)
    doc["chart"] = {"row1": "bottom-right", "width": 44, "height": 39}
    doc["written_rows"] = [
        {"row": r["row"], "runs": [[c, n] for c, n in r["runs"]]}
        for r in doc["written_rows"]
        if r["row"] <= 39
    ]
    # Tile 1 holds columns 1-44 of 176: keep the rightmost 44 stitches of each row (odd rows read right to left).
    for r in doc["written_rows"]:
        runs = r["runs"] if r["row"] % 2 == 1 else [[c, n] for c, n in reversed(r["runs"])]
        kept, left = [], 44
        for c, n in runs:
            take = min(n, left)
            if take:
                kept.append([c, take])
            left -= take
        r["runs"] = kept if r["row"] % 2 == 1 else [[c, n] for c, n in reversed(kept)]
    (staged / "prose.json").write_text(json.dumps(doc), encoding="utf-8")
    # Second run: the staged prose is picked up, the rows become the chart, the folder is written.
    assert main(["import", str(src), "--into", str(into), "--page", "5"]) == 0
    report = (into / "import-report.md").read_text()
    assert "39 written rows, 0 disagree with the chart" in report
    toml = (into / "pattern.toml").read_text()
    assert (
        'hook = "5 mm (US H-8)"' in toml
        and "hdc = [3.25, 2.5]" in toml
        and 'dedication = "For Meaghan"' in toml
    )


def test_cli_grid_only_skips_the_prose(tmp_path, monkeypatch):
    import shutil

    src = tmp_path / "foreign.pdf"
    shutil.copy(ROOT / "fixtures" / "import" / "craigh-na-dun-final-hdc.pdf", src)
    monkeypatch.setattr("graphghan.importers.is_own_pdf", lambda _p: False)
    monkeypatch.setattr("graphghan.cli.find_repo_root", lambda *a, **k: tmp_path)
    into = tmp_path / "grid-only"
    assert main(["import", str(src), "--into", str(into), "--page", "5", "--grid-only"]) == 0
    assert (into / "chart.png").exists() and "IMPORTED: fill me" in (into / "pattern.toml").read_text()


def test_rows_alone_when_there_is_no_picture(tmp_path):
    """A pattern whose rows are drawn as boxes and that has no chart: the written rows are the chart
    and every colour must come from the key (spec §6 stretch case)."""
    import sys

    sys.path.insert(0, str(ROOT / "tests"))
    from test_rasterchart import draw_box_rows

    src = tmp_path / "rows.png"
    draw_box_rows([["#000000"], ["#ffffff", "#000000", "#ffffff"], ["#000000"]]).save(src)
    result = importers.import_file(src)
    assert result.kind == "no-grid" and result.grid is None and result.width == 0
    prose = {
        "schema": "graphghan-import/1",
        "palette": [
            {"code": "K", "name": "Black", "hex": "#000000"},
            {"code": "W", "name": "White", "hex": "#ffffff"},
        ],
        "chart": {"width": 5, "height": 3, "row1": "bottom-right"},
        "written_rows": [
            {"row": 1, "runs": [["K", 5]]},
            {"row": 2, "runs": [["W", 2], ["K", 1], ["W", 2]]},
            {"row": 3, "runs": [["K", 5]]},
        ],
    }
    with pytest.raises(ValueError, match="chart.width and chart.height"):
        importers.import_file(src, prose={**prose, "chart": {}})
    with pytest.raises(ValueError, match="give every key colour a hex"):
        importers.import_file(src, prose={**prose, "palette": [{"code": "K"}, {"code": "W"}]})
    result = importers.import_file(src, prose=prose)
    assert result.kind == "rows" and result.rows == ["5K", "2W1K2W", "5K"]
    assert "no picture" in result.meta["cross_check"]
    folder = importers.write_pattern(result, tmp_path / "rows-only", title="Rows Only")
    ok, output = importers.check_folder(folder, ROOT)
    assert ok, output


def test_staging_writes_boxes_json_for_box_rows(tmp_path, monkeypatch):
    import sys

    sys.path.insert(0, str(ROOT / "tests"))
    from test_rasterchart import draw_box_rows

    src = tmp_path / "rows.png"
    draw_box_rows([["#000000"], ["#ffffff", "#000000", "#ffffff"]]).resize((1200, 1600)).save(src)
    monkeypatch.setattr("graphghan.cli.find_repo_root", lambda *a, **k: tmp_path)
    assert main(["import", str(src), "--into", str(tmp_path / "p")]) == 0
    staged = tmp_path / "build" / "import" / "rows"
    boxes = json.loads((staged / "boxes.json").read_text())
    assert [len(b["boxes"]) for b in boxes["1"]] == [1, 3] and [b["label"] for b in boxes["1"]] == [
        True,
        True,
    ]
    assert "Rows drawn as coloured boxes" in (staged / "request.md").read_text()
    assert main(["import", str(src), "--into", str(tmp_path / "p"), "--grid-only"]) == 1


def test_an_imported_pattern_passes_graphghan_check(tmp_path):
    """The point of opt-in shape checks (#114): `graphghan check` means the chart is sound, not
    that it looks like a bordered blanket."""
    doc = load("two-letter-codes")
    src = tmp_path / "chart.oxs"
    src.write_text(exporters.to_oxs(doc), encoding="utf-8")
    folder = importers.write_pattern(importers.import_file(src), tmp_path / "imported", title="Imported")
    assert main(["check", str(folder)]) == 0
