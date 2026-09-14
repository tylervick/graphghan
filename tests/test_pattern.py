from pathlib import Path

import pytest

from graphghan import grid as gr
from graphghan.pattern import find_repo_root, load_design, load_pattern

FIX = Path(__file__).parent / "fixtures" / "minimal"


def test_load_pattern_meta_and_gauges():
    meta = load_pattern(FIX)
    assert meta.slug == "minimal" and meta.title == "Minimal" and meta.version == "0.0.1"
    assert meta.size_in == (4.0, 3.0) and meta.first_row_color == "A"
    assert meta.gauges["square"] == (4.0, 4.0) and gr.GAUGES["square"] == (4.0, 4.0)
    assert meta.notes["setup"] == ["Chain W + 1 in A."]
    assert meta.palette.codes == ["A", "B"]


def test_load_design_builds():
    load_pattern(FIX)
    design = load_design(FIX)
    g, report = design.build("sc", "final")
    assert g.a.shape == (12, 14) and report["panel"] == (2, 2, 12, 10)
    assert design.VARIANTS == {"final": {}}


def test_find_repo_root():
    root = find_repo_root(Path(__file__))
    assert (root / "pyproject.toml").exists()


def test_publish_defaults_to_final_at_pattern_stitch():
    meta = load_pattern(FIX)
    assert meta.publish == [("final", "sc")]
    assert meta.author == "" and meta.license == ""


def test_instructions_from_notes_and_extra_sections(tmp_path):
    src = (FIX / "pattern.toml").read_text()
    src += '\n[publish]\ncharts = [["final", "square"], ["final", "sc"]]\n'
    src += '\n[[instructions]]\ntitle = "Blocking"\ntext = "Wet block to size."\n'
    (tmp_path / "pattern.toml").write_text(src)
    (tmp_path / "design.py").write_text((FIX / "design.py").read_text())
    meta = load_pattern(tmp_path)
    assert meta.publish == [("final", "square"), ("final", "sc")]
    assert meta.instructions == [
        {"title": "Setup", "text": "Chain W + 1 in A."},
        {"title": "Blocking", "text": "Wet block to size."},
    ]


def test_notes_with_several_items_join_with_newlines(tmp_path):
    src = (
        (FIX / "pattern.toml")
        .read_text()
        .replace('setup = ["Chain W + 1 in A."]', 'setup = ["One.", "Two."]\ncolors = ["Carry B."]')
    )
    (tmp_path / "pattern.toml").write_text(src)
    meta = load_pattern(tmp_path)
    assert meta.instructions == [
        {"title": "Setup", "text": "One.\nTwo."},
        {"title": "Colors", "text": "Carry B."},
    ]


def test_stitch_table_and_pattern_terms(tmp_path):
    src = (FIX / "pattern.toml").read_text()
    src = src.replace(
        'stitch = "sc"', 'stitch = "sc"\ncraft = "crochet"\nterms = "US"\nterms_also = "UK"\nlanguage = "en"'
    )
    src += (
        '\n[stitch.sc]\nchain = 1\ncounts_as_stitch = false\nchain_color = "next"\nfirst_stitch_in = 2\n'
        '\n[stitch.square]\nboundary = "join"\nchain = 3\nname = "granny cluster"\nunit = "tiles"\n'
    )
    (tmp_path / "pattern.toml").write_text(src)
    meta = load_pattern(tmp_path)
    assert (
        meta.craft == "crochet" and meta.terms == "US" and meta.terms_also == "UK" and meta.language == "en"
    )
    assert meta.stitches["sc"] == {
        "boundary": "turn",  # defaulted because chain is authored
        "chain": 1,
        "counts_as_stitch": False,
        "chain_color": "next",
        "first_stitch_in": 2,
    }
    assert meta.stitches["square"] == {
        "boundary": "join",
        "chain": 3,
        "name": "granny cluster",
        "unit": "tiles",
    }


def test_stitch_table_absent_means_nothing_authored():
    meta = load_pattern(FIX)
    assert meta.stitches == {}
    assert meta.craft == "" and meta.terms == "" and meta.terms_also == "" and meta.language == ""


def test_stitch_table_rejects_unknown_keys_and_bad_values(tmp_path):
    for body in (
        "[stitch.sc]\nturning_chain = 1\n",
        "[stitch.sc]\nchain = -1\n",
        '[stitch.sc]\nboundary = "flip"\nchain = 1\n',
        '[stitch.sc]\nboundary = "join"\n',
    ):
        (tmp_path / "pattern.toml").write_text((FIX / "pattern.toml").read_text() + "\n" + body)
        with pytest.raises(ValueError):
            load_pattern(tmp_path)
