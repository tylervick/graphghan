"""An on-device reader of a pattern's prose (spec §9, the optional spike): Apple's Foundation
Models through `apple-fm-sdk`, writing the same `graphghan-import/1` document the skill would.

macOS 27 with Apple Intelligence turned on, and the `apple` extra installed (`uv sync --extra
apple`). The model's context is 4k tokens and its patience for long structured output is short,
so the text is read page by page for the front matter and one written row per prompt for the
rows. Turning-chain tokens the model likes to keep ("ch 1", "turn") are dropped afterwards; the
counts are never touched, so the row-total check downstream still judges the reading.
"""

from __future__ import annotations

import asyncio
import re
from pathlib import Path

from .chartdoc import CODE_RE
from .importers import page_texts
from .prose import SCHEMA_ID

ROW_LINE = re.compile(r"^\s*(?:Row|ROW|R)\s*\.?\s*\d+\b")
NOT_A_RUN = {"ch", "turn", "sl", "st", "sts", "fsc", "fdc", "sc", "hdc", "dc"}
FRONT_CHARS = 5000  # about a page of text fits the 4k context with the schema and the answer


def available() -> tuple[bool, str]:
    """Whether the on-device model can answer here: (ok, reason when not)."""
    try:
        import apple_fm_sdk as fm
    except ImportError:
        return False, "apple-fm-sdk is not installed (uv sync --extra apple, macOS 27 only)"
    try:
        ok, reason = fm.SystemLanguageModel().is_available()
    except Exception as e:  # the framework is missing or refuses to load
        return False, str(e)
    return bool(ok), "" if ok else str(reason)


_SCHEMAS: tuple | None = None


def _schemas():
    """The guided-generation types, built once the SDK is known to import. They are placed in this
    module's globals as they are defined because the decorator resolves `list[Run]` by name."""
    global _SCHEMAS
    if _SCHEMAS is not None:
        return _SCHEMAS
    import apple_fm_sdk as fm

    @fm.generable
    class Run:
        """One run of stitches in a written crochet row"""

        count: int = fm.guide("the number of stitches in this run")
        code: str = fm.guide(
            "the colour exactly as the row names it: a code such as A or a name such as White"
        )

    globals()["Run"] = Run

    @fm.generable
    class WrittenRow:
        """One written row of a crochet chart, transcribed exactly as printed"""

        row: int = fm.guide("the row number")
        runs: list[Run] = fm.guide("every run in the order printed; do not add, merge or correct any")
        total: int = fm.guide("the stitch count the row prints at its end, or 0 when it prints none")

    @fm.generable
    class Colour:
        """One colour of the pattern's key"""

        code: str = fm.guide("the letter or short code the pattern uses, or the name when it has none")
        name: str = fm.guide("the colour's name as printed")
        hex: str = fm.guide("the hex colour as #rrggbb when the key prints one, else empty")

    globals()["Colour"] = Colour

    @fm.generable
    class Front:
        """A crochet pattern's front matter: what it is, what it needs, how big"""

        title: str = fm.guide("the pattern's title, or empty")
        author: str = fm.guide("the designer, or empty")
        hook: str = fm.guide("the hook size as printed, or empty")
        yarn_weight: str = fm.guide("the yarn weight or yarn named, or empty")
        gauge_stitches: int = fm.guide("stitches in the gauge, or 0")
        gauge_rows: int = fm.guide("rows in the gauge, or 0")
        gauge_over: int = fm.guide("the length the gauge is measured over, or 0")
        gauge_unit: str = fm.guide("in or cm", anyOf=["in", "cm", ""])
        stitch: str = fm.guide("the stitch the chart is worked in, as its abbreviation such as sc, or empty")
        width: int = fm.guide("the chart's width in stitches when stated, or 0")
        height: int = fm.guide("the chart's height in rows when stated, or 0")
        colours: list[Colour] = fm.guide("the colour key, in the order printed; empty when the page has none")

    _SCHEMAS = (fm, WrittenRow, Front)
    return _SCHEMAS


def _row_blocks(text: str) -> list[str]:
    """Each written row's text on a page, wrapped continuation lines rejoined."""
    blocks: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if ROW_LINE.match(line):
            blocks.append(line)
        elif blocks and (line[0].isdigit() or ", " in line) and not blocks[-1].endswith((".", ":")):
            blocks[-1] += " " + line  # a wrapped row continues with a count; a footer does not
    return blocks


