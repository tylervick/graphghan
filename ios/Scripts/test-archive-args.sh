#!/bin/bash
# archive.sh must assemble the right command lines AND survive with no CI env set: macOS /bin/bash
# is 3.2, where `set -u` on an empty array aborts unless expanded as "${ARR[@]+"${ARR[@]}"}".
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
BASH32=/bin/bash
"$BASH32" --version | head -1 | grep -q 'version 3\.2' || echo "warn: $BASH32 is not 3.2; the empty-array case may not be exercised"

run_archive() { env -u ASC_KEY_PATH -u ASC_KEY_ID -u ASC_ISSUER_ID -u BUILD_NUMBER -u EXPORT_OPTIONS_PLIST \
                    ARCHIVE_PRINT_ONLY=1 "$@" "$BASH32" "$HERE/archive.sh"; }

OUT="$(run_archive 2>&1)" || fail "archive.sh aborted with no env set: $OUT"
case "$OUT" in
  *-authenticationKey*) fail "auth flags present with no ASC env set" ;;
  *CURRENT_PROJECT_VERSION*) fail "version override present with no BUILD_NUMBER" ;;
esac
grep -q "ExportOptions.plist" <<<"$OUT" || fail "default export plist not used"
grep -q -- "-scheme Graphghan" <<<"$OUT" || fail "wrong scheme"
! grep -q -- "^ARCHIVE:.*-allowProvisioningUpdates" <<<"$OUT" || fail "archive step must never pass -allowProvisioningUpdates"
pass "no env -> no auth flags, no version override, default plist, no provisioning updates on archive"

OUT3="$(ARCHIVE_PRINT_ONLY=1 ASC_KEY_PATH=/tmp/k.p8 ASC_KEY_ID=KEYID ASC_ISSUER_ID=ISSUER BUILD_NUMBER=42 \
        EXPORT_OPTIONS_PLIST=ExportOptions-ci.plist "$BASH32" "$HERE/archive.sh" 2>&1)" || fail "archive.sh failed with CI env set"
[ "$(grep -c -- '-authenticationKeyPath /tmp/k.p8' <<<"$OUT3")" -eq 2 ] || fail "auth flags must be on both xcodebuild lines"
grep -q -- 'CURRENT_PROJECT_VERSION=42' <<<"$OUT3" || fail "build number override missing"
grep -q -- 'ExportOptions-ci.plist' <<<"$OUT3" || fail "CI plist not used"
pass "CI env -> auth flags on both lines, build number override, CI plist"

OUT4="$(ARCHIVE_PRINT_ONLY=1 ASC_KEY_ID=KEYID "$BASH32" "$HERE/archive.sh" 2>&1)" || fail "partial ASC env failed"
case "$OUT4" in *-authenticationKey*) fail "auth flags added from partial env" ;; esac
pass "partial ASC env -> no auth flags"

if ASC_KEY_PATH=/tmp/k.p8 ASC_KEY_ID=K ASC_ISSUER_ID=I "$BASH32" "$HERE/archive.sh" >/dev/null 2>"${TMPDIR:-/tmp}/err" ; then
  fail "ASC auth without an explicit manual plist must be refused"
fi
grep -q "manual-signing export plist" "${TMPDIR:-/tmp}/err" || fail "refusal did not explain itself: $(cat "${TMPDIR:-/tmp}/err")"
pass "ASC auth without EXPORT_OPTIONS_PLIST is refused before any work"
