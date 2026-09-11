#!/bin/bash
# Builds an App Store archive and exports the .ipa. Run from anywhere; paths are relative to ios/.
#
# Optional CI behaviour, all inert when the variables are unset (test-archive-args.sh proves it):
#   ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID  App Store Connect API key for a runner with no signed-in
#                                              Xcode account. All three or none.
#   BUILD_NUMBER          overrides CURRENT_PROJECT_VERSION for this build (applies to app and extension).
#   EXPORT_OPTIONS_PLIST  defaults to ExportOptions.plist (automatic, local). CI passes ExportOptions-ci.plist.
#   ARCHIVE_PRINT_ONLY=1  print the command lines and exit; used by the test.
#
# "${ARR[@]+"${ARR[@]}"}": macOS /bin/bash is 3.2, where `set -u` aborts on an empty array otherwise.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"

ASC_ARGS=()
if [ -n "${ASC_KEY_PATH:-}" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    ASC_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
VERSION_ARGS=()
if [ -n "${BUILD_NUMBER:-}" ]; then
    VERSION_ARGS=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi
EXPORT_PLIST="${EXPORT_OPTIONS_PLIST:-ExportOptions.plist}"
ARCHIVE="$IOS/build/archive/Graphghan.xcarchive"
EXPORT_DIR="$IOS/build/archive/export"

# Defence against the one irreversible failure: with API-key auth and an automatic-signing plist, the
# export's -allowProvisioningUpdates would MINT a Distribution certificate. Refuse rather than trust the caller.
if [ -n "${ASC_KEY_PATH:-}" ] && [ -z "${EXPORT_OPTIONS_PLIST:-}" ]; then
    echo "error: ASC key auth requires an explicit manual-signing export plist." >&2
    echo "       set EXPORT_OPTIONS_PLIST (e.g. ExportOptions-ci.plist)." >&2
    exit 1
fi

if [ "${ARCHIVE_PRINT_ONLY:-}" = "1" ]; then
    echo "ARCHIVE: xcodebuild -project Graphghan.xcodeproj -scheme Graphghan -destination generic/platform=iOS" \
         "-configuration Release -archivePath $ARCHIVE" \
         "${ASC_ARGS[@]+"${ASC_ARGS[@]}"}" "${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"}" "archive"
    echo "EXPORT: xcodebuild -exportArchive -archivePath $ARCHIVE -exportOptionsPlist $EXPORT_PLIST" \
         "-exportPath $EXPORT_DIR" "${ASC_ARGS[@]+"${ASC_ARGS[@]}"}" "-allowProvisioningUpdates"
    exit 0
fi

cd "$IOS"
xcodegen generate --quiet
# No -allowProvisioningUpdates on the archive: CI signs manually with pre-installed profiles, and on
# an automatic-signing local run it would let xcodebuild mint a certificate when the identity is missing.
xcodebuild -project Graphghan.xcodeproj -scheme Graphghan \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath "$ARCHIVE" \
  "${ASC_ARGS[@]+"${ASC_ARGS[@]}"}" "${VERSION_ARGS[@]+"${VERSION_ARGS[@]}"}" \
  archive
rm -rf "$EXPORT_DIR"
# /usr/bin first: a Homebrew rsync ahead on PATH breaks Xcode's IPA copy step ("Copy failed").
# -allowProvisioningUpdates is a no-op under the manual CI plist; locally it lets a first-time bundle
# id mint its App Store profile.
PATH="/usr/bin:$PATH" xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" -exportPath "$EXPORT_DIR" \
  "${ASC_ARGS[@]+"${ASC_ARGS[@]}"}" \
  -allowProvisioningUpdates
echo "IPA at $EXPORT_DIR/"
