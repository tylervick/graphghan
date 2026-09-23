# ProseReader

The Foundation Models reading experiment from the import spec
(`docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md` §9), in Swift so that it
can reach both of Apple's models: the on-device one and Private Cloud Compute. `prosereader`
reads a pattern's text and writes the `graphghan-import/1` document (`schema/import-prose.schema.json`)
that `graphghan import --prose` consumes. `ProseReaderKit` is the part a phone would carry for #112:
the `@Generable` shape of the document and the reading loop.

    cd ios/Packages/ProseReader
    swift build -c release                      # Xcode 27; macOS 26 or later at run time
    swift test
    .build/release/prosereader <pattern.pdf> --model ondevice --batch row --out prose.json
    .build/release/prosereader <build/import/<stem>/pages dir> --model cloud --batch page --out prose.json

`--model ondevice|cloud`, `--batch row|page` (one row per prompt is what a 4k window holds; a page
per prompt is for the 32k cloud window), `--reuse-session` (one session for the whole run; slower,
since every prompt then carries the transcript). Text comes from PDFKit for a PDF, or from the `pNN.txt` files
`graphghan import` stages, so both sides read the same characters.

`--chunk N` (default 4) reads long rows in parts; `--examples` adds the corpus's row grammars to the
instructions. Before any prompt, code rewrites what the model cannot keep: the row head becomes
"Row N:" whatever the page wrote ("Row 1.", "Row 3 -", "Rows 1-10:", "1st row:", or a bare "7." before
something that looks like a run), run spellings become "count colour" ("c2" → "2 c", "8sc in c1" → "8 A",
"sc 8 in white" and "(green) sc 10" → "8 white" and "10 green", a bare "(Pale Rose)" → "(Pale Rose) x 1"),
a bracketed group with a count and a starred "repeat from *" are expanded (to the previous row's width
for "across"), increases and decreases become stitch counts, foundation chains and turning phrases go,
adjacent counts of one colour add, row numbers come from the text's head, and key codes are A, B, C in
key order unless the rows print codes. A head that covers several rows ("Rows 2-4") yields one row per
number, and "Row 6: repeat row 5" copies row 5 without a prompt. A run whose code is neither a colour of the
document nor a word of the row is dropped, and a row left with none is reported as an error, not a guess.

`--sections` prints how the pages' rows fall into sections (a new one wherever the rows count from 1
again) and whether each names colours, without the model; `--height N` marks, or with `--model` reads
only, the section a chart N rows tall is checked by, as the app's check does (#176, #197, #198).

Scoring against ground truth: `uv run python Scripts/score.py prose.json craigh|orca` (Craigh na Dun's
rows come from our own PDF's text layer; Orca's from the hand transcript in `fixtures/import/real/`).

Measured on the mini (macOS 27, on-device model): Craigh na Dun 177 of 184 rows exact at 15 s a row;
Orca's front panel 77 of 77 with `--examples` (76 without) at 3 s a row; across the twenty-two
breadth patterns 815 of 903 rows (spec §9.2). The Python spike before these rewrites read 150 and 45.

`Scripts/breadth/` repeats the breadth measurement (spec §9.1 and §9.2, twenty-two patterns, 534 of
903 rows exact before the reader fixes, 815 after): `fetch.sh <work>` pulls the sourced pages as text, `truth.py <work>` builds the regex ground
truth, the tool writes `<work>/<id>.json` for each `<work>/<id>/` folder, and `table.py <work>` prints
the table. The Ravelry PDFs are fetched by hand (a login) into `<work>/pdf/`.

## Private Cloud Compute needs a managed entitlement

Unsigned, every cloud request fails at once with `FoundationModels.LanguageModelError -1` wrapping
`ModelManagerServices.ModelManagerError 1046`, before any network traffic. Signed with the team's
development identity (`codesign --force --sign "Apple Development" --options runtime
.build/release/prosereader`), the framework instead stops at launch:

    Fatal error: Missing entitlement: com.apple.developer.private-cloud-compute
    To develop with PCC you must meet certain eligibility requirements. To learn more and request
    access to the managed entitlement, sign into your Developer account and complete the
    entitlement request form. https://developer.apple.com/contact/request/private-cloud-compute/

So the cloud model is gated by a request to Apple, not by signing. Once the entitlement is granted
to the team, add it to a provisioning profile for a small macOS app target that wraps
`ProseReaderKit` (a bare SwiftPM tool carries no profile) and run `--model cloud --batch page`.

If the Mac has no development identity in its keychain, a build of any automatically signed
target with `xcodebuild -allowProvisioningUpdates` creates one through the signed-in Xcode account.
