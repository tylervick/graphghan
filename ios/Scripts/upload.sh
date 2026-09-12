#!/bin/bash
# Uploads (or with --validate, validates) the exported IPA to App Store Connect with an API key.
#   Scripts/upload.sh [--validate] [path-to-ipa]
# Needs ASC_KEY_ID and ASC_ISSUER_ID in the environment or in Scripts/.appstore.env (gitignored), and
# the .p8 either at ASC_KEY_PATH or where altool searches (~/.appstoreconnect/private_keys/AuthKey_<ID>.p8).
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"

ACTION="--upload-app"
if [ "${1:-}" = "--validate" ]; then ACTION="--validate-app"; shift; fi
IPA="${1:-$IOS/build/archive/export/Graphghan.ipa}"

# shellcheck disable=SC1091
[ -f "$IOS/Scripts/.appstore.env" ] && source "$IOS/Scripts/.appstore.env"
: "${ASC_KEY_ID:?set ASC_KEY_ID (env or Scripts/.appstore.env)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (env or Scripts/.appstore.env)}"
[ -f "$IPA" ] || { echo "IPA not found: $IPA (run Scripts/archive.sh first)" >&2; exit 1; }

KEY_ARGS=()
if [ -n "${ASC_KEY_PATH:-}" ]; then KEY_ARGS=(--p8-file-path "$ASC_KEY_PATH"); fi

echo "${ACTION#--} $IPA"
# Captured, not streamed: Xcode 26's altool has printed an ITMS error and still exited 0. Trusting the
# exit code alone would make a failed release look green.
set +e
OUT="$(xcrun altool "$ACTION" -f "$IPA" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
        "${KEY_ARGS[@]+"${KEY_ARGS[@]}"}" 2>&1)"
RC=$?
set -e
printf '%s\n' "$OUT"
if [ "$RC" -ne 0 ]; then echo "error: altool exited $RC" >&2; exit "$RC"; fi
if grep -qE 'ERROR ITMS-|error:' <<<"$OUT"; then
    echo "error: altool reported an error but exited 0 (known Xcode 26 behaviour); treating as FAILED." >&2
    echo "error: the build MAY still have been uploaded; check App Store Connect before re-running (a re-run consumes another build number)" >&2
    exit 1
fi
