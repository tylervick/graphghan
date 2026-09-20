#!/bin/bash
# Imports TestFlight tester feedback (screenshot submissions and crash submissions) from App Store
# Connect into GitHub Issues: one issue per submission, never the same submission twice.
#
# Reads from the environment (see asc-jwt.sh): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH. Needs
# `gh` authenticated for the repository (GH_TOKEN in Actions, the keyring locally), `curl`, and
# `python3`. GITHUB_REPOSITORY (set by Actions) names the repo; locally it is read from the checkout.
#
# ASC_JWT: path to the script that mints the App Store Connect token; default asc-jwt.sh next to
# this script. This is what the test stubs to stay hermetic. TESTFLIGHT_FEEDBACK_LIMIT: submissions
# listed per kind (screenshot, crash); default 50.
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

# A tester who types the marker's spelling into a comment must not be able to mark another
# submission as tracked: a zero-width space after the prefix renders identically on GitHub
# but never matches the reader's pattern.
comment = comment.replace("testflight-feedback:", "testflight-feedback​:")

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

TOKEN="$("$ASC_JWT")" || { echo "error: could not mint an App Store Connect token" >&2; exit 1; }
if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::add-mask::$TOKEN"; fi

APPS_RESP="$(api_get "/v1/apps?filter%5BbundleId%5D=$BUNDLE_ID")" || { echo "error: could not resolve the app id for $BUNDLE_ID" >&2; exit 1; }
APP_ID="$(printf '%s' "$APPS_RESP" | python3 -c 'import json, sys; d = json.load(sys.stdin).get("data") or []; print(d[0]["id"] if d else "")')"
[ -n "$APP_ID" ] || { echo "error: App Store Connect has no app with bundle id $BUNDLE_ID" >&2; exit 1; }

QUERY="sort=-createdDate&limit=$LIMIT&include=build&fields%5Bbuilds%5D=version"
api_get "/v1/apps/$APP_ID/betaFeedbackScreenshotSubmissions?$QUERY" > "$TMP/screenshots.json" || { echo "error: could not list screenshot submissions" >&2; exit 1; }
api_get "/v1/apps/$APP_ID/betaFeedbackCrashSubmissions?$QUERY" > "$TMP/crashes.json" || { echo "error: could not list crash submissions" >&2; exit 1; }
# Both kinds in one list, oldest first across kinds, so issue numbers follow arrival order.
{ normalize "$TMP/screenshots.json" screenshot; normalize "$TMP/crashes.json" crash; } \
    | python3 -c 'import json, sys; rows = [json.loads(l) for l in sys.stdin if l.strip()]; rows.sort(key=lambda r: r["created"]); print("\n".join(json.dumps(r) for r in rows))' \
    > "$TMP/submissions.jsonl"

if [ "$DRY_RUN" -eq 0 ]; then
    gh label create "$FEEDBACK_LABEL" --repo "$REPO" --color 0e8a16 \
        --description "Imported from TestFlight by ios/Scripts/testflight-feedback.sh" --force >/dev/null \
        || { echo "error: could not ensure the $FEEDBACK_LABEL label" >&2; exit 1; }
fi

# The seen set. A failure here must stop the run: without it every submission looks new.
gh issue list --repo "$REPO" --label "$FEEDBACK_LABEL" --state all --limit 1000 --json body -q '.[].body' > "$TMP/bodies" \
    || { echo "error: could not list existing feedback issues; refusing to run without the seen set" >&2; exit 1; }
# Match the full `<!-- testflight-feedback:<id> -->` comment form on purpose, not a bare token: a
# tester's comment is stored verbatim in the body, and a bare-token match would let text a tester
# typed mark an unrelated submission as tracked.
{ grep -o '<!-- testflight-feedback:[^ >]* -->' "$TMP/bodies" || true; } \
    | sed 's/^<!-- testflight-feedback://; s/ -->$//' | sort -u > "$TMP/seen"

created=0; skipped=0
while IFS= read -r REC; do
    [ -n "$REC" ] || continue
    ID="$(field id)"
    if grep -qxF "$ID" "$TMP/seen"; then skipped=$((skipped + 1)); continue; fi

    IMAGE_URLS=""
    SHOTS="$(printf '%s' "$REC" | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["screenshots"]))')"
    if [ -n "$SHOTS" ] && [ "$DRY_RUN" -eq 0 ]; then
        ensure_release || exit 1
        IMAGE_URLS="$(upload_screenshots "$ID" "$SHOTS")" || exit 1
    fi
    # --dry-run still fetches the crash log on purpose: it is a read-only App Store Connect call,
    # and skipping it would make the dry run's report unrepresentative of a real run.
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
