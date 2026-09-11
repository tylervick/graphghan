#!/bin/bash
# Creates (or re-downloads) the two manually managed App Store provisioning profiles through the App
# Store Connect API and writes them under ios/build/profiles/. Idempotent: an existing profile of the
# same name is downloaded, not recreated. Needs ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (env or
# Scripts/.appstore.env). The App IDs must already exist with the App Group capability (Xcode's
# automatic signing created both on the first device build). Nothing here creates certificates: the
# profiles bind to the existing Apple Distribution certificate, the same one Waddle's p12 holds.
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
[ -f "$IOS/Scripts/.appstore.env" ] && source "$IOS/Scripts/.appstore.env"
: "${ASC_KEY_ID:?}"; : "${ASC_ISSUER_ID:?}"; : "${ASC_KEY_PATH:?}"
API="https://api.appstoreconnect.apple.com"
OUT="$IOS/build/profiles"; mkdir -p "$OUT"
TOKEN="$("$IOS/Scripts/asc-jwt.sh")"
get() { curl -sS -f -H "Authorization: Bearer $TOKEN" "$API$1"; }
post() { curl -sS --fail-with-body -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @- "$API$1"; }
jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

CERT_ID="$(get "/v1/certificates?filter%5BcertificateType%5D=DISTRIBUTION&limit=10" \
  | jq_py 'items=[c for c in d["data"] if c["attributes"].get("certificateType")=="DISTRIBUTION"]; print(items[0]["id"] if items else "")')"
[ -n "$CERT_ID" ] || { echo "error: no Apple Distribution certificate on the account" >&2; exit 1; }

make_profile() { # bundle-id, profile-name, out-file
    local bid name file bundle_res existing
    bid="$1"; name="$2"; file="$3"
    bundle_res="$(get "/v1/bundleIds?filter%5Bidentifier%5D=$bid&limit=5" \
      | jq_py "items=[b for b in d['data'] if b['attributes']['identifier']=='$bid']; print(items[0]['id'] if items else '')")"
    [ -n "$bundle_res" ] || { echo "error: no App ID for $bid; build once for a device with automatic signing first" >&2; exit 1; }
    existing="$(get "/v1/profiles?filter%5Bname%5D=$(printf '%s' "$name" | sed 's/ /%20/g')&limit=5" \
      | jq_py "items=[p for p in d['data'] if p['attributes']['name']=='$name' and p['attributes'].get('profileState')=='ACTIVE']; print(items[0]['attributes']['profileContent'] if items else '')")"
    if [ -z "$existing" ]; then
        existing="$(printf '{"data":{"type":"profiles","attributes":{"name":"%s","profileType":"IOS_APP_STORE"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"%s"}},"certificates":{"data":[{"type":"certificates","id":"%s"}]}}}}' "$name" "$bundle_res" "$CERT_ID" \
          | post "/v1/profiles" | jq_py 'print(d["data"]["attributes"]["profileContent"])')"
        echo "created profile: $name"
    else
        echo "downloaded existing profile: $name"
    fi
    printf '%s' "$existing" | /usr/bin/base64 --decode > "$file"
    security cms -D -i "$file" | plutil -extract ExpirationDate raw - | sed "s/^/  expires: /"
}
make_profile com.tylervick.graphghan "Graphghan App Store CI" "$OUT/app.mobileprovision"
make_profile com.tylervick.graphghan.widgets "Graphghan Widgets App Store CI" "$OUT/widgets.mobileprovision"

cat <<EOM

Profiles written under $OUT. Set the repository secrets (never commit these files):
  gh secret set PROVISIONING_PROFILE_APP_BASE64     -R tylervick/graphghan < <(/usr/bin/base64 -i "$OUT/app.mobileprovision")
  gh secret set PROVISIONING_PROFILE_WIDGETS_BASE64 -R tylervick/graphghan < <(/usr/bin/base64 -i "$OUT/widgets.mobileprovision")
EOM
