#!/usr/bin/env bash
# Register a new bundle ID and (attempt to) create an App Store Connect app.
#
# Apple's public API does NOT allow creating apps (POST /v1/apps is forbidden
# on standard accounts); this script only registers the bundle ID reliably.
# Creating the app record requires a 60-second click in the ASC web UI — the
# script prints the exact fields to fill in.
#
# Required env:
#   ASC_KEY_ID        10-char API key id (e.g. 48ZWN983JL)
#   ASC_ISSUER_ID     UUID from appstoreconnect.apple.com/access/integrations/api
#   ASC_TEAM_ID       10-char Apple Developer Team ID
#
# Required flags (NEVER hardcode below — every call must pass these):
#   --bundle-id       e.g. com.example.app
#   --app-name        e.g. ExampleApp    (used for bundle display name AND app name)
#   --sku             e.g. EXAMPLE001
#   --locale          optional, defaults to en-US
#
# Example:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_TEAM_ID=... \
#     ./asc_create_app.sh --bundle-id com.hydrolite.app --app-name HydroLite --sku HYDROLITE001
#
# KNOWN PITFALL (fixed in this script):
#   Older copies had the app name hardcoded inside the JSON body of the bundle
#   POST, so when the script was duplicated from a previous app, new bundles
#   inherited the old name and the ASC "New App" dropdown showed the wrong
#   name. This version parameterizes 100% via the --app-name flag and also
#   PATCHes any existing bundle's display name on every run (idempotent).
set -euo pipefail

: "${ASC_KEY_ID:?set ASC_KEY_ID (10-char key id)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (UUID)}"
: "${ASC_TEAM_ID:?set ASC_TEAM_ID (10-char team ID)}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

BUNDLE_ID=""
APP_NAME=""
SKU=""
PRIMARY_LOCALE="${PRIMARY_LOCALE:-en-US}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --app-name)  APP_NAME="$2";  shift 2 ;;
    --sku)       SKU="$2";       shift 2 ;;
    --locale)    PRIMARY_LOCALE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$BUNDLE_ID" || -z "$APP_NAME" || -z "$SKU" ]]; then
  cat >&2 <<EOF
Required: --bundle-id <id> --app-name <name> --sku <sku>

Example:
  $0 --bundle-id com.example.app --app-name Example --sku EXAMPLE001
EOF
  exit 2
fi

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "private key not found at $ASC_KEY_PATH" >&2
  exit 1
fi

# Mint JWT.
JWT=$(python3 - <<PY
import jwt, time
with open("${ASC_KEY_PATH}", "rb") as f: key = f.read()
print(jwt.encode(
    {"iss":"${ASC_ISSUER_ID}","iat":int(time.time()),"exp":int(time.time())+1200,"aud":"appstoreconnect-v1"},
    key, algorithm="ES256", headers={"kid":"${ASC_KEY_ID}","typ":"JWT"}))
PY
)
AUTH=( -H "Authorization: Bearer ${JWT}" -H "Content-Type: application/json" )

echo "==> Looking up bundle ID ${BUNDLE_ID}"
BUNDLE_RESP=$(curl -sSf -g "https://api.appstoreconnect.apple.com/v1/bundleIds?filter%5Bidentifier%5D=${BUNDLE_ID}" "${AUTH[@]}")
BUNDLE_RELID=$(echo "$BUNDLE_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"][0]["id"] if d.get("data") else "")')

if [[ -z "$BUNDLE_RELID" ]]; then
  echo "==> Creating bundle ID ${BUNDLE_ID} with display name '${APP_NAME}'"
  BUNDLE_RELID=$(curl -sSf -X POST "https://api.appstoreconnect.apple.com/v1/bundleIds" "${AUTH[@]}" \
    -d "{\"data\":{\"type\":\"bundleIds\",\"attributes\":{\"identifier\":\"${BUNDLE_ID}\",\"name\":\"${APP_NAME}\",\"platform\":\"IOS\"}}}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["id"])')
else
  # Bundle exists — ensure the display name matches this app so the ASC
  # "New App" dropdown shows the right name. Idempotent.
  CURRENT_NAME=$(echo "$BUNDLE_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["attributes"].get("name",""))')
  if [[ "$CURRENT_NAME" != "$APP_NAME" ]]; then
    echo "==> Bundle ${BUNDLE_RELID} exists with name '${CURRENT_NAME}' — renaming to '${APP_NAME}'"
    curl -sSf -X PATCH "https://api.appstoreconnect.apple.com/v1/bundleIds/${BUNDLE_RELID}" "${AUTH[@]}" \
      -d "{\"data\":{\"type\":\"bundleIds\",\"id\":\"${BUNDLE_RELID}\",\"attributes\":{\"name\":\"${APP_NAME}\"}}}" > /dev/null
  else
    echo "==> Bundle ${BUNDLE_RELID} exists with correct name '${APP_NAME}'"
  fi
fi

# Try POST /v1/apps. Expected to 403 on standard accounts.
APP_RESP=$(curl -sS -X POST "https://api.appstoreconnect.apple.com/v1/apps" "${AUTH[@]}" \
  -d "{
    \"data\": {
      \"type\": \"apps\",
      \"attributes\": {
        \"name\": \"${APP_NAME}\",
        \"primaryLocale\": \"${PRIMARY_LOCALE}\",
        \"sku\": \"${SKU}\",
        \"bundleId\": \"${BUNDLE_ID}\"
      },
      \"relationships\": {
        \"bundleId\": {\"data\": {\"type\": \"bundleIds\", \"id\": \"${BUNDLE_RELID}\"}}
      }
    }
  }")
APP_ID=$(echo "$APP_RESP" | python3 -c 'import json,sys,os
try:
    d=json.load(sys.stdin); print(d.get("data",{}).get("id",""))
except: print("")' 2>/dev/null || echo "")

if [[ -n "$APP_ID" ]]; then
  echo "==> App record created via API: ${APP_ID}"
  echo "==> Open https://appstoreconnect.apple.com/apps/${APP_ID} to continue"
else
  cat <<EOF

==> API app-create is not permitted (expected). Finish in the web UI — 60 seconds:
    1. Open https://appstoreconnect.apple.com/apps
    2. Click  +  →  New App
    3. Fill in:
         Platform:          iOS
         Name:              ${APP_NAME}
         Primary Language:  ${PRIMARY_LOCALE}
         Bundle ID:         ${BUNDLE_ID}
                            (appears in the dropdown labeled "${APP_NAME}")
         SKU:               ${SKU}
         User Access:       Full Access

==> Bundle '${BUNDLE_ID}' is registered with display name '${APP_NAME}'.
EOF
fi
