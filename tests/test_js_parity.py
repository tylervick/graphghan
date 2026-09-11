"""The PWA's sequencer must agree with the Python one, pass for pass, on every chart fixture.

site/src/app/data.js is a hand-written mirror of graphghan.chartdoc.sequence; nothing else keeps
the two from drifting. Node is pinned in mise.toml; without it on PATH this test skips.
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
