"""The `.graphghan` bundle: a pattern as one file, for Files, Mail and AirDrop.

A zip with `pattern.json` at the root plus exactly the files that manifest references -- the
pattern preview and, per published chart, its `chart.json` and `preview.png`. The site tree also
carries `chart.png` and `written-rows.txt`; the manifest names neither and the app reads neither,
so leaving them out halves the file.

The output is byte-reproducible, which costs two decisions (see the design spec §3.2):

* Entries are **stored**, not deflated. pytest runs on ubuntu and the committed fixture is
  generated on a Mac; zlib's deflate output is deterministic for one zlib build but not across
  builds (several distributions now ship Python against zlib-ng), so a deflated fixture would
  pass locally and drift in CI. The payload is mostly already-compressed PNG, so stored costs
  about 15 KB on a 70 KB bundle. The iOS reader handles deflate anyway, for bundles written
  elsewhere.
* The manifest's `updated`, which the site build stamps with the build time, is fixed. There is no
  build time available in a checkout that is stable across clones, and nothing reads the field: a
  bundle is content, not a build.
"""

from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

from .manifest import manifest, published_docs

#: The earliest instant a zip entry can carry, used for every entry and for the manifest's
#: `updated` so the two agree about a bundle having no build time.
BUNDLE_EPOCH = (1980, 1, 1, 0, 0, 0)
BUNDLE_UPDATED = "1980-01-01T00:00:00Z"

MANIFEST_NAME = "pattern.json"


def bundle_files(pattern_dir: str | Path) -> dict[str, bytes]:
    """{entry name: bytes} for a bundle of this pattern: the manifest and everything it names.

    Read from the *committed* dist/, never a fresh render, for the same reason `export --format
    pdf` is: what ships has to be what `render --check` guards.
    """
    d = Path(pattern_dir)
    dist = d / "dist"
    if not (dist / "chart.json").exists():
        raise FileNotFoundError(f"no committed chart at {dist / 'chart.json'}; run 'graphghan render' first")
    doc = manifest(published_docs(d), BUNDLE_UPDATED)
    # The manifest's paths are relative to the pattern's directory on the site, and dist/ has the
    # same shape, so one path reads both.
    wanted = [doc["preview"]]
    for chart in doc["charts"]:
        wanted.extend([chart["path"], chart["preview"]])
    files: dict[str, bytes] = {MANIFEST_NAME: json.dumps(doc).encode("utf-8")}
    for name in wanted:
        src = dist / name
        if not src.exists():
            raise FileNotFoundError(f"{d.name}: pattern.json references {name}, which is not in dist/")
        files[name] = src.read_bytes()
    return files


def to_bundle(pattern_dir: str | Path) -> bytes:
    """The bundle as bytes. Two calls on one pattern give identical output, on any platform."""
    files = bundle_files(pattern_dir)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, date_time=BUNDLE_EPOCH)
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o644 << 16
            info.create_system = 0  # MS-DOS, so the mode above is the only thing that varies
            z.writestr(info, files[name])
    return buf.getvalue()
