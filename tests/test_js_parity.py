"""The PWA's sequencer and cell-kind noun must agree with the Python ones on every chart fixture.

site/src/app/data.js is a hand-written mirror of graphghan.chartdoc.sequence and .cell_kind;
nothing else keeps the two from drifting. Node is pinned in mise.toml; without it on PATH this
test skips.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from graphghan import chartdoc

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "chart-format"
NAMES = sorted(p.name[: -len(".chart.json")] for p in FIX.glob("*.chart.json"))
NODE = shutil.which("node")

SCRIPT = """
import { readFileSync } from 'node:fs';
import { sequence } from './site/src/app/data.js';
const doc = JSON.parse(readFileSync(process.env.FIXTURE, 'utf8'));
process.stdout.write(JSON.stringify(sequence(doc)));
"""

pytestmark = pytest.mark.skipif(
    NODE is None, reason="node is not on PATH (mise.toml pins it; run `mise install`)"
)


def js_sequence(path: Path):
    r = subprocess.run(
        [NODE, "--input-type=module", "-e", SCRIPT],
        cwd=ROOT,
        env={"FIXTURE": str(path), "PATH": str(Path(NODE).parent)},
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def as_python(passes):
    """The JS shape with Python's key: gridRow -> grid_row. Missing values are null/None in both."""
    return [
        {
            "label": p["label"],
            "side": p["side"],
            "direction": p["direction"],
            "grid_row": p["gridRow"],
            "runs": [{"code": r["code"], "count": r["count"], "x0": r["x0"]} for r in p["runs"]],
        }
        for p in passes
    ]


@pytest.mark.parametrize("name", NAMES)
def test_js_sequence_matches_python(name):
    path = FIX / f"{name}.chart.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    js = js_sequence(path)
    try:
        expected = chartdoc.sequence(doc)
    except chartdoc.UnsupportedTechnique:
        assert js is None, "Python refuses to sequence this chart; the PWA must return null too"
        return
    assert js is not None, "Python sequences this chart; the PWA must not return null"
    assert as_python(js) == expected


# The plural of every graphghan.chartdoc.CELL_KINDS value, exactly as site/src/app/data.js's
# CELL_KIND_NOUNS and Swift's CellKind.nounPlural also spell them.
CELL_NOUNS = {"stitch": "stitches", "block": "blocks", "tile": "tiles", "motif": "motifs", "pair": "pairs"}

CELL_NOUN_SCRIPT = """
import { readFileSync } from 'node:fs';
import { cellNoun } from './site/src/app/data.js';
const doc = JSON.parse(readFileSync(process.env.FIXTURE, 'utf8'));
process.stdout.write(cellNoun(doc.chart));
"""


def js_cell_noun(path: Path) -> str:
    r = subprocess.run(
        [NODE, "--input-type=module", "-e", CELL_NOUN_SCRIPT],
        cwd=ROOT,
        env={"FIXTURE": str(path), "PATH": str(Path(NODE).parent)},
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return r.stdout


@pytest.mark.parametrize("name", NAMES)
def test_js_cell_noun_matches_python(name):
    path = FIX / f"{name}.chart.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    assert js_cell_noun(path) == CELL_NOUNS[chartdoc.cell_kind(doc)]


FINISHED_SIZE_SCRIPT = """
import { readFileSync } from 'node:fs';
import { finishedSize } from './site/src/app/data.js';
const doc = JSON.parse(readFileSync(process.env.FIXTURE, 'utf8'));
process.stdout.write(JSON.stringify(finishedSize(doc)));
"""


def js_finished_size(path: Path):
    r = subprocess.run(
        [NODE, "--input-type=module", "-e", FINISHED_SIZE_SCRIPT],
        cwd=ROOT,
        env={"FIXTURE": str(path), "PATH": str(Path(NODE).parent)},
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


@pytest.mark.parametrize("name", NAMES)
def test_js_finished_size_matches_python(name):
    """finishedSize withholds a size exactly when gauge.unit and chart.cell.kind disagree (#48);
    both languages must agree on *when* a size derives, not just what it is when they do."""
    path = FIX / f"{name}.chart.json"
    doc = json.loads(path.read_text(encoding="utf-8"))
    expected = chartdoc.finished_size(doc)
    js = js_finished_size(path)
    if expected is None:
        assert js is None, "Python withholds the size; the PWA must return null too"
        return
    assert js is not None, "Python derives a size; the PWA must not return null"
    assert [js["w"], js["h"], js["unit"]] == list(expected)
