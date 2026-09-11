#!/bin/bash
# Hermetic tests for check-simulator-available.sh: SIMCTL points at a stub that prints a fixture.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

stub() { # fixture-text -> path of a stub simctl
    printf '#!/bin/bash\ncat <<'"'"'FIX'"'"'\n%s\nFIX\n' "$1" > "$TMP/simctl"
    chmod +x "$TMP/simctl"
    echo "$TMP/simctl"
}
LISTING='== Devices ==
-- iOS 26.2 --
    iPhone 17 (0A1B2C3D-0000-0000-0000-000000000001) (Shutdown)
    iPhone 17 Pro (0A1B2C3D-0000-0000-0000-000000000002) (Shutdown)
    iPad Pro 13-inch (M4) (0A1B2C3D-0000-0000-0000-000000000003) (Shutdown)
-- iOS 18.5 --
    iPhone 16 (0A1B2C3D-0000-0000-0000-000000000004) (Shutdown)'

run() { SIMULATOR_CHECK_DELAY=0 SIMULATOR_CHECK_ATTEMPTS=2 SIMCTL="$1" "$HERE/check-simulator-available.sh" "$2" "$3"; }

out="$(run "$(stub "$LISTING")" "iPhone 17" 26.2)" || fail "exact name should match: $out"
grep -q "matched: iPhone 17 (" <<<"$out" || fail "matched the wrong line: $out"
pass "exact device name in the requested OS section matches"

if run "$(stub "$LISTING")" "iPhone 1" 26.2 >"$TMP/o" 2>&1; then fail "a prefix must not match"; fi
grep -q "requested simulator not found" "$TMP/o" || fail "wrong diagnostic: $(cat "$TMP/o")"
! grep -q GRAPHGHAN_SIMULATOR_UNAVAILABLE "$TMP/o" || fail "marker printed for a pin problem"
pass "a name prefix does not match and the marker is not printed"

out="$(run "$(stub "$LISTING")" "iPad Pro 13-inch (M4)" 26.2)" || fail "parenthesised name should match: $out"
pass "device names containing parentheses match"

if run "$(stub "$LISTING")" "iPhone 17" 18.5 >"$TMP/o" 2>&1; then fail "wrong OS section must not match"; fi
pass "the OS section is respected"

if run "$(stub '== Devices ==')" "iPhone 17" 26.2 >"$TMP/o" 2>&1; then fail "empty enumeration must fail"; fi
grep -q GRAPHGHAN_SIMULATOR_UNAVAILABLE "$TMP/o" || fail "marker missing for an empty enumeration: $(cat "$TMP/o")"
pass "an empty enumeration prints the re-run marker"

printf '#!/bin/bash\nexit 1\n' > "$TMP/simctl"; chmod +x "$TMP/simctl"
if run "$TMP/simctl" "iPhone 17" 26.2 >"$TMP/o" 2>&1; then fail "a failing simctl must fail"; fi
grep -q GRAPHGHAN_SIMULATOR_UNAVAILABLE "$TMP/o" || fail "a failing simctl should read as infrastructure"
pass "a failing simctl is treated as infrastructure"
