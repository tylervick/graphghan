#!/bin/bash
# Creates (or re-downloads) the two manually managed App Store provisioning profiles through the App
# Store Connect API and writes them under ios/build/profiles/. Idempotent: an ACTIVE profile of the
# same name is downloaded, not recreated; a same-name profile in any other state (EXPIRED / INVALID,
# which is what a certificate renewal leaves behind) is deleted and recreated, because Apple refuses
# to create a second profile with a name already taken. Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH
# (env or Scripts/.appstore.env). The App IDs must already exist with the App Group capability
# (Xcode's automatic signing created both on the first device build). Nothing here creates
# certificates: the profiles bind to an existing, unexpired Apple Distribution certificate, the same
# one Waddle's p12 holds. With more than one unexpired Distribution certificate on the account the
# script refuses to guess and lists them; re-run with ASC_CERT_ID=<id> to choose.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
[ -f "$IOS/Scripts/.appstore.env" ] && source "$IOS/Scripts/.appstore.env"
: "${ASC_KEY_ID:?}"; : "${ASC_ISSUER_ID:?}"; : "${ASC_KEY_PATH:?}"
API="https://api.appstoreconnect.apple.com"
OUT="$IOS/build/profiles"; mkdir -p "$OUT"
TOKEN="$("$IOS/Scripts/asc-jwt.sh")"
# --fail-with-body rather than -f: Apple's 4xx bodies carry the only useful diagnostic (which
# capability is missing, which name is taken), and -f throws the body away.
get() { curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN" "$API$1"; }
post() { curl -sS --fail-with-body -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @- "$API$1"; }
jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

# DELETE answers 204 with no body; anything else (including a 200) is treated as a failure so a
# half-deleted profile cannot be mistaken for a clean slate.
delete_profile() { # profile-id
    local tmp code
    tmp="$(mktemp "${TMPDIR:-/tmp}/asc-del.XXXXXX")"
    code="$(curl -sS --fail-with-body -X DELETE -H "Authorization: Bearer $TOKEN" \
              -o "$tmp" -w '%{http_code}' "$API/v1/profiles/$1")" || true
    if [ "$code" != "204" ]; then
        echo "error: DELETE /v1/profiles/$1 returned ${code:-no status}; profile not deleted." >&2
        cat "$tmp" >&2 || true
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
}

# Reads a /v1/bundleIds response on stdin, prints the id of the exact identifier match.
bundle_pick() { # identifier
    PICK_BID="$1" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
items = [b for b in (d.get("data") or []) if (b.get("attributes") or {}).get("identifier") == os.environ["PICK_BID"]]
print(items[0]["id"] if items else "")'
}

# Reads a /v1/profiles response on stdin, prints one field of the exact name match ("" if none).
# The name goes through the environment, not into the python source: interpolating it would make a
# quote in a profile name a syntax error at best.
profile_pick() { # name, id|profileState|profileContent
    PICK_NAME="$1" PICK_KEY="$2" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
items = [p for p in (d.get("data") or []) if (p.get("attributes") or {}).get("name") == os.environ["PICK_NAME"]]
if not items:
    print(""); raise SystemExit(0)
p = items[0]; key = os.environ["PICK_KEY"]
print((p.get("id") if key == "id" else (p.get("attributes") or {}).get(key)) or "")'
}

# The account can hold several Distribution certificates (a renewal leaves the old one listed until
# it is revoked), and binding a profile to an expired one produces a profile that exports nothing.
# Expiry is decided by parsing the timestamp, not by trusting Apple's status string.
CERTS_RESP="$(get "/v1/certificates?filter%5BcertificateType%5D=DISTRIBUTION&limit=50")"
CERT_ID="$(printf '%s' "$CERTS_RESP" | ASC_CERT_ID="${ASC_CERT_ID:-}" python3 -c '
import json, os, re, sys
from datetime import datetime, timezone

def parse(ts):
    s = (ts or "").strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    # Apple writes the offset as +0000; fromisoformat wants +00:00 before python 3.11.
    m = re.search(r"([+-])(\d{2})(\d{2})$", s)
    if m:
        s = s[:m.start()] + "%s%s:%s" % m.groups()
    try:
        d = datetime.fromisoformat(s)
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)

