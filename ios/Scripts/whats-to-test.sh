#!/bin/bash
# Assembles TestFlight "What to Test" notes and attaches them to a build in App Store Connect.
#   Scripts/whats-to-test.sh --print          assemble and print (no network)
#   Scripts/whats-to-test.sh <build-number>   assemble and attach via the App Store Connect API
#
# Notes = optional hand-written preamble (ios/docs/whats-to-test.md) + a changelog DERIVED from git:
# commits since the newest ios-build-* tag below the current build, restricted to paths a tester can
# notice (ios/ and patterns/), grouped "In the app" (feat/fix/perf) and "Behind the scenes" (the rest),
# with the conventional-commit prefix and any trailing "(#N)" removed. Trimmed to App Store Connect's
# whatsNew cap on a bullet boundary.
#
# WHATS_TO_TEST_RANGE_ONLY=1 with a build number prints the notes for that build and exits (test hook).
# WHATS_TO_TEST_POLL_ATTEMPTS / WHATS_TO_TEST_POLL_DELAY override the ingestion poll; ASC_JWT the JWT script.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$IOS/.." && pwd)"
cd "$ROOT"

PREAMBLE_FILE="ios/docs/whats-to-test.md"
API="https://api.appstoreconnect.apple.com"
BUNDLE_ID="com.tylervick.graphghan"
TAG_PREFIX="ios-build-"
POLL_ATTEMPTS="${WHATS_TO_TEST_POLL_ATTEMPTS:-30}"
POLL_DELAY="${WHATS_TO_TEST_POLL_DELAY:-30}"
ASC_JWT="${ASC_JWT:-$IOS/Scripts/asc-jwt.sh}"
NOTES_MAX=3900

# One bullet per commit in the range that touches ios/ or patterns/. Output lines: "<group>\t<text>".
changelog() { # git log range args...
    git log --format='%H%x09%s' "$@" -- ios patterns | while IFS=$'\t' read -r _sha subject; do
        [ -n "$subject" ] || continue
        prefix=""; text="$subject"
        case "$subject" in
            *:*) prefix="${subject%%:*}"; text="${subject#*: }" ;;
        esac
        # strip a trailing " (#123)"
        text="$(printf '%s' "$text" | sed -E 's/ \(#[0-9]+\)$//')"
        # capitalise the first character
        text="$(printf '%s' "$text" | python3 -c 'import sys; s=sys.stdin.read(); print(s[:1].upper()+s[1:], end="")')"
        kind="${prefix%%(*}"; kind="${kind%%!}"
        case "$kind" in
            feat|fix|perf) printf 'app\t%s\n' "$text" ;;
            *) printf 'other\t%s\n' "$text" ;;
        esac
    done
}

format_groups() { # reads changelog lines on stdin
    python3 -c '
import sys
app, other = [], []
for line in sys.stdin.read().splitlines():
    if "\t" not in line: continue
    kind, text = line.split("\t", 1)
    (app if kind == "app" else other).append("- " + text)
out = []
if app: out += ["In the app"] + app
if other:
    if out: out.append("")
    out += ["Behind the scenes"] + other
print("\n".join(out), end="")'
}

prev_tag() { # [current-build-number]
    printf '%s\n' "$TAG_LIST" | awk -v n="${1:-}" -v p="$TAG_PREFIX" '
        { num = $0; sub("^" p, "", num) }
        ($0 != "") && (n == "" || num + 0 < n + 0) { print; exit }'
}

