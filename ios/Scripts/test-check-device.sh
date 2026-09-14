#!/bin/bash
# Hermetic tests for check-device-available.sh: DEVICECTL points at a stub that writes a
# fixture to whatever path the script passes to --json-output, the way the real tool does.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "${TMP:?}"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# A stub devicectl: finds --json-output in its own argv and writes the fixture there, so the
# script's real calling convention is exercised rather than a simplified stand-in.
stub() { # fixture-json -> path of a stub devicectl
    printf '%s' "$1" > "$TMP/fixture.json"
    cat > "$TMP/devicectl" <<'STUB'
#!/bin/bash
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = "--json-output" ]; then out="$2"; shift; fi
    shift
done
[ -n "$out" ] && cp "$(dirname "$0")/fixture.json" "$out"
exit "${STUB_RC:-0}"
STUB
    chmod +x "$TMP/devicectl"
    echo "$TMP/devicectl"
}

PAIRED='{"result":{"devices":[
  {"identifier":"00008120-001A2B3C4D5E6F70",
   "deviceProperties":{"name":"Tyler iPhone","osVersionNumber":"18.5"},
   "connectionProperties":{"tunnelState":"connected","pairingState":"paired"},
   "hardwareProperties":{"platform":"iOS","udid":"00008120-001A2B3C4D5E6F70"}}
]}}'

run() { DEVICE_CHECK_DELAY=0 DEVICE_CHECK_ATTEMPTS=2 DEVICECTL="$1" "$HERE/check-device-available.sh" ${2+"$2"}; }

out="$(run "$(stub "$PAIRED")")" || fail "a connected paired iOS device should be found: $out"
grep -q 'device: Tyler iPhone (00008120-001A2B3C4D5E6F70)' <<<"$out" \
    || fail "wrong identification line: $out"
pass "a connected paired iOS device is found and identified"

# Absence is the normal case, not a fault: it must be told apart from a broken toolchain by
# exit code alone, so callers can degrade to the simulator without grepping stderr.
EMPTY='{"result":{"devices":[]}}'
set +e; out="$(run "$(stub "$EMPTY")" 2>&1)"; rc=$?; set -e
[ "$rc" -eq 3 ] || fail "no devices should exit 3 (degrade), got $rc: $out"
grep -q 'GRAPHGHAN_DEVICE_UNAVAILABLE' <<<"$out" || fail "missing the degrade marker: $out"
pass "no connected device exits 3 with the degrade marker"

# Asking for a device that is not there while others ARE is a pin problem, not a timing one.
# It must NOT read as "degrade to simulator" -- silently building on the wrong phone is worse
# than failing -- and it must not burn the retry schedule waiting for something that cannot arrive.
set +e; out="$(run "$(stub "$PAIRED")" "Meaghan iPhone" 2>&1)"; rc=$?; set -e
[ "$rc" -eq 1 ] || fail "a missing named device should exit 1 (fault), got $rc: $out"
grep -q 'pin problem' <<<"$out" || fail "missing the pin-problem diagnosis: $out"
grep -q 'GRAPHGHAN_DEVICE_UNAVAILABLE' <<<"$out" && fail "must not read as degradable: $out"
pass "a named device that is absent while others are connected exits 1, not 3"

# The same name, matched exactly, still works -- the filter must not reject its own target.
out="$(run "$(stub "$PAIRED")" "Tyler iPhone")" || fail "exact name should match: $out"
grep -q 'device: Tyler iPhone' <<<"$out" || fail "wrong match for an exact name: $out"
pass "an exactly-named connected device is matched"

# A broken devicectl must NOT read as "no device, degrade to the simulator" -- that would
# silently stop device testing forever while every run still looked green.
set +e; out="$(STUB_RC=1 run "$(stub "$PAIRED")" 2>&1)"; rc=$?; set -e
[ "$rc" -eq 1 ] || fail "a failing devicectl should exit 1 (fault), got $rc: $out"
grep -q 'GRAPHGHAN_DEVICE_UNAVAILABLE' <<<"$out" && fail "a broken tool must not read as degradable: $out"
pass "a failing devicectl exits 1, not 3"

# Paired but not connected is the locked-phone / out-of-the-house case: degradable, not a fault.
DISCONNECTED='{"result":{"devices":[
  {"identifier":"00008120-001A2B3C4D5E6F70",
   "deviceProperties":{"name":"Tyler iPhone"},
   "connectionProperties":{"tunnelState":"unavailable","pairingState":"paired"},
   "hardwareProperties":{"platform":"iOS","udid":"00008120-001A2B3C4D5E6F70"}}
]}}'
set +e; out="$(run "$(stub "$DISCONNECTED")" 2>&1)"; rc=$?; set -e
[ "$rc" -eq 3 ] || fail "a paired-but-disconnected device should exit 3, got $rc: $out"
pass "a paired but disconnected device is degradable, not a match"
