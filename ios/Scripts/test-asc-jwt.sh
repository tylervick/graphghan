#!/bin/bash
# asc-jwt.sh: the DER->JOSE conversion must produce exactly 64 bytes (r||s, each left-padded to 32),
# including for a short r and for an r carrying DER's leading 0x00 sign byte. A wrong length is a
# bare 401 from App Store Connect with no diagnostic.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

jose_len() { # hex DER on stdin -> decoded byte length of the JOSE output
    python3 -c '
import sys, base64
s = sys.stdin.read().strip()
s += "=" * (-len(s) % 4)
print(len(base64.urlsafe_b64decode(s)))'
}
der() { python3 -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.argv[1]))' "$1"; }

# r and s both 32 bytes, high bit clear.
R32=$(printf '1%.0s' $(seq 1 64)); S32=$(printf '2%.0s' $(seq 1 64))
out="$(der "30440220${R32}0220${S32}" | "$HERE/asc-jwt.sh" --der-to-jose)"
[ "$(jose_len <<<"$out")" -eq 64 ] || fail "plain 32/32 case: wrong length"
pass "32-byte r and s convert to 64 bytes"

# r has the high bit set, so DER prefixes 0x00 and encodes it as 33 bytes.
R_HI="ff$(printf '1%.0s' $(seq 1 62))"
out="$(der "3045022100${R_HI}0220${S32}" | "$HERE/asc-jwt.sh" --der-to-jose)"
[ "$(jose_len <<<"$out")" -eq 64 ] || fail "sign-byte case: wrong length"
pass "a DER sign byte is stripped"

# r is short (31 bytes) because DER drops leading zeros.
R_SHORT=$(printf '3%.0s' $(seq 1 62))
out="$(der "3043021f${R_SHORT}0220${S32}" | "$HERE/asc-jwt.sh" --der-to-jose)"
[ "$(jose_len <<<"$out")" -eq 64 ] || fail "short-r case: wrong length"
pass "a short r is left-padded"

# A real mint with a throwaway key produces three dot-separated parts and a 64-byte signature.
openssl ecparam -name prime256v1 -genkey -noout -out "$TMP/k.p8" 2>/dev/null
tok="$(ASC_KEY_ID=ABCDEFGHIJ ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 ASC_KEY_PATH="$TMP/k.p8" "$HERE/asc-jwt.sh")"
[ "$(tr -cd '.' <<<"$tok" | wc -c | tr -d ' ')" -eq 2 ] || fail "token is not three parts"
[ "$(jose_len <<<"${tok##*.}")" -eq 64 ] || fail "minted signature is not 64 bytes"
pass "mints a three-part token with a 64-byte signature"
