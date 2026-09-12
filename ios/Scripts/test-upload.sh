#!/bin/bash
# Hermetic tests for upload.sh: a stub `xcrun` on PATH replays altool output. The case that matters is
# Xcode 26's altool reporting a failed validation while exiting 0 -- the first real validate run on CI
# went green on four validation errors because the guard only knew the older "ERROR ITMS-" spelling.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
mkdir -p "$TMP/bin"; : > "$TMP/fake.ipa"
stub() { # output-text, exit-code -> writes $TMP/bin/xcrun that records its args
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" > "%s/args"\ncat <<'"'"'OUT'"'"'\n%s\nOUT\nexit %s\n' "$TMP" "$1" "$2" > "$TMP/bin/xcrun"
    chmod +x "$TMP/bin/xcrun"
}
run() { PATH="$TMP/bin:$PATH" ASC_KEY_ID=KEY ASC_ISSUER_ID=ISS "$@" /bin/bash "$HERE/upload.sh" "${ARGS[@]+"${ARGS[@]}"}" "$TMP/fake.ipa"; }

ARGS=(); stub "No errors uploading '/x/Graphghan.ipa'" 0
run >"$TMP/o" 2>&1 || fail "clean altool output must pass: $(cat "$TMP/o")"
grep -q -- "--upload-app" "$TMP/args" || fail "default action must be --upload-app"
! grep -q -- "--p8-file-path" "$TMP/args" || fail "no ASC_KEY_PATH -> no --p8-file-path"
pass "clean output with exit 0 passes and uploads by default"

ARGS=(--validate); stub "No errors validating archive" 0
run >"$TMP/o" 2>&1 || fail "--validate must pass on clean output"
grep -q -- "--validate-app" "$TMP/args" || fail "--validate must map to --validate-app"
pass "--validate maps to --validate-app"

ARGS=(); stub "ok" 0
run env ASC_KEY_PATH=/tmp/k.p8 >"$TMP/o" 2>&1 || fail "with ASC_KEY_PATH must pass"
grep -q -- "--p8-file-path /tmp/k.p8" "$TMP/args" || fail "ASC_KEY_PATH must add --p8-file-path"
pass "ASC_KEY_PATH adds --p8-file-path"

ARGS=(--validate); stub '2026-09-12 03:19:04.429 ERROR: [ContentDelivery.Uploader.10170EB00] VERIFY FAILED with 4 errors
2026-09-12 03:19:04.432 ERROR: [altool.10170EB00] Validation failed (409) Missing required icon file.' 0
if run >"$TMP/o" 2>&1; then fail "exit 0 with a failed validation must be treated as FAILED"; fi
grep -q "treating as FAILED" "$TMP/o" || fail "missing failure diagnostic: $(cat "$TMP/o")"
grep -q "check App Store Connect before re-running" "$TMP/o" || fail "missing the may-be-uploaded warning"
pass "Xcode 26 altool: exit 0 with 'VERIFY FAILED' / 'Validation failed' is a failure"

ARGS=(); stub "ERROR ITMS-90000: something" 0
if run >"$TMP/o" 2>&1; then fail "ITMS error with exit 0 must fail"; fi
pass "the older 'ERROR ITMS-' spelling is still caught"

ARGS=(); stub "boom" 3
if run >"$TMP/o" 2>&1; then fail "non-zero altool exit must fail"; fi
grep -q "altool exited 3" "$TMP/o" || fail "exit code not reported: $(cat "$TMP/o")"
pass "a non-zero altool exit propagates"
