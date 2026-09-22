#!/bin/bash
# Build, install and launch on a tethered iPhone, then stream the app's console (#176).
#
#   Scripts/run-on-device.sh              the one connected iPhone
#   GRAPHGHAN_DEVICE=<udid> Scripts/...   a particular one
#
# Why this exists: the on-device model is the only place the row check fails, the simulator has
# none, and five TestFlight round trips to read a dozen lines off a screen is no way to debug.
# With the phone plugged into the mini this is one command and a live log.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
cd "$IOS"

BUNDLE_ID="com.tylervick.graphghan"

device() {
    if [ -n "${GRAPHGHAN_DEVICE:-}" ]; then
        echo "$GRAPHGHAN_DEVICE"
        return
    fi
    # "physical" is what tells a real iPhone from the simulators in the same listing.
    xcrun devicectl list devices 2>/dev/null \
        | awk '$0 ~ /physical/ && $0 ~ /connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-Fa-f-]{25,}$/) { print $i; exit } }'
}

UDID="$(device)"
if [ -z "$UDID" ]; then
    echo "No iPhone is paired with this Mac." >&2
    echo "Plug one in over USB, unlock it and trust this computer; or pair it over Wi-Fi in" >&2
    echo "Xcode > Window > Devices and Simulators. Then run this again." >&2
    echo >&2
    echo "What is visible now:" >&2
    xcrun devicectl list devices 2>&1 | sed 's/^/  /' >&2
    exit 1
fi
echo "==> device $UDID"

xcodebuild build -quiet -project Graphghan.xcodeproj -scheme Graphghan \
    -destination "platform=iOS,id=$UDID" -derivedDataPath build/DerivedData

APP="$(find build/DerivedData/Build/Products -maxdepth 2 -name Graphghan.app -path '*iphoneos*' | head -1)"
[ -n "$APP" ] || { echo "No Graphghan.app was built for the device." >&2; exit 1; }
echo "==> installing $APP"
xcrun devicectl device install app --device "$UDID" "$APP"

echo "==> launching with the console attached; Ctrl-C to stop"
exec xcrun devicectl device process launch --device "$UDID" --console --terminate-existing "$BUNDLE_ID"
