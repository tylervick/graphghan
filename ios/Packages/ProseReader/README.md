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
per prompt is for the 32k cloud window), `--fresh-session` (a new session per prompt, the slow way
the Python spike did it). Text comes from PDFKit for a PDF, or from the `pNN.txt` files
`graphghan import` stages, so both sides read the same characters.

Scoring against ground truth: `uv run python Scripts/score.py prose.json craigh|orca` (Craigh na Dun's
rows come from our own PDF's text layer; Orca's from the hand transcript in `fixtures/import/real/`).

## Private Cloud Compute needs a signed, attributed process

On the build mini (macOS 27, Apple Intelligence on) `PrivateCloudComputeLanguageModel().availability`
is `.available` and the quota is below its limit, yet every request fails at once with
`FoundationModels.LanguageModelError -1` wrapping `ModelManagerServices.ModelManagerError 1046`, before
any network traffic. The binary is an ad-hoc-signed SwiftPM executable with no entitlements and no
team, and this account holds no signing identity (`security find-identity -v -p codesigning` finds
none), so the request cannot be attributed to a developer account, which is what the cloud tier
meters. Xcode 27's capability catalogue names no entitlement for the model, so team attribution
is the whole of it as far as we can tell.

To run the cloud half: on a Mac where Xcode is signed into the team (`DEVELOPMENT_TEAM 352UZEKYPP`
in `ios/project.yml`), sign the built tool with the development identity and run it again:

    codesign --force --sign "Apple Development" --options runtime .build/release/prosereader
    .build/release/prosereader <pages dir> --model cloud --batch page --out prose.json

If that still returns 1046, the model wants an app with a bundle identifier and a provisioning
profile rather than a bare tool, and the next step is a small macOS app target in `project.yml`
under automatic signing that wraps `ProseReaderKit`.