assemble_notes() { # [current-build-number]
    PREAMBLE=""
    if [ -f "$PREAMBLE_FILE" ]; then
        # drop HTML comments, trailing whitespace, and leading blank lines
        PREAMBLE="$(sed -e 's/<!--.*-->//' -e 's/[[:space:]]*$//' "$PREAMBLE_FILE" | sed -e '/./,$!d')"
    fi
    TAG_ERR="$(mktemp "${TMPDIR:-/tmp}/wtt-tag.XXXXXX")"
    if ! TAG_LIST="$(git tag --list "${TAG_PREFIX}*" --sort=-v:refname 2>"$TAG_ERR")"; then
        echo "error: git tag --list failed; cannot determine the previous build tag." >&2
        cat "$TAG_ERR" >&2; rm -f "$TAG_ERR"; exit 1
    fi
    rm -f "$TAG_ERR"
    TAG="$(prev_tag "${1:-}")"
    if [ -n "$TAG" ]; then
        HEADING="Changes since build ${TAG#"$TAG_PREFIX"}:"
        if [ -n "${1:-}" ] && git rev-parse -q --verify "refs/tags/${TAG_PREFIX}$1" >/dev/null; then
            BODY="$(changelog "$TAG..${TAG_PREFIX}$1" | format_groups)"
        else
            BODY="$(changelog "$TAG..HEAD" | format_groups)"
        fi
    else
        HEADING="Recent changes (no previous build tag; showing the last 20 commits):"
        BODY="$(changelog --max-count=20 | format_groups)"
    fi
    if [ -z "$PREAMBLE" ] && [ -z "$BODY" ]; then
        echo "error: no changes since ${TAG:-the start of history} and $PREAMBLE_FILE is empty." >&2
        echo "       Nothing to tell a tester. Write a preamble or ship a build with changes in it." >&2
        exit 1
    fi
    OUT=""
    if [ -n "$PREAMBLE" ]; then OUT="$PREAMBLE"; [ -n "$BODY" ] && OUT="$OUT"$'\n\n'; fi
    if [ -n "$BODY" ]; then OUT="$OUT$HEADING"$'\n\n'"$BODY"; fi
    trim_notes "$OUT"
    printf '\n'
}

trim_notes() { # text
    TRIM_TEXT="$1" TRIM_MAX="$NOTES_MAX" python3 -c '
import os, sys
def emit(s): sys.stdout.buffer.write(s.encode("utf-8", "surrogateescape"))
text = os.environ["TRIM_TEXT"]; limit = int(os.environ["TRIM_MAX"])
if len(text) <= limit:
    emit(text); raise SystemExit(0)
def tail(n): return "\n… and %d more change%s" % (n, "" if n == 1 else "s")
lines = text.split("\n"); dropped = 0
while len(lines) > 1 and len("\n".join(lines)) + len(tail(dropped + 1)) > limit:
    if lines.pop().startswith("- "): dropped += 1
if dropped:
    while len(lines) > 1 and not lines[-1].startswith("- "): lines.pop()
out = "\n".join(lines) + (tail(dropped) if dropped else "")
emit(out[:limit])'
}

json_first() { # field-path e.g. "id" or "attributes.processingState"
    python3 -c '
import json, sys
doc = json.load(sys.stdin)
items = doc.get("data") or []
if not items: sys.exit(3)
cur = items[0]
for part in sys.argv[1].split("."):
    cur = (cur or {}).get(part)
print(cur if cur is not None else "")' "$1"
}
api_get() { curl -sS -f -H "Authorization: Bearer $TOKEN" "$API$1"; }
# Prints the field and returns 0; returns 3 on "no items"; 1 on a parse failure.
read_json_field() { # response, field-path
    local val rc
    if val="$(printf '%s' "$1" | json_first "$2" 2>/dev/null)"; then printf '%s' "$val"; return 0; else rc=$?; fi
    [ "$rc" -eq 3 ] && return 3
    return 1
}
api_send() { # method, path, json-body
    local resp
    if resp="$(curl -sS --fail-with-body -X "$1" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
            --data-binary @- "$API$2" <<< "$3")"; then return 0; fi
    printf '%s\n' "$resp" >&2
    return 1
}
loc_body() { # build-id, notes, [loc-id]
    LOC_BUILD_ID="$1" LOC_NOTES="$2" LOC_LOC_ID="${3:-}" python3 -c '
import json, os
data = {"type": "betaBuildLocalizations", "attributes": {"whatsNew": os.environ["LOC_NOTES"]}}
loc_id = os.environ.get("LOC_LOC_ID") or None
if loc_id: data["id"] = loc_id
else:
    data["attributes"]["locale"] = "en-US"
    data["relationships"] = {"build": {"data": {"type": "builds", "id": os.environ["LOC_BUILD_ID"]}}}
print(json.dumps({"data": data}))'
}

