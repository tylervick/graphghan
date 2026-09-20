# TestFlight Feedback → GitHub Issues Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every TestFlight screenshot submission and crash submission for the app becomes one GitHub issue, labelled and with the screenshot or crash log attached, and never twice.

**Architecture:** A scheduled GitHub Actions workflow runs `ios/Scripts/testflight-feedback.sh` every 30 minutes on Ubuntu. The script mints an App Store Connect token with the existing `asc-jwt.sh`, lists submissions, skips those already tracked (found by label plus a hidden marker in the issue body, not by search), uploads screenshots as assets on a permanent `testflight-feedback` pre-release so the issue can embed a stable image URL, and opens one issue per submission with `gh`. A hermetic shell test stubs `curl` and `gh`.

**Tech Stack:** bash (must run under macOS `/bin/bash` 3.2 for the tests and Ubuntu bash 5 in CI), `curl`, `python3` (JSON), `gh`, GitHub Actions, App Store Connect API v1.

**Spec:** GitHub issue #113 ("Bridge TestFlight feedback into GitHub Issues") plus the design section below. There is no separate spec file.

## Design (read before any task)

- **Endpoints** (verified against Apple's docs on 2026-09-19):
  - `GET /v1/apps?filter[bundleId]=com.tylervick.graphghan` → `data[0].id` is the app id.
  - `GET /v1/apps/{app}/betaFeedbackScreenshotSubmissions?sort=-createdDate&limit=50&include=build&fields[builds]=version`
  - `GET /v1/apps/{app}/betaFeedbackCrashSubmissions?sort=-createdDate&limit=50&include=build&fields[builds]=version`
  - `GET /v1/betaFeedbackCrashSubmissions/{id}/crashLog` → `data.attributes.logText`.
  - Submission attributes used: `createdDate`, `comment`, `deviceModel`, `osVersion`, `locale`, `screenshots[].url` (screenshot kind only; the URLs expire). `relationships.build.data.id` joins to `included[type=builds].attributes.version` (the build number).
  - Attributes deliberately **never** read: `email` and the `tester` relationship. The repository is public.
- **Idempotency:** every issue the script opens carries the label `testflight-feedback` and ends with `<!-- testflight-feedback:<submission id> -->`. Before creating anything the script lists issues by that label through `gh issue list` (REST/GraphQL, consistent) and collects the ids; GitHub *search* is not used because its index lags a fresh issue and would cause duplicates on back-to-back runs.
- **Screenshots:** downloaded, then uploaded with `gh release upload` to a pre-release tagged `testflight-feedback` (created on first need). Embedded as `![screenshot N](https://github.com/<repo>/releases/download/testflight-feedback/<id>-<N>.png)`. No branch of PNGs, no clone bloat.
- **Issue shape:** labels `bug`, `ios`, `testflight-feedback`. Title is the comment's first line (max 72 chars) or `TestFlight feedback on build N (device, os)`; crashes are `Crash on build N (device, os): first line`. Body sections: Feedback/Crash, images, collapsed crash log (max 50 000 chars inside a four-backtick fence), Where (build, device, OS, locale, sent), a link to App Store Connect, the marker.
- **Order:** oldest submission first, so issue numbers follow arrival order.
- **Dry run:** `--dry-run` lists what would be created and creates nothing (no label, release, upload, or issue).

## Global Constraints

- Scripts live in `ios/Scripts/`, are `#!/bin/bash` with `set -euo pipefail`, carry a header comment explaining *why* (see `asc-jwt.sh`), and have a sibling `test-<name>.sh` that `mise run script-test` (from `ios/`) picks up automatically.
- No bash 4 features (macOS ships 3.2): no `mapfile`, no associative arrays, no `${var,,}`.
- JSON is handled with `python3` heredocs, as in `whats-to-test.sh`; no `jq`.
- Workflow actions are pinned to commit SHAs (zizmor enforces it); reuse the `actions/checkout` SHA already in `.github/workflows/ci.yml`. `permissions: {}` at the top, per-job grants only.
- Never put a secret or token in a `run:` string; pass via `env:`.
- The tester's email or name must not appear in any issue title or body. A test asserts this.
- Branch `feat/testflight-feedback`, worktree under `.worktrees/`, PR to `main` with `Closes #113`.
- Run `mise run lint` at the repo root before every commit that touches `.github/` (hk runs actionlint and zizmor).

---

### Task 1: Test harness and the screenshot path (no images yet)

**Files:**
- Create: `ios/Scripts/testflight-feedback.sh`
- Create: `ios/Scripts/test-testflight-feedback.sh`

**Interfaces:**
- Produces: `ios/Scripts/testflight-feedback.sh [--dry-run]`, env `ASC_JWT` (path to a token-minting script, default `asc-jwt.sh`), `GITHUB_REPOSITORY` (`owner/name`), `TESTFLIGHT_FEEDBACK_LIMIT` (default 50). Exit 0 on success, 1 on any API or `gh` failure, 2 on bad usage. Prints `created: <url>` per issue and a final `N created, M already tracked.` line.
- The test harness (`STUB_DIR`, the `curl` and `gh` stubs, `run_script`, `reset`) is reused by every later task.

- [ ] **Step 1: Write the failing test**

Create `ios/Scripts/test-testflight-feedback.sh`:

```bash
#!/bin/bash
# Hermetic tests for testflight-feedback.sh: curl and gh are stubs on PATH that answer from fixtures
# under $STUB_DIR and log every call, so each case asserts on what the script asked for and what it
# would have created. Nothing here touches App Store Connect or GitHub.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

export STUB_DIR="$TMP/stub"
BIN="$TMP/bin"
mkdir -p "$STUB_DIR" "$BIN"

# --- stubs -------------------------------------------------------------------------------------

cat > "$BIN/asc-jwt" <<'EOF'
#!/bin/bash
echo tok
EOF

cat > "$BIN/curl" <<'EOF'
#!/bin/bash
# Answers App Store Connect and screenshot downloads from fixtures; logs every URL.
out=""; url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift ;;
        -H|-X) shift ;;
        http*) url="$1" ;;
    esac
    shift
done
echo "$url" >> "$STUB_DIR/curl.log"
case "$url" in
    */v1/apps\?*)                              cat "$STUB_DIR/apps.json" ;;
    */betaFeedbackScreenshotSubmissions\?*)    cat "$STUB_DIR/screenshots.json" ;;
    */betaFeedbackCrashSubmissions\?*)         cat "$STUB_DIR/crashes.json" ;;
    */betaFeedbackCrashSubmissions/*/crashLog) cat "$STUB_DIR/crashlog.json" ;;
    https://shots.example/*)                   printf 'PNG' > "$out" ;;
    *) echo "curl stub: unexpected url $url" >&2; exit 22 ;;
esac
EOF

cat > "$BIN/gh" <<'EOF'
#!/bin/bash
# Records every invocation; serves the already-tracked issue bodies; captures created issues.
printf '%s\n' "$*" >> "$STUB_DIR/gh.log"
case "$1 $2" in
    "issue list") cat "$STUB_DIR/bodies.txt" 2>/dev/null || true ;;
    "issue create")
        title=""; body=""
        while [ $# -gt 0 ]; do
            case "$1" in --title) title="$2"; shift ;; --body-file) body="$2"; shift ;; esac
            shift
        done
        n="$(ls "$STUB_DIR"/created-*.md 2>/dev/null | wc -l | tr -d ' ')"; n=$((n + 1))
        printf '%s\n' "$title" > "$STUB_DIR/created-$n.title"
        cp "$body" "$STUB_DIR/created-$n.md"
        echo "https://github.com/tylervick/graphghan/issues/$n" ;;
    "release view")   [ -f "$STUB_DIR/release-exists" ] ;;
    "release create") touch "$STUB_DIR/release-exists" ;;
    "release upload") ;;
    "label create")   ;;
    *) echo "gh stub: unexpected: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$BIN"/*

# --- fixtures ----------------------------------------------------------------------------------

cat > "$STUB_DIR/apps.json" <<'EOF'
{"data":[{"type":"apps","id":"APP1"}]}
EOF

# Two screenshot submissions, newest first as Apple returns them. Both carry the tester's email,
# which must never reach an issue. S-OLD has no comment and two screenshots; S-NEW has a
# two-line comment and one screenshot.
cat > "$STUB_DIR/screenshots.json" <<'EOF'
{"data":[
 {"type":"betaFeedbackScreenshotSubmissions","id":"S-NEW",
  "attributes":{"createdDate":"2026-09-19T14:03:11Z","comment":"Done button hides behind the strip\nHappens after rotating.","email":"tester@example.com","deviceModel":"iPhone17,1","osVersion":"26.0","locale":"en-US",
   "screenshots":[{"url":"https://shots.example/one.png","width":1179,"height":2556,"expirationDate":"2026-09-20T00:00:00Z"}]},
  "relationships":{"build":{"data":{"type":"builds","id":"B12"}}}},
 {"type":"betaFeedbackScreenshotSubmissions","id":"S-OLD",
  "attributes":{"createdDate":"2026-09-18T09:00:00Z","comment":"","email":"tester@example.com","deviceModel":"iPhone17,1","osVersion":"26.0","locale":"en-US",
   "screenshots":[{"url":"https://shots.example/a.png"},{"url":"https://shots.example/b.png"}]},
  "relationships":{"build":{"data":{"type":"builds","id":"B12"}}}}
],"included":[{"type":"builds","id":"B12","attributes":{"version":"12"}}]}
EOF

# No crash submissions until Task 4 adds them.
cat > "$STUB_DIR/crashes.json" <<'EOF'
{"data":[],"included":[]}
EOF

# --- helpers -----------------------------------------------------------------------------------

reset() { rm -f "$STUB_DIR"/*.log "$STUB_DIR"/created-* "$STUB_DIR/bodies.txt" "$STUB_DIR/release-exists"; }
run_script() { # args... -> stdout+stderr
    PATH="$BIN:$PATH" ASC_JWT="$BIN/asc-jwt" GITHUB_REPOSITORY=tylervick/graphghan \
        "$HERE/testflight-feedback.sh" "$@" 2>&1
}
created_count() { ls "$STUB_DIR"/created-*.md 2>/dev/null | wc -l | tr -d ' '; }

# --- cases -------------------------------------------------------------------------------------

reset
out="$(run_script)" || fail "fresh run exited non-zero: $out"
[ "$(created_count)" -eq 2 ] || fail "expected 2 issues, created $(created_count); output: $out"
grep -q "^2 created, 0 already tracked\.$" <<<"$out" || fail "summary line missing; got: $out"
pass "a fresh run opens one issue per screenshot submission"

# Oldest first: S-OLD (2026-09-18) is issue 1, S-NEW is issue 2.
grep -q "testflight-feedback:S-OLD" "$STUB_DIR/created-1.md" || fail "issue 1 is not S-OLD"
grep -q "testflight-feedback:S-NEW" "$STUB_DIR/created-2.md" || fail "issue 2 is not S-NEW"
pass "submissions are created oldest first"

[ "$(cat "$STUB_DIR/created-2.title")" = "Done button hides behind the strip" ] || fail "title should be the comment's first line; got: $(cat "$STUB_DIR/created-2.title")"
[ "$(cat "$STUB_DIR/created-1.title")" = "TestFlight feedback on build 12 (iPhone17,1, 26.0)" ] || fail "fallback title wrong; got: $(cat "$STUB_DIR/created-1.title")"
pass "titles come from the first comment line, with a build/device fallback"

body="$(cat "$STUB_DIR/created-2.md")"
grep -q "^### Feedback$" <<<"$body" || fail "Feedback heading missing"
grep -q "Happens after rotating\." <<<"$body" || fail "full comment missing from body"
grep -q -- "- Build: 12$" <<<"$body" || fail "build number missing (included builds not joined)"
grep -q -- "- Device: iPhone17,1 (26.0)$" <<<"$body" || fail "device line missing"
grep -q -- "- Locale: en-US$" <<<"$body" || fail "locale line missing"
grep -q -- "- Sent: 2026-09-19T14:03:11Z$" <<<"$body" || fail "sent line missing"
grep -q "appstoreconnect.apple.com/apps/APP1/testflight" <<<"$body" || fail "App Store Connect link missing"
grep -q "<!-- testflight-feedback:S-NEW -->" <<<"$body" || fail "marker missing"
grep -q "_No comment\._" "$STUB_DIR/created-1.md" || fail "empty comment placeholder missing"
pass "the body has the comment, the Where block, the link, and the marker"

grep -q -- "--label bug,ios,testflight-feedback" "$STUB_DIR/gh.log" || fail "labels missing from issue create; log: $(cat "$STUB_DIR/gh.log")"
grep -q "^label create testflight-feedback" "$STUB_DIR/gh.log" || fail "the feedback label is not ensured"
pass "issues carry bug, ios, and testflight-feedback, and the label is ensured first"

! grep -rq "tester@example.com" "$STUB_DIR"/created-* || fail "the tester's email reached an issue"
! grep -q "email" "$STUB_DIR"/created-*.md || fail "the word email appears in a body"
pass "the tester's identity never reaches an issue"

grep -q "betaFeedbackScreenshotSubmissions?sort=-createdDate&limit=50&include=build&fields%5Bbuilds%5D=version" "$STUB_DIR/curl.log" || fail "listing query wrong; log: $(cat "$STUB_DIR/curl.log")"
pass "the listing asks for newest-first with the build version included"

echo "all testflight-feedback tests passed"
```

- [ ] **Step 2: Run it to verify it fails**

Run from `ios/`: `chmod +x Scripts/test-testflight-feedback.sh && Scripts/test-testflight-feedback.sh`
Expected: `FAIL: fresh run exited non-zero: ... No such file or directory` (the script does not exist yet).

- [ ] **Step 3: Write the script**

Create `ios/Scripts/testflight-feedback.sh`:

```bash
#!/bin/bash
# Imports TestFlight tester feedback (screenshot submissions and crash submissions) from App Store
# Connect into GitHub Issues: one issue per submission, never the same submission twice.
#
# Reads from the environment (see asc-jwt.sh): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH. Needs
# `gh` authenticated for the repository (GH_TOKEN in Actions, the keyring locally), `curl`, and
# `python3`. GITHUB_REPOSITORY (set by Actions) names the repo; locally it is read from the checkout.
#
# Usage: ios/Scripts/testflight-feedback.sh [--dry-run]
#   --dry-run  print what would be created; touch nothing on GitHub.
#
# WHY TRACKED ISSUES ARE FOUND BY LABEL, NOT SEARCH: GitHub's search index lags a fresh issue by
# seconds to minutes, so two runs close together would open the same submission twice. Listing
# issues by label is served consistently, and every issue this script opens carries the label plus a
# hidden `<!-- testflight-feedback:<id> -->` marker in its body that the next run reads back.
#
# WHY SCREENSHOTS BECOME RELEASE ASSETS: Apple's screenshot URLs expire, an issue body cannot hold
# an image, and PNGs committed to a branch ride along with every clone. Assets on the permanent
# `testflight-feedback` pre-release have a stable URL and cost clones nothing.
#
# The tester's email is never read out of the response: the repository is public.
set -euo pipefail

IOS="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$IOS/.." && pwd)"
cd "$ROOT"

API="https://api.appstoreconnect.apple.com"
BUNDLE_ID="com.tylervick.graphghan"
RELEASE_TAG="testflight-feedback"
FEEDBACK_LABEL="testflight-feedback"
ISSUE_LABELS="bug,ios,$FEEDBACK_LABEL"
LIMIT="${TESTFLIGHT_FEEDBACK_LIMIT:-50}"
ASC_JWT="${ASC_JWT:-$IOS/Scripts/asc-jwt.sh}"

DRY_RUN=0
case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    '') ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

REPO="${GITHUB_REPOSITORY:-}"
[ -n "$REPO" ] || REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

api_get() { curl -sS -f -H "Authorization: Bearer $TOKEN" "$API$1"; }
field() { printf '%s' "$REC" | python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

# One JSON object per line, oldest first, only the fields an issue needs. `email` and the tester
# relationship are not on this list on purpose.
normalize() { # response-file, kind
    python3 - "$1" "$2" <<'EOF'
import json, sys
path, kind = sys.argv[1], sys.argv[2]
doc = json.load(open(path))
builds = {b["id"]: (b.get("attributes") or {}).get("version", "")
          for b in doc.get("included") or [] if b.get("type") == "builds"}
rows = []
for item in doc.get("data") or []:
    a = item.get("attributes") or {}
    build = ((item.get("relationships") or {}).get("build") or {}).get("data") or {}
    rows.append({
        "id": item["id"],
        "kind": kind,
        "created": a.get("createdDate") or "",
        "comment": a.get("comment") or "",
        "device": a.get("deviceModel") or "",
        "os": a.get("osVersion") or "",
        "locale": a.get("locale") or "",
        "build": builds.get(build.get("id", ""), ""),
        "screenshots": [s.get("url", "") for s in (a.get("screenshots") or []) if s.get("url")],
    })
rows.sort(key=lambda r: r["created"])
for r in rows:
    print(json.dumps(r))
EOF
}

# Writes $TMP/title and $TMP/body.md from $REC plus IMAGE_URLS (one per line) and CRASH_LOG_FILE.
render() {
    REC="$REC" IMAGE_URLS="${IMAGE_URLS:-}" CRASH_LOG_FILE="${CRASH_LOG_FILE:-}" APP_ID="$APP_ID" OUT="$TMP" python3 - <<'EOF'
import json, os
r = json.loads(os.environ["REC"])
out = os.environ["OUT"]
comment = r["comment"].strip()
first = comment.splitlines()[0].strip() if comment else ""
if len(first) > 72:
    first = first[:71].rstrip() + "…"
build = r["build"] or "?"
where = f"build {build}" + (f" ({r['device']}, {r['os']})" if r["device"] else "")
if r["kind"] == "crash":
    title = f"Crash on {where}" + (f": {first}" if first else "")
else:
    title = first or f"TestFlight feedback on {where}"

lines = ["### Crash" if r["kind"] == "crash" else "### Feedback", comment or "_No comment._", ""]
for i, url in enumerate([u for u in os.environ["IMAGE_URLS"].splitlines() if u], 1):
    lines += [f"![screenshot {i}]({url})", ""]
log_path = os.environ["CRASH_LOG_FILE"]
if log_path:
    log = open(log_path, encoding="utf-8", errors="replace").read().rstrip("\n")
    if len(log) > 50000:
        log = log[:50000] + "\n… truncated; the full log is in App Store Connect."
    # Four backticks: a crash log may itself contain a three-backtick run.
    lines += ["<details><summary>Crash log</summary>", "", "````", log, "````", "", "</details>", ""]
lines += [
    "### Where",
    f"- Build: {build}",
    f"- Device: {r['device'] or '?'} ({r['os'] or '?'})",
    f"- Locale: {r['locale'] or '?'}",
    f"- Sent: {r['created'] or '?'}",
    "",
    f"Imported from [App Store Connect › TestFlight](https://appstoreconnect.apple.com/apps/{os.environ['APP_ID']}/testflight/ios) by `ios/Scripts/testflight-feedback.sh`.",
    "",
    f"<!-- testflight-feedback:{r['id']} -->",
    "",
]
open(os.path.join(out, "title"), "w").write(title)
open(os.path.join(out, "body.md"), "w").write("\n".join(lines))
EOF
}

TOKEN="$("$ASC_JWT")" || { echo "error: could not mint an App Store Connect token" >&2; exit 1; }
if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::$TOKEN"; fi

APPS_RESP="$(api_get "/v1/apps?filter%5BbundleId%5D=$BUNDLE_ID")" || { echo "error: could not resolve the app id for $BUNDLE_ID" >&2; exit 1; }
APP_ID="$(printf '%s' "$APPS_RESP" | python3 -c 'import json, sys; d = json.load(sys.stdin).get("data") or []; print(d[0]["id"] if d else "")')"
[ -n "$APP_ID" ] || { echo "error: App Store Connect has no app with bundle id $BUNDLE_ID" >&2; exit 1; }

QUERY="sort=-createdDate&limit=$LIMIT&include=build&fields%5Bbuilds%5D=version"
api_get "/v1/apps/$APP_ID/betaFeedbackScreenshotSubmissions?$QUERY" > "$TMP/screenshots.json" || { echo "error: could not list screenshot submissions" >&2; exit 1; }
normalize "$TMP/screenshots.json" screenshot > "$TMP/submissions.jsonl"

if [ "$DRY_RUN" -eq 0 ]; then
    gh label create "$FEEDBACK_LABEL" --repo "$REPO" --color 0e8a16 \
        --description "Imported from TestFlight by ios/Scripts/testflight-feedback.sh" --force >/dev/null \
        || { echo "error: could not ensure the $FEEDBACK_LABEL label" >&2; exit 1; }
fi

# The seen set. A failure here must stop the run: without it every submission looks new.
gh issue list --repo "$REPO" --label "$FEEDBACK_LABEL" --state all --limit 1000 --json body -q '.[].body' > "$TMP/bodies" \
    || { echo "error: could not list existing feedback issues; refusing to run without the seen set" >&2; exit 1; }
{ grep -o "testflight-feedback:[A-Za-z0-9._-]*" "$TMP/bodies" || true; } | sed 's/^testflight-feedback://' | sort -u > "$TMP/seen"

created=0; skipped=0
while IFS= read -r REC; do
    [ -n "$REC" ] || continue
    ID="$(field id)"
    if grep -qx "$ID" "$TMP/seen"; then skipped=$((skipped + 1)); continue; fi

    IMAGE_URLS=""
    CRASH_LOG_FILE=""
    render

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "would create: $(cat "$TMP/title")"
    else
        url="$(gh issue create --repo "$REPO" --title "$(cat "$TMP/title")" --label "$ISSUE_LABELS" --body-file "$TMP/body.md")" \
            || { echo "error: could not create an issue for submission $ID" >&2; exit 1; }
        echo "created: $url"
        echo "$ID" >> "$TMP/seen"
    fi
    created=$((created + 1))
done < "$TMP/submissions.jsonl"

if [ "$DRY_RUN" -eq 1 ]; then echo "$created would be created, $skipped already tracked."
else echo "$created created, $skipped already tracked."; fi
```

Then `chmod +x ios/Scripts/testflight-feedback.sh`.

- [ ] **Step 4: Run the test to verify it passes**

Run from `ios/`: `Scripts/test-testflight-feedback.sh`
Expected: seven `ok - ...` lines and `all testflight-feedback tests passed`.

Also run the whole suite once to be sure the new files did not break the loop: `mise run script-test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Scripts/testflight-feedback.sh ios/Scripts/test-testflight-feedback.sh
git commit -m "feat(ios): import TestFlight screenshot feedback as GitHub issues (#113)"
```

---

### Task 2: Skip already-tracked submissions, and a dry run

**Files:**
- Modify: `ios/Scripts/test-testflight-feedback.sh` (append cases before the final `echo`)
- Modify: `ios/Scripts/testflight-feedback.sh` (no code change expected; this task proves the seen set and dry run written in Task 1 actually behave)

**Interfaces:**
- Consumes: `reset`, `run_script`, `created_count`, `$STUB_DIR/bodies.txt` (what the `gh issue list` stub returns).

- [ ] **Step 1: Write the failing tests**

Append to `ios/Scripts/test-testflight-feedback.sh`, above `echo "all testflight-feedback tests passed"`:

```bash
# A second run sees both markers in existing issue bodies and creates nothing.
reset
cat > "$STUB_DIR/bodies.txt" <<'EOF'
Some earlier body
<!-- testflight-feedback:S-OLD -->
Another
<!-- testflight-feedback:S-NEW -->
EOF
out="$(run_script)" || fail "second run exited non-zero: $out"
[ "$(created_count)" -eq 0 ] || fail "second run created $(created_count) issues; output: $out"
grep -q "^0 created, 2 already tracked\.$" <<<"$out" || fail "summary wrong; got: $out"
! grep -q "^issue create" "$STUB_DIR/gh.log" || fail "issue create was called on a re-run"
pass "already-tracked submissions are skipped"

# Only one tracked: the other is still created.
reset
printf '<!-- testflight-feedback:S-OLD -->\n' > "$STUB_DIR/bodies.txt"
out="$(run_script)" || fail "partial run exited non-zero: $out"
[ "$(created_count)" -eq 1 ] || fail "expected exactly 1 new issue; output: $out"
grep -q "testflight-feedback:S-NEW" "$STUB_DIR/created-1.md" || fail "the untracked submission was not the one created"
pass "the seen set is per submission, not all-or-nothing"

# Dry run: reports, touches nothing.
reset
out="$(run_script --dry-run)" || fail "dry run exited non-zero: $out"
[ "$(created_count)" -eq 0 ] || fail "dry run created issues"
grep -q "^would create: Done button hides behind the strip$" <<<"$out" || fail "dry run did not list the titles; got: $out"
grep -q "^2 would be created, 0 already tracked\.$" <<<"$out" || fail "dry run summary wrong; got: $out"
! grep -qE "^(issue create|label create|release)" "$STUB_DIR/gh.log" || fail "dry run wrote to GitHub: $(cat "$STUB_DIR/gh.log")"
pass "--dry-run lists titles and writes nothing"

# Bad usage.
out="$(run_script --bogus)" && fail "unknown flag should exit non-zero"
grep -q "^usage:" <<<"$out" || fail "usage message missing; got: $out"
pass "an unknown flag prints usage and exits 2"
```

- [ ] **Step 2: Run it to verify the new cases pass or fail**

Run from `ios/`: `Scripts/test-testflight-feedback.sh`
Expected: all cases pass. Task 1's script already implements the seen set and dry run; this task exists so a reviewer can reject the idempotency behaviour independently. If any case fails, fix the script, not the test, and note what was wrong in the commit message.

- [ ] **Step 3: Commit**

```bash
git add ios/Scripts/test-testflight-feedback.sh ios/Scripts/testflight-feedback.sh
git commit -m "test(ios): testflight-feedback skips tracked submissions and honours --dry-run"
```

---

### Task 3: Screenshots as release assets, embedded in the issue

**Files:**
- Modify: `ios/Scripts/testflight-feedback.sh` (add `ensure_release`, `upload_screenshots`; call them in the loop)
- Modify: `ios/Scripts/test-testflight-feedback.sh` (append cases)

**Interfaces:**
- Consumes: `RELEASE_TAG`, `REPO`, `DRY_RUN`, `TMP`, `field`, the `render` contract (`IMAGE_URLS` newline-separated).
- Produces: `upload_screenshots <id> <urls>` prints one asset URL per line: `https://github.com/<repo>/releases/download/testflight-feedback/<id>-<N>.png`.

- [ ] **Step 1: Write the failing tests**

Append above the final `echo`:

```bash
# Screenshots: downloaded, uploaded to the pre-release, embedded by stable asset URL.
reset
out="$(run_script)" || fail "screenshot run exited non-zero: $out"
grep -q "^release view testflight-feedback" "$STUB_DIR/gh.log" || fail "release existence not checked"
grep -q "^release create testflight-feedback" "$STUB_DIR/gh.log" || fail "release not created when missing"
[ "$(grep -c "^release upload testflight-feedback" "$STUB_DIR/gh.log")" -eq 3 ] || fail "expected 3 uploads (2 + 1); log: $(cat "$STUB_DIR/gh.log")"
grep -q "https://shots.example/one.png" "$STUB_DIR/curl.log" || fail "screenshot was not downloaded"
grep -q '^!\[screenshot 1\](https://github.com/tylervick/graphghan/releases/download/testflight-feedback/S-NEW-1.png)$' "$STUB_DIR/created-2.md" || fail "image line missing or wrong; body: $(cat "$STUB_DIR/created-2.md")"
grep -q '^!\[screenshot 2\](https://github.com/tylervick/graphghan/releases/download/testflight-feedback/S-OLD-2.png)$' "$STUB_DIR/created-1.md" || fail "second image line missing on the two-screenshot submission"
! grep -q "shots.example" "$STUB_DIR"/created-*.md || fail "an expiring Apple URL reached an issue body"
pass "screenshots are uploaded once each and embedded by asset URL"

# The release is created at most once per run.
reset
touch "$STUB_DIR/release-exists"
out="$(run_script)" || fail "run with existing release exited non-zero: $out"
! grep -q "^release create" "$STUB_DIR/gh.log" || fail "release re-created although it exists"
pass "an existing release is reused"

# Dry run downloads nothing and uploads nothing.
reset
out="$(run_script --dry-run)" || fail "dry run exited non-zero: $out"
! grep -q "shots.example" "$STUB_DIR/curl.log" || fail "dry run downloaded a screenshot"
! grep -q "^release" "$STUB_DIR/gh.log" || fail "dry run touched the release"
pass "--dry-run leaves screenshots alone"
```

- [ ] **Step 2: Run it to verify it fails**

Run from `ios/`: `Scripts/test-testflight-feedback.sh`
Expected: `FAIL: release existence not checked`.

- [ ] **Step 3: Implement**

In `ios/Scripts/testflight-feedback.sh`, add these two functions directly after `render() { ... }`:

```bash
ensure_release() {
    [ -z "${RELEASE_READY:-}" ] || return 0
    if ! gh release view "$RELEASE_TAG" --repo "$REPO" >/dev/null 2>&1; then
        gh release create "$RELEASE_TAG" --repo "$REPO" --prerelease --title "TestFlight feedback screenshots" \
            --notes "Screenshots attached to issues labelled testflight-feedback. Not a release of anything." >/dev/null \
            || { echo "error: could not create the $RELEASE_TAG release" >&2; return 1; }
    fi
    RELEASE_READY=1
}

# Downloads each screenshot URL, uploads it as <id>-<N>.png, prints the asset URLs one per line.
upload_screenshots() { # id, urls (newline-separated)
    local id="$1" n=0 url file
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        n=$((n + 1)); file="$TMP/$id-$n.png"
        curl -sS -f -L -o "$file" "$url" || { echo "error: could not download screenshot $n of $id" >&2; return 1; }
        gh release upload "$RELEASE_TAG" "$file" --repo "$REPO" --clobber >/dev/null \
            || { echo "error: could not upload screenshot $n of $id" >&2; return 1; }
        echo "https://github.com/$REPO/releases/download/$RELEASE_TAG/$id-$n.png"
    done <<< "$2"
}
```

Then replace the two lines `IMAGE_URLS=""` and `CRASH_LOG_FILE=""` inside the loop with:

```bash
    IMAGE_URLS=""
    SHOTS="$(printf '%s' "$REC" | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["screenshots"]))')"
    if [ -n "$SHOTS" ] && [ "$DRY_RUN" -eq 0 ]; then
        ensure_release || exit 1
        IMAGE_URLS="$(upload_screenshots "$ID" "$SHOTS")" || exit 1
    fi
    CRASH_LOG_FILE=""
```

- [ ] **Step 4: Run the test to verify it passes**

Run from `ios/`: `Scripts/test-testflight-feedback.sh`
Expected: every case passes, ending in `all testflight-feedback tests passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/Scripts/testflight-feedback.sh ios/Scripts/test-testflight-feedback.sh
git commit -m "feat(ios): attach TestFlight screenshots to feedback issues as release assets"
```

---

### Task 4: Crash submissions with the crash log

**Files:**
- Modify: `ios/Scripts/testflight-feedback.sh` (list crashes, fetch the log, merge into one ordered list)
- Modify: `ios/Scripts/test-testflight-feedback.sh` (crash fixtures and cases)

**Interfaces:**
- Consumes: `normalize <file> <kind>` (kind `crash` yields `screenshots: []`), `render` (`CRASH_LOG_FILE` path → collapsed log block), `api_get`.

- [ ] **Step 1: Write the failing tests**

Replace the empty `crashes.json` fixture in the test with:

```bash
# One crash submission, newer than both screenshots, with a comment. The log contains a
# three-backtick run to prove the fence survives it.
cat > "$STUB_DIR/crashes.json" <<'EOF'
{"data":[
 {"type":"betaFeedbackCrashSubmissions","id":"C-1",
  "attributes":{"createdDate":"2026-09-19T15:00:00Z","comment":"Tapped Back twice fast","email":"tester@example.com","deviceModel":"iPhone17,1","osVersion":"26.0","locale":"en-US"},
  "relationships":{"build":{"data":{"type":"builds","id":"B12"}}}}
],"included":[{"type":"builds","id":"B12","attributes":{"version":"12"}}]}
EOF
cat > "$STUB_DIR/crashlog.json" <<'EOF'
{"data":{"type":"betaCrashLogs","id":"C-1","attributes":{"logText":"Incident Identifier: ABC\nThread 0 Crashed:\n0  Graphghan  0x1 WorkView.perform ```not a fence```"}}}
EOF
```

Existing assertions that count issues change: in the Task 1 case, `-eq 2` becomes `-eq 3` and the summary becomes `3 created, 0 already tracked.`; in the Task 2 cases the "second run" summary becomes `0 created, 3 already tracked.` after adding `<!-- testflight-feedback:C-1 -->` to that `bodies.txt`, the "partial" case expects 2 new issues, and the dry-run summary becomes `3 would be created, 0 already tracked.`. Update those lines now. The crash is newest, so it is `created-3` in a fresh run; the screenshot assertions on `created-1` and `created-2` are unchanged.

Then append above the final `echo`:

```bash
# Crash submissions: fetched alongside screenshots, log embedded, ordered by date with the rest.
reset
out="$(run_script)" || fail "crash run exited non-zero: $out"
[ "$(created_count)" -eq 3 ] || fail "expected 3 issues with the crash; output: $out"
[ "$(cat "$STUB_DIR/created-3.title")" = "Crash on build 12 (iPhone17,1, 26.0): Tapped Back twice fast" ] || fail "crash title wrong; got: $(cat "$STUB_DIR/created-3.title")"
body="$(cat "$STUB_DIR/created-3.md")"
grep -q "^### Crash$" <<<"$body" || fail "Crash heading missing"
grep -q "<details><summary>Crash log</summary>" <<<"$body" || fail "crash log details block missing"
grep -q "Thread 0 Crashed:" <<<"$body" || fail "log text missing"
grep -q '^````$' <<<"$body" || fail "four-backtick fence missing"
grep -q "<!-- testflight-feedback:C-1 -->" <<<"$body" || fail "crash marker missing"
grep -q "betaFeedbackCrashSubmissions/C-1/crashLog" "$STUB_DIR/curl.log" || fail "crash log not fetched"
grep -q "betaFeedbackCrashSubmissions?sort=-createdDate&limit=50&include=build&fields%5Bbuilds%5D=version" "$STUB_DIR/curl.log" || fail "crash listing query wrong"
! grep -q "tester@example.com" <<<"$body" || fail "email reached the crash issue"
pass "crash submissions become issues with the log collapsed"
```

- [ ] **Step 2: Run it to verify it fails**

Run from `ios/`: `Scripts/test-testflight-feedback.sh`
Expected: the first case fails with `expected 3 issues, created 2` (crashes are not listed yet).

- [ ] **Step 3: Implement**

In `ios/Scripts/testflight-feedback.sh`, replace the single `normalize ... > "$TMP/submissions.jsonl"` line and the screenshot `api_get` above it with:

```bash
api_get "/v1/apps/$APP_ID/betaFeedbackScreenshotSubmissions?$QUERY" > "$TMP/screenshots.json" || { echo "error: could not list screenshot submissions" >&2; exit 1; }
api_get "/v1/apps/$APP_ID/betaFeedbackCrashSubmissions?$QUERY" > "$TMP/crashes.json" || { echo "error: could not list crash submissions" >&2; exit 1; }
# Both kinds in one list, oldest first across kinds, so issue numbers follow arrival order.
{ normalize "$TMP/screenshots.json" screenshot; normalize "$TMP/crashes.json" crash; } \
    | python3 -c 'import json, sys; rows = [json.loads(l) for l in sys.stdin if l.strip()]; rows.sort(key=lambda r: r["created"]); print("\n".join(json.dumps(r) for r in rows))' \
    > "$TMP/submissions.jsonl"
```

Then replace the line `CRASH_LOG_FILE=""` inside the loop with:

```bash
    CRASH_LOG_FILE=""
    if [ "$(field kind)" = "crash" ]; then
        CRASH_LOG_FILE="$TMP/$ID.crash"
        if ! api_get "/v1/betaFeedbackCrashSubmissions/$ID/crashLog" \
                | python3 -c 'import json, sys; print((json.load(sys.stdin).get("data") or {}).get("attributes", {}).get("logText") or "")' \
                > "$CRASH_LOG_FILE"; then
            echo "warning: no crash log for $ID; the issue will say so" >&2
            printf 'The crash log could not be fetched; see App Store Connect.\n' > "$CRASH_LOG_FILE"
        fi
    fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run from `ios/`: `Scripts/test-testflight-feedback.sh`, then `mise run script-test`.
Expected: all cases pass in both.

- [ ] **Step 5: Commit**

```bash
git add ios/Scripts/testflight-feedback.sh ios/Scripts/test-testflight-feedback.sh
git commit -m "feat(ios): import TestFlight crash submissions with the crash log"
```

---

### Task 5: The scheduled workflow, docs, and the PR

**Files:**
- Create: `.github/workflows/testflight-feedback.yml`
- Modify: `ios/docs/release.md` (new section after "When something fails")
- Modify: `CLAUDE.md` (one line under Backlog)

**Interfaces:**
- Consumes: `ios/Scripts/testflight-feedback.sh [--dry-run]`; repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (base64 of the `.p8`), already present for `testflight.yml`.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/testflight-feedback.yml`:

```yaml
name: TestFlight feedback

# Every 30 minutes, TestFlight screenshot and crash submissions become GitHub issues (one each,
# never twice) via ios/Scripts/testflight-feedback.sh. Manual dispatch exists for a dry run and
# for "I know feedback just arrived".
on:
  schedule:
    - cron: '*/30 * * * *'
  workflow_dispatch:
    inputs:
      dry_run:
        description: List what would be created without opening issues or uploading screenshots
        type: boolean
        required: false
        default: false

# Two overlapping runs would both compute an empty seen set and open duplicates.
concurrency:
  group: testflight-feedback
  cancel-in-progress: false

permissions: {}

jobs:
  import:
    name: Import feedback as issues
    runs-on: ubuntu-latest
    timeout-minutes: 10
    # issues: write for gh issue create and gh label create; contents: write for gh release
    # create/upload, which is where the screenshots live.
    permissions:
      issues: write
      contents: write
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
        with: {persist-credentials: false}

      # No set -x: a decoded .p8 is multi-line PEM and GitHub's masking needs a single-line match.
      - name: Install the App Store Connect key
        env:
          ASC_PRIVATE_KEY: ${{ secrets.ASC_PRIVATE_KEY }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
        run: |
          umask 077
          printf '%s' "$ASC_PRIVATE_KEY" | /usr/bin/base64 --decode > "$RUNNER_TEMP/AuthKey_${ASC_KEY_ID}.p8"

      - name: Import feedback
        env:
          ASC_KEY_PATH: ${{ runner.temp }}/AuthKey_${{ secrets.ASC_KEY_ID }}.p8
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          GH_TOKEN: ${{ github.token }}
          DRY_RUN: ${{ inputs.dry_run }}
        run: |
          if [ "$DRY_RUN" = "true" ]; then ios/Scripts/testflight-feedback.sh --dry-run
          else ios/Scripts/testflight-feedback.sh; fi
```

- [ ] **Step 2: Lint the workflow**

Run from the repo root: `mise run lint`
Expected: `✔ zizmor`, `✔ actionlint`, and the rest green. If zizmor flags anything, fix the workflow; do not add a suppression.

- [ ] **Step 3: Write the docs**

In `ios/docs/release.md`, insert this section between "## When something fails" and "## Local archive":

```markdown
## TestFlight feedback

`.github/workflows/testflight-feedback.yml` runs `ios/Scripts/testflight-feedback.sh` every 30
minutes. Each TestFlight screenshot submission or crash submission becomes one issue labelled
`bug`, `ios`, and `testflight-feedback`, with the comment, build number, device, OS, locale, the
screenshots, or the crash log collapsed. Screenshots are assets on the `testflight-feedback`
pre-release (stable URLs; Apple's expire). The tester's email is never read; the repo is public.

An issue is never opened twice: the script lists issues by the `testflight-feedback` label and
reads the `<!-- testflight-feedback:<id> -->` marker each body ends with. Deleting an issue makes
the next run recreate it; close it instead.

Tell the tester: **take a screenshot inside the app and choose "Share Beta Feedback"**; after a
crash, TestFlight asks on its own.

To see what a run would do without opening anything, Actions › TestFlight feedback › Run workflow
with `dry_run` ticked, or locally with the keychain credentials:

```bash
ios/Scripts/with-asc-credentials.sh ios/Scripts/testflight-feedback.sh --dry-run
```

The first real run imports every submission App Store Connect still holds (up to 50 of each kind),
so run a dry run first if the app has been on TestFlight for a while.
```

In `CLAUDE.md`, add this bullet at the end of the Backlog list:

```markdown
- Issues labelled `testflight-feedback` were opened by the TestFlight import workflow from tester
  submissions. Relabel or retitle freely; do not delete them (the next run would recreate them).
```

- [ ] **Step 4: Verify everything once more**

Run from `ios/`: `mise run script-test`. Run from the repo root: `mise run check`.
Expected: both green.

- [ ] **Step 5: Commit and open the PR**

```bash
git add .github/workflows/testflight-feedback.yml ios/docs/release.md CLAUDE.md
git commit -m "ci: import TestFlight feedback into GitHub Issues every 30 minutes (#113)"
git push -u origin feat/testflight-feedback
gh pr create --title "Bridge TestFlight feedback into GitHub Issues" --body "$(cat <<'EOF'
## What

- `ios/Scripts/testflight-feedback.sh`: lists TestFlight screenshot and crash submissions through the App Store Connect API, skips ones already tracked (label + hidden marker, not search), uploads screenshots as assets on a permanent `testflight-feedback` pre-release, and opens one issue per submission labelled `bug`, `ios`, `testflight-feedback`. `--dry-run` reports and writes nothing. The tester's email is never read.
- `ios/Scripts/test-testflight-feedback.sh`: hermetic tests with `curl` and `gh` stubs, in `mise run script-test`.
- `.github/workflows/testflight-feedback.yml`: cron every 30 minutes plus manual dispatch with a dry-run input.
- Docs in `ios/docs/release.md`; a note in `CLAUDE.md`.

## Before merging

Run the workflow by hand with `dry_run` ticked and read the log: it lists every submission the first real run would import.

Closes #113
EOF
)"
```

Then, after the PR's CI is green, dispatch the workflow on the branch with `dry_run` ticked (`gh workflow run testflight-feedback.yml --ref feat/testflight-feedback -f dry_run=true`), read the run log, and paste the "would create" lines into a PR comment. That is the only integration check available without opening real issues.

---

## Self-review

**Spec coverage.** Listing both kinds (Tasks 1, 4), build number joined from `included` (Task 1), no email (Task 1 test, Task 4 test), label-based seen set (Tasks 1, 2), oldest first (Tasks 1, 4), screenshots as release assets with stable URLs (Task 3), crash log collapsed with a safe fence and 50 000-char cap (Task 4), dry run (Tasks 2, 3), scheduled workflow with least permissions and pinned action (Task 5), docs and tester instruction (Task 5), `Closes #113` (Task 5). The App Store Connect link in the body is `/apps/<id>/testflight/ios`; if that path 404s on a real app id, change it to `/apps/<id>/testflight` in `render` and the Task 1 assertion (`appstoreconnect.apple.com/apps/APP1/testflight`) still passes.

**Placeholders.** None: every step has its code.

**Consistency.** `render` reads `IMAGE_URLS` and `CRASH_LOG_FILE` from the environment in every task; `upload_screenshots` prints exactly the URL form the Task 3 test asserts; `normalize` sorts within a kind and the Task 4 merge sorts across kinds by the same `created` key; the gh stub's `issue list` output is read by the same `grep -o` in every task; the summary line wording (`N created, M already tracked.` / `N would be created, M already tracked.`) is identical in the script and every assertion.
