#!/bin/bash
# Resolves a paired, connected iOS device before a build spends a run trying to reach one.
#
# Unlike check-simulator-available.sh, absence here is NORMAL rather than exceptional: the
# device lane is Tyler's own phone, reachable over the LAN by Bonjour/mDNS, so it is simply
# not there when he is out of the house or the screen is locked. A task that needs a device
# must be able to tell "no device, fall back to the simulator and say so" apart from "the
# toolchain is broken" -- hence three outcomes rather than two.
#
# Usage: ios/Scripts/check-device-available.sh [device-name-or-udid]
#   With no argument, any connected iOS device matches.
#
# Exit codes:
#   0  a device is available; prints  device: <name> (<udid>)
#   3  GRAPHGHAN_DEVICE_UNAVAILABLE -- nothing connected. Expected; degrade to the simulator.
#   1  a genuine fault -- devicectl failed, or a specific device was asked for while others
#      were connected (a pin problem: retrying will not help).
#
# DEVICE_CHECK_ATTEMPTS / DEVICE_CHECK_DELAY override the retry schedule; the test sets the
# delay to 0. DEVICECTL overrides `xcrun devicectl` so the test can feed fixtures.
set -euo pipefail

WANTED="${1:-}"
ATTEMPTS="${DEVICE_CHECK_ATTEMPTS:-3}"
DELAY="${DEVICE_CHECK_DELAY:-5}"
DEVICECTL="${DEVICECTL:-xcrun devicectl}"

TMPJSON="$(mktemp)" || { echo "could not create a temp file" >&2; exit 1; }
trap 'rm -f "${TMPJSON:?}"' EXIT

# --json-output rather than the columnar text: device names contain spaces and apostrophes,
# and the column layout has changed between Xcode releases.
query() {
    $DEVICECTL list devices --json-output "$TMPJSON" >/dev/null 2>&1 || return 1
    python3 - "$TMPJSON" "$WANTED" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        devices = json.load(fh)["result"]["devices"]
except Exception:
    sys.exit(2)
connected = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if hw.get("platform") != "iOS":
        continue
    if conn.get("tunnelState") != "connected":
        continue
    name = d.get("deviceProperties", {}).get("name", "")
    udid = hw.get("udid") or d.get("identifier", "")
    connected.append((name, udid))
if not connected:
    sys.exit(3)
if wanted:
    for name, udid in connected:
        if wanted in (name, udid):
            print(f"{name}\t{udid}")
            sys.exit(0)
    # Distinct from 3: devices ARE connected, just not this one. Building on whichever
    # phone happens to be plugged in is worse than not building at all.
    sys.exit(4)
name, udid = connected[0]
print(f"{name}\t{udid}")
PY
}

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
    if match="$(query)"; then
        printf 'device: %s (%s)\n' "${match%%$'\t'*}" "${match##*$'\t'}"
        exit 0
    else
        # Captured inside the else on purpose: after `fi`, $? is the status of the IF
        # STATEMENT -- which is 0 when the condition failed and no branch ran -- not the
        # status of the condition. Reading it there silently loses query()'s exit code.
        rc=$?
    fi
    # A pin problem cannot resolve itself by waiting, so stop rather than burn the schedule.
    [ "$rc" -eq 4 ] && break
    [ "$attempt" -lt "$ATTEMPTS" ] && sleep "$DELAY"
    attempt=$((attempt + 1))
done

if [ "${rc:-1}" -eq 4 ]; then
    echo "requested device not connected: '$WANTED', but other iOS devices are." >&2
    echo "A pin problem rather than a timing one; retrying will not help." >&2
    exit 1
fi
if [ "${rc:-1}" -eq 3 ]; then
    echo "GRAPHGHAN_DEVICE_UNAVAILABLE -- no connected iOS device after $ATTEMPTS attempt(s)."
    echo "Expected when the phone is away or locked. Callers should fall back to the simulator and say so."
    exit 3
fi
echo "could not enumerate a device." >&2
exit 1
