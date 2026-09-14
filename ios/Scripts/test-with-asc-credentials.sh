#!/bin/bash
# Hermetic tests for with-asc-credentials.sh: SECURITY points at a stub keychain, so nothing
# touches the real login keychain and no Apple credential is needed to run these.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "${TMP:?}"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# A stub `security`: serves find-generic-password -s <service> -w from a fixture directory,
# and exits 44 for an absent item the way the real tool does.
mkdir -p "$TMP/items"
cat > "$TMP/security" <<'STUB'
#!/bin/bash
svc=""
while [ $# -gt 0 ]; do
    [ "$1" = "-s" ] && svc="$2"
    shift
done
f="$(dirname "$0")/items/$svc"
[ -f "$f" ] || { echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2; exit 44; }
cat "$f"
STUB
chmod +x "$TMP/security"
seed() { printf '%s' "$2" > "$TMP/items/$1"; }
unseed() { command rm -f "$TMP/items/$1"; }

seed graphghan-asc-key-id      "ABCD1234EF"
seed graphghan-asc-issuer-id   "69a6de70-1111-47e3-e053-5b8c7c11a4d1"
# Deliberately NOT shaped like a real PEM. The secret-scanning hk step flags anything that
# looks like a private key, and it is right to -- nothing here needs PEM syntax. What is under
# test is that a multi-line body round-trips into a private file and never reaches the
# environment, which this sentinel exercises exactly as well.
SENTINEL='NOT-A-REAL-KEY-9f3a2c
second line of the fake key body'
seed graphghan-asc-private-key "$SENTINEL"

# A probe standing in for archive.sh/upload.sh: records what it was handed.
cat > "$TMP/probe" <<'PROBE'
#!/bin/bash
{
  echo "ASC_KEY_ID=$ASC_KEY_ID"
  echo "ASC_ISSUER_ID=$ASC_ISSUER_ID"
  echo "ASC_KEY_PATH=$ASC_KEY_PATH"
  echo "KEY_EXISTS=$([ -f "$ASC_KEY_PATH" ] && echo yes || echo no)"
  echo "KEY_MODE=$(stat -f '%Lp' "$ASC_KEY_PATH" 2>/dev/null)"
  echo "KEY_FIRST_LINE=$(head -1 "$ASC_KEY_PATH")"
  echo "ARGV=$*"
} > "$1"
PROBE
chmod +x "$TMP/probe"

run() { SECURITY="$TMP/security" "$HERE/with-asc-credentials.sh" "$@"; }

# --- the three values reach the wrapped command, and the key arrives as a FILE ---
run "$TMP/probe" "$TMP/out" extra-arg >/dev/null || fail "wrapper should run the command"
grep -q '^ASC_KEY_ID=ABCD1234EF$' "$TMP/out" || fail "key id not exported: $(cat "$TMP/out")"
grep -q '^ASC_ISSUER_ID=69a6de70-1111-47e3-e053-5b8c7c11a4d1$' "$TMP/out" || fail "issuer id not exported"
grep -q '^KEY_EXISTS=yes$' "$TMP/out" || fail "ASC_KEY_PATH does not point at a real file"
grep -q 'NOT-A-REAL-KEY-9f3a2c' "$TMP/out" || fail "the key file does not hold the key body"
grep -q "^ARGV=$TMP/out extra-arg$" "$TMP/out" || fail "arguments were not forwarded: $(cat "$TMP/out")"
pass "exports the three ASC values and forwards the command with its arguments"

# --- a missing keychain item must name the item and must NOT run the command ---
unseed graphghan-asc-issuer-id
command rm -f "$TMP/out"
set +e; err="$(run "$TMP/probe" "$TMP/out" 2>&1)"; rc=$?; set -e
[ "$rc" -ne 0 ] || fail "a missing keychain item should fail"
[ -f "$TMP/out" ] && fail "the command must not run when a credential is missing"
grep -q 'graphghan-asc-issuer-id' <<<"$err" || fail "the error should name the missing item: $err"
pass "a missing keychain item fails loudly by name, without running the command"
seed graphghan-asc-issuer-id "69a6de70-1111-47e3-e053-5b8c7c11a4d1"

# --- the key is private while it exists, and does not outlive the command ---
command rm -f "$TMP/out"
run "$TMP/probe" "$TMP/out" >/dev/null || fail "wrapper should run the command"
grep -q '^KEY_MODE=600$' "$TMP/out" || fail "the key file must be 0600: $(grep KEY_MODE "$TMP/out")"
pass "the ASC key file is mode 0600 while the command runs"

leaked="$(grep '^ASC_KEY_PATH=' "$TMP/out" | cut -d= -f2-)"
[ -n "$leaked" ] || fail "could not read back the key path"
[ -e "$leaked" ] && fail "the ASC key survived the wrapper at $leaked -- it must not outlive the run"
pass "the ASC key file is removed when the wrapper returns"

# The key's CONTENTS must never be handed to the child as an environment variable -- only the
# path. An env var is visible to every descendant and to `ps -E` on some systems.
env_dump="$TMP/env.txt"
cat > "$TMP/envprobe" <<'EP'
#!/bin/bash
env > "$1"
EP
chmod +x "$TMP/envprobe"
run "$TMP/envprobe" "$env_dump" >/dev/null || fail "wrapper should run the env probe"
grep -q 'NOT-A-REAL-KEY-9f3a2c' "$env_dump" && fail "the private key leaked into the child's environment"
pass "the private key reaches the command as a file, never as an environment variable"

# Two releases in a row must both work, and must not reuse one predictable path. BSD mktemp
# only substitutes trailing Xs -- a template like AuthKey_ID.XXXXXX.p8 silently yields that
# literal name, so the first run succeeds, the file lingers, and the SECOND run collides.
run "$TMP/probe" "$TMP/out1" >/dev/null || fail "first consecutive run failed"
run "$TMP/probe" "$TMP/out2" >/dev/null || fail "second consecutive run failed -- a stale key path collided"
p1="$(grep '^ASC_KEY_PATH=' "$TMP/out1" | cut -d= -f2-)"
p2="$(grep '^ASC_KEY_PATH=' "$TMP/out2" | cut -d= -f2-)"
[ "$p1" != "$p2" ] || fail "consecutive runs reused the same key path: $p1"
grep -q 'X\{4,\}' <<<"$p1" && fail "mktemp did not substitute its template: $p1"
pass "consecutive runs each get a fresh, unpredictable key path"