MODE="${1:---print}"
if [ "$MODE" = "--print" ]; then assemble_notes; exit 0; fi
BUILD="$MODE"
case "$BUILD" in ''|*[!0-9]*) echo "usage: $0 --print | <build-number>" >&2; exit 2 ;; esac
if [ "${WHATS_TO_TEST_RANGE_ONLY:-}" = "1" ]; then assemble_notes "$BUILD"; exit 0; fi

NOTES="$(assemble_notes "$BUILD")" || { echo "error: could not assemble notes for build $BUILD" >&2; exit 1; }
TOKEN="$("$ASC_JWT")" || { echo "error: could not mint an App Store Connect token" >&2; exit 1; }
if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::$TOKEN"; fi

APPS_RESP="$(api_get "/v1/apps?filter%5BbundleId%5D=$BUNDLE_ID")" || { echo "error: could not resolve the app id for $BUNDLE_ID" >&2; exit 1; }
if APP_ID="$(read_json_field "$APPS_RESP" id)"; then :; else
    rc=$?
    if [ "$rc" -eq 3 ]; then echo "error: App Store Connect has no app with bundle id $BUNDLE_ID (create the app record; see ios/docs/release.md)." >&2
    else echo "error: could not parse the apps response" >&2; fi
    exit 1
fi

# The build resource appears only once ingestion starts and sits in PROCESSING for minutes; poll for both.
STATE=""; BUILD_ID=""; attempt=0
while [ "$attempt" -lt "$POLL_ATTEMPTS" ]; do
    attempt=$((attempt + 1))
    RESP="$(api_get "/v1/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$BUILD")" || { echo "error: could not query builds" >&2; exit 1; }
    if BUILD_ID="$(read_json_field "$RESP" id)"; then :; else rc=$?; [ "$rc" -eq 3 ] || { echo "error: could not parse the builds response" >&2; exit 1; }; fi
    if STATE="$(read_json_field "$RESP" attributes.processingState)"; then :; else rc=$?; [ "$rc" -eq 3 ] || { echo "error: could not parse the builds response" >&2; exit 1; }; fi
    if [ -n "$BUILD_ID" ] && [ "$STATE" != "PROCESSING" ]; then break; fi
    if [ "$attempt" -lt "$POLL_ATTEMPTS" ]; then sleep "$POLL_DELAY"; fi
done
[ -n "$BUILD_ID" ] || { echo "error: build $BUILD never appeared in App Store Connect after $attempt attempts; notes not attached." >&2; exit 1; }
[ "$STATE" != "PROCESSING" ] || { echo "error: build $BUILD still PROCESSING after $POLL_ATTEMPTS attempts; notes not attached." >&2; exit 1; }

LOC_RESP="$(api_get "/v1/betaBuildLocalizations?filter%5Bbuild%5D=$BUILD_ID&filter%5Blocale%5D=en-US")" || { echo "error: could not look up localizations" >&2; exit 1; }
if LOC_ID="$(read_json_field "$LOC_RESP" id)"; then :; else rc=$?; [ "$rc" -eq 3 ] || { echo "error: could not parse the localizations response" >&2; exit 1; }; fi
BODY="$(loc_body "$BUILD_ID" "$NOTES" "$LOC_ID")"
if [ -n "$LOC_ID" ]; then
    api_send PATCH "/v1/betaBuildLocalizations/$LOC_ID" "$BODY" || { echo "error: failed to update the notes for build $BUILD" >&2; exit 1; }
else
    api_send POST "/v1/betaBuildLocalizations" "$BODY" || { echo "error: failed to create the notes for build $BUILD" >&2; exit 1; }
fi
echo "Attached What-to-Test notes to build $BUILD."
