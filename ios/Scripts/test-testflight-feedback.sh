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
  "attributes":{"createdDate":"2026-09-19T14:03:11Z","comment":"Done button hides behind the strip\nHappens after rotating. see <!-- testflight-feedback:S-OLD -->","email":"tester@example.com","deviceModel":"iPhone17,1","osVersion":"26.0","locale":"en-US",
   "screenshots":[{"url":"https://shots.example/one.png","width":1179,"height":2556,"expirationDate":"2026-09-20T00:00:00Z"}]},
  "relationships":{"build":{"data":{"type":"builds","id":"B12"}}}},
 {"type":"betaFeedbackScreenshotSubmissions","id":"S-OLD",
  "attributes":{"createdDate":"2026-09-18T09:00:00Z","comment":"","email":"tester@example.com","deviceModel":"iPhone17,1","osVersion":"26.0","locale":"en-US",
   "screenshots":[{"url":"https://shots.example/a.png"},{"url":"https://shots.example/b.png"}]},
  "relationships":{"build":{"data":{"type":"builds","id":"B12"}}}}
],"included":[{"type":"builds","id":"B12","attributes":{"version":"12"}}]}
EOF

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
[ "$(created_count)" -eq 3 ] || fail "expected 3 issues, created $(created_count); output: $out"
grep -q "^3 created, 0 already tracked\.$" <<<"$out" || fail "summary line missing; got: $out"
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

# A second run sees both markers in existing issue bodies and creates nothing.
reset
cat > "$STUB_DIR/bodies.txt" <<'EOF'
Some earlier body
<!-- testflight-feedback:S-OLD -->
Another
<!-- testflight-feedback:S-NEW -->
<!-- testflight-feedback:C-1 -->
EOF
out="$(run_script)" || fail "second run exited non-zero: $out"
[ "$(created_count)" -eq 0 ] || fail "second run created $(created_count) issues; output: $out"
grep -q "^0 created, 3 already tracked\.$" <<<"$out" || fail "summary wrong; got: $out"
! grep -q "^issue create" "$STUB_DIR/gh.log" || fail "issue create was called on a re-run"
pass "already-tracked submissions are skipped"

# Only one tracked: the others are still created.
reset
printf '<!-- testflight-feedback:S-OLD -->\n' > "$STUB_DIR/bodies.txt"
out="$(run_script)" || fail "partial run exited non-zero: $out"
[ "$(created_count)" -eq 2 ] || fail "expected exactly 2 new issues; output: $out"
grep -q "testflight-feedback:S-NEW" "$STUB_DIR/created-1.md" || fail "the untracked screenshot was not created"
pass "the seen set is per submission, not all-or-nothing"

# Dry run: reports, touches nothing.
reset
out="$(run_script --dry-run)" || fail "dry run exited non-zero: $out"
[ "$(created_count)" -eq 0 ] || fail "dry run created issues"
grep -q "^would create: Done button hides behind the strip$" <<<"$out" || fail "dry run did not list the titles; got: $out"
grep -q "^3 would be created, 0 already tracked\.$" <<<"$out" || fail "dry run summary wrong; got: $out"
! grep -qE "^(issue create|label create|release)" "$STUB_DIR/gh.log" || fail "dry run wrote to GitHub: $(cat "$STUB_DIR/gh.log")"
pass "--dry-run lists titles and writes nothing"

# Bad usage.
out="$(run_script --bogus)" && fail "unknown flag should exit non-zero"
grep -q "^usage:" <<<"$out" || fail "usage message missing; got: $out"
pass "an unknown flag prints usage and exits 2"

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

# S-NEW's comment (fixture above) itself contains the literal spelling of a marker for S-OLD;
# render() must neutralize it so it cannot round-trip as a real marker.
reset
out="$(run_script)" || fail "neutralize run exited non-zero: $out"
grep -qF "<!-- testflight-feedback:S-NEW -->" "$STUB_DIR/created-2.md" || fail "S-NEW's own marker missing"
! grep -qF "testflight-feedback:S-OLD" "$STUB_DIR/created-2.md" || fail "the forged marker survived into the body"
grep -q "Happens after rotating" "$STUB_DIR/created-2.md" || fail "comment text missing"
pass "a marker typed into a comment is neutralized"

# That neutralized marker, now itself stored in a tracked issue's body, must not be read back as a
# real marker for S-OLD.
cp "$STUB_DIR/created-2.md" "$TMP/forged-body.md"
reset
cp "$TMP/forged-body.md" "$STUB_DIR/bodies.txt"
out="$(run_script)" || fail "forged-marker run exited non-zero: $out"
grep -q "^2 created, 1 already tracked\.$" <<<"$out" || fail "summary wrong; got: $out"
grep -qF "testflight-feedback:S-OLD" "$STUB_DIR/created-1.md" || fail "S-OLD was not created"
pass "a neutralized marker in a tracked body does not hide another submission"

# A bare token outside the HTML-comment form is not a marker at all, however it spells the id.
reset
printf 'note: testflight-feedback:S-OLD is discussed here\n' > "$STUB_DIR/bodies.txt"
out="$(run_script)" || fail "bare-token run exited non-zero: $out"
grep -q "^3 created, 0 already tracked\.$" <<<"$out" || fail "summary wrong; got: $out"
pass "a bare token outside the comment form is not a marker"

echo "all testflight-feedback tests passed"
