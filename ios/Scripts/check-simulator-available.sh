#!/bin/bash
# Confirms a named iOS Simulator device/OS pair is genuinely available before a build spends the
# whole run against it. On a cold macOS runner CoreSimulator sometimes enumerates NO devices at
# all for the first minute; xcodebuild then fails ~60s in with "Unable to find a device matching
# the provided destination specifier". That is infrastructure, not the code under test, and a
# re-run fixes it -- so this guard retries, and distinguishes "nothing enumerated" (prints the
# GRAPHGHAN_SIMULATOR_UNAVAILABLE marker: re-run the job) from "devices enumerated but none match"
# (a genuine destination pin problem: a re-run will not help).
#
# Usage: ios/Scripts/check-simulator-available.sh <device-name> <os-version>
#   e.g. ios/Scripts/check-simulator-available.sh "iPhone 17" 26.2
# SIMULATOR_CHECK_ATTEMPTS / SIMULATOR_CHECK_DELAY (seconds) override the schedule; the test sets
# the delay to 0. SIMCTL overrides the `xcrun simctl` command so the test can feed fixtures.
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <device-name> <os-version>" >&2
    exit 2
fi
DEVICE_NAME="$1"
OS_VERSION="$2"
ATTEMPTS="${SIMULATOR_CHECK_ATTEMPTS:-5}"
DELAY="${SIMULATOR_CHECK_DELAY:-15}"
SIMCTL="${SIMCTL:-xcrun simctl}"

listing=""
total_count=0
match_line=""

query_once() {
    # A failing simctl is the same infrastructure signal as an empty enumeration; do not mask it.
    if listing="$($SIMCTL list devices available 2>&1)"; then
        :
    else
        listing=""
    fi
    total_count="$(printf '%s\n' "$listing" | grep -cE '^    [^[:space:]]' || true)"
    # Exact match on the name inside the requested OS section. The name is recovered by peeling the two
    # trailing "(udid) (state)" fields off the right, because device names themselves may contain parentheses.
    match_line="$(printf '%s\n' "$listing" | awk -v os="$OS_VERSION" -v dev="$DEVICE_NAME" '
        /^-- / { insection = ($0 == "-- iOS " os " --"); next }
        insection && /^    / {
            line = $0
            sub(/^    /, "", line)
            sub(/[[:space:]]+$/, "", line)
            name = line
            sub(/ \([^()]*\)$/, "", name)
            sub(/ \([^()]*\)$/, "", name)
            if (name == dev) { print line; exit }
        }
    ')"
}

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
    query_once
    if [ -n "$match_line" ]; then
        echo "matched: $match_line (iOS $OS_VERSION, attempt $attempt/$ATTEMPTS)"
        exit 0
    fi
    if [ "$attempt" -lt "$ATTEMPTS" ]; then
        sleep "$DELAY"
    fi
    attempt=$((attempt + 1))
done

if [ "$total_count" -eq 0 ]; then
    echo "::error::GRAPHGHAN_SIMULATOR_UNAVAILABLE -- CoreSimulator enumerated zero simulators after $ATTEMPTS attempts. Runner infrastructure, not the code under test: re-run the job."
else
    echo "::error::requested simulator not found: '$DEVICE_NAME' (iOS $OS_VERSION) -- $total_count other device(s) enumerated. A genuine destination pin problem; re-running will not fix it."
fi
echo "requested: name=\"$DEVICE_NAME\" OS=$OS_VERSION"
printf '%s\n' "$listing"
exit 1
