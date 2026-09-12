#!/bin/bash
# Runs a release script with App Store Connect credentials sourced from the login keychain,
# so archive.sh / upload.sh / asc-profiles.sh stay byte-identical between CI and the mini and
# their hermetic tests keep covering both.
#
# Usage: ios/Scripts/with-asc-credentials.sh <command> [args...]
#   e.g. ios/Scripts/with-asc-credentials.sh ios/Scripts/upload.sh build/Graphghan.ipa
#
# Only THREE values are secret here, not the seven `testflight.yml` sets. The other four
# (BUILD_CERTIFICATE_BASE64, P12_PASSWORD, both PROVISIONING_PROFILE_*_BASE64) exist purely to
# construct an ephemeral keychain on a throwaway runner. The mini's keychain is persistent: the
# distribution certificate is imported once and codesign finds it by identity, and the profiles
# live in ~/Library/MobileDevice/Provisioning Profiles/. So they never need to reach this box.
#
# The .p8 is written to a private temp file for the life of the command rather than kept on
# disk, because ASC_KEY_PATH is a path -- the scripts want a file, not the key's contents. At
# rest the key exists only inside the keychain.
#
# Keychain item names (the contract with the manual seeding step in RUNBOOK "mini build host"):
#   graphghan-asc-key-id       the ASC key id, e.g. ABCD1234EF
#   graphghan-asc-issuer-id    the ASC issuer id (a UUID)
#   graphghan-asc-private-key  the .p8 contents, including the BEGIN/END lines
#
# SECURITY overrides the `security` command so the test can serve a stub keychain.
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <command> [args...]" >&2
    exit 2
fi

SECURITY="${SECURITY:-security}"

# -w prints only the password. A missing item exits non-zero and is named in the message:
# "it didn't work" without saying which of the three is absent costs a real debugging session.
keychain_get() { # service-name
    local value
    if ! value="$("$SECURITY" find-generic-password -s "$1" -w 2>/dev/null)"; then
        echo "with-asc-credentials: keychain item '$1' not found in the login keychain." >&2
        echo "Seed it as the build account -- see ios/docs/release.md, 'Credentials on the mini'." >&2
        return 1
    fi
    printf '%s' "$value"
}

ASC_KEY_ID="$(keychain_get graphghan-asc-key-id)"
ASC_ISSUER_ID="$(keychain_get graphghan-asc-issuer-id)"
key_body="$(keychain_get graphghan-asc-private-key)"

# A private DIRECTORY rather than a temp file, for two reasons. Apple's tooling expects the
# conventional AuthKey_<key-id>.p8 filename, and BSD mktemp only substitutes Xs when they are
# TRAILING -- a template like "AuthKey_ID.XXXXXX.p8" is returned verbatim, exit 0, so the first
# run quietly creates a predictable shared path and the second run dies on "File exists".
# mktemp -d gives uniqueness; the directory carries the privacy and the file keeps its name.
ASC_KEY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/graphghan-asc.XXXXXX")" || {
    echo "with-asc-credentials: could not create a temp directory for the ASC key." >&2
    exit 1
}
chmod 700 "$ASC_KEY_DIR"
trap 'command rm -rf "${ASC_KEY_DIR:?}"' EXIT
ASC_KEY_PATH="$ASC_KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
printf '%s\n' "$key_body" > "$ASC_KEY_PATH"
chmod 600 "$ASC_KEY_PATH"

export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH

# Deliberately NOT exec: the EXIT trap above is what removes the key, and exec would replace
# this shell before it could fire, leaving the .p8 behind after every release.
"$@"