def _clean_runs(runs, key: dict[str, str] | None) -> list[list]:
    out: list[list] = []
    for r in runs:
        code = str(r.code).strip()
        if code.lower() in NOT_A_RUN or int(r.count) <= 0:
            continue
        if key:
            code = key.get(code.lower(), key.get(code, code))
        if not CODE_RE.match(code):
            code = re.sub(r"[^A-Za-z]", "", code)[:3] or "X"
        if out and out[-1][0] == code:
            out[-1][1] += int(r.count)
        else:
            out.append([code, int(r.count)])
    return out


async def _read_rows(texts: list[str], key: dict[str, str] | None, progress=None) -> list[dict]:
    fm, WrittenRow, _ = _schemas()
    instructions = (
        "You transcribe one written crochet row into structured data exactly as printed. "
        "A run is a count and a colour; a turning chain (ch 1, turn) is not a run. Never correct a number."
    )
    rows: list[dict] = []
    for page_no, text in enumerate(texts, start=1):
        for block in _row_blocks(text):
            session = fm.LanguageModelSession(instructions=instructions)
            try:
                got = await session.respond("Transcribe this row:\n" + block, generating=WrittenRow)
            except Exception as e:  # a refusal or a decode failure on one row must not lose the rest
                rows.append({"row": 0, "page": page_no, "text": block, "runs": [], "error": str(e)[:200]})
                continue
            entry = {"row": int(got.row), "page": page_no, "text": block, "runs": _clean_runs(got.runs, key)}
            if int(got.total) > 0:
                entry["total"] = int(got.total)
            rows.append(entry)
            if progress:
                progress(entry)
    return rows


async def _read_front(texts: list[str]) -> dict:
    fm, _, Front = _schemas()
    session = fm.LanguageModelSession(
        instructions="You read a crochet pattern's front matter and answer only from what the text says; leave what it does not say empty or 0."
    )
    doc: dict = {"schema": SCHEMA_ID}
    for text in texts[:3]:
        if not text.strip():
            continue
        try:
            got = await session.respond("Read this page:\n" + text[:FRONT_CHARS], generating=Front)
        except Exception:
            continue
        pattern = {k: v for k, v in (("title", got.title), ("author", got.author)) if v}
        doc.setdefault("pattern", {}).update(
            {k: v for k, v in pattern.items() if k not in doc.get("pattern", {})}
        )
        gauge = doc.setdefault("gauge", {})
        if (
            got.gauge_stitches
            and got.gauge_rows
            and got.gauge_over
            and got.gauge_unit
            and "stitches" not in gauge
        ):
            gauge.update(
                stitches=int(got.gauge_stitches),
                rows=int(got.gauge_rows),
                over={"value": int(got.gauge_over), "unit": got.gauge_unit},
            )
        for k, v in (("hook", got.hook), ("yarn_weight", got.yarn_weight), ("stitch", got.stitch)):
            if v and k not in gauge:
                gauge[k] = v
        chart = doc.setdefault("chart", {"row1": "bottom-right"})
        if got.width and got.height and "width" not in chart:
            chart.update(width=int(got.width), height=int(got.height))
        if got.colours and "palette" not in doc:
            palette = []
            for i, c in enumerate(got.colours):
                code = c.code.strip() if CODE_RE.match(c.code.strip()) else chr(ord("A") + i)
                entry = {"code": code, "name": c.name or c.code, "key_label": c.name or c.code}
                if re.fullmatch(r"#[0-9a-fA-F]{6}", c.hex.strip()):
                    entry["hex"] = c.hex.strip().lower()
                palette.append(entry)
            doc["palette"] = palette
    if not doc.get("gauge"):
        doc.pop("gauge", None)
    if not doc.get("pattern"):
        doc.pop("pattern", None)
    return doc


def prose_from_pdf(pdf_path: str | Path, progress=None) -> dict:
    """The prose document the on-device model reads off the PDF's text layer."""
    ok, reason = available()
    if not ok:
        raise RuntimeError(f"the on-device reader is not available: {reason}")
    texts = page_texts(pdf_path)

    async def main():
        doc = await _read_front(texts)
        key = {p["key_label"].lower(): p["code"] for p in doc.get("palette", []) if p.get("key_label")}
        rows = await _read_rows(texts, key or None, progress)
        if rows:
            doc["written_rows"] = rows
        doc.setdefault("uncertain", []).append(
            "read by the on-device model (apple-fm-sdk); numbers were transcribed one row at a time and not checked by the model"
        )
        return doc

    return asyncio.run(main())
