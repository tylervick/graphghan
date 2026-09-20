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