doc = json.load(sys.stdin)
now = datetime.now(timezone.utc)
live = []
for c in doc.get("data") or []:
    a = c.get("attributes") or {}
    if a.get("certificateType") != "DISTRIBUTION":
        continue
    exp = parse(a.get("expirationDate"))
    if exp is None or exp <= now:
        continue
    name = a.get("name") or ""
    disp = a.get("displayName") or ""
    label = name if (not disp or disp == name) else ("%s / %s" % (name, disp) if name else disp)
    live.append((c.get("id") or "", label or "(unnamed)", a.get("expirationDate") or "(no expiry)"))

def listing():
    return "".join("  id=%s  name=%s  expires=%s\n" % c for c in live) or "  (none)\n"

def bail(msg):
    sys.stderr.write(msg)
    raise SystemExit(1)

want = (os.environ.get("ASC_CERT_ID") or "").strip()
if want:
    if want not in [c[0] for c in live]:
        bail("error: ASC_CERT_ID=%s is not an unexpired Distribution certificate on this account.\n"
             "Unexpired Distribution certificates:\n%s" % (want, listing()))
    print(want)
elif len(live) == 1:
    print(live[0][0])
elif not live:
    bail("error: no unexpired Apple Distribution certificate on the account.\n"
         "       Create or renew one in the developer portal, then re-run.\n")
else:
    bail("error: %d unexpired Apple Distribution certificates on the account; refusing to guess.\n"
         "%s"
         "       Re-run with ASC_CERT_ID=<id> for the one whose private key the p12 secret holds.\n"
         % (len(live), listing()))')"
[ -n "$CERT_ID" ] || { echo "error: could not select a Distribution certificate" >&2; exit 1; }
echo "using Distribution certificate: $CERT_ID"

make_profile() { # bundle-id, profile-name, out-file
    local bid name file bundle_res resp pid pstate content
    bid="$1"; name="$2"; file="$3"
    resp="$(get "/v1/bundleIds?filter%5Bidentifier%5D=$bid&limit=5")"
    bundle_res="$(printf '%s' "$resp" | bundle_pick "$bid")"
    [ -n "$bundle_res" ] || { echo "error: no App ID for $bid; build once for a device with automatic signing first" >&2; exit 1; }
    # Any profileState, not just ACTIVE: an EXPIRED or INVALID profile still occupies the name, so
    # filtering it out here would turn every post-renewal run into a "name already taken" 409.
    resp="$(get "/v1/profiles?filter%5Bname%5D=$(printf '%s' "$name" | sed 's/ /%20/g')&limit=10")"
    pid="$(printf '%s' "$resp" | profile_pick "$name" id)"
    pstate="$(printf '%s' "$resp" | profile_pick "$name" profileState)"
    if [ -n "$pid" ] && [ "$pstate" = "ACTIVE" ]; then
        content="$(printf '%s' "$resp" | profile_pick "$name" profileContent)"
        echo "downloaded existing profile: $name"
    else
        if [ -n "$pid" ]; then
            delete_profile "$pid"
            echo "deleted stale profile: $name (${pstate:-unknown state})"
        fi
        content="$(printf '{"data":{"type":"profiles","attributes":{"name":"%s","profileType":"IOS_APP_STORE"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"%s"}},"certificates":{"data":[{"type":"certificates","id":"%s"}]}}}}' "$name" "$bundle_res" "$CERT_ID" \
          | post "/v1/profiles" | jq_py 'print(d["data"]["attributes"]["profileContent"])')"
        echo "created profile: $name"
    fi
    [ -n "$content" ] || { echo "error: App Store Connect returned no profileContent for $name" >&2; exit 1; }
    printf '%s' "$content" | /usr/bin/base64 --decode > "$file"
    security cms -D -i "$file" | plutil -extract ExpirationDate raw - | sed "s/^/  expires: /"
}
make_profile com.tylervick.graphghan "Graphghan App Store CI" "$OUT/app.mobileprovision"
make_profile com.tylervick.graphghan.widgets "Graphghan Widgets App Store CI" "$OUT/widgets.mobileprovision"

cat <<EOM

Profiles written under $OUT. Set the repository secrets (never commit these files):
  gh secret set PROVISIONING_PROFILE_APP_BASE64     -R tylervick/graphghan < <(/usr/bin/base64 -i "$OUT/app.mobileprovision")
  gh secret set PROVISIONING_PROFILE_WIDGETS_BASE64 -R tylervick/graphghan < <(/usr/bin/base64 -i "$OUT/widgets.mobileprovision")
EOM
