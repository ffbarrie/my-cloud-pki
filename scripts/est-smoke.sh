#!/usr/bin/env bash
# Smoke-test companion EST MVP: /cacerts, /simpleenroll, /simplereenroll stub.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART="$ROOT/est/artifacts"
EST_HOST="${EST_HOST:-localhost}"
EST_PORT="${EST_HTTPS_PORT:-8444}"
BASE="https://${EST_HOST}:${EST_PORT}/.well-known/est"
TRUST="$ART/IssuingCA.cacert.pem"
ESTUSER="$(cat "$ART/est-ra.user")"
ESTPASS="$(cat "$ART/est-ra.pass")"

# /cacerts — RFC 7030 base64 PKCS#7
curl -sk --cacert "$TRUST" -o "$ART/smoke-cacerts.b64" "$BASE/cacerts"
openssl base64 -A -d -in "$ART/smoke-cacerts.b64" -out "$ART/smoke-cacerts.p7"
openssl pkcs7 -inform DER -in "$ART/smoke-cacerts.p7" -print_certs -noout | head -5

# Bad Basic credentials must be rejected
AUTH_CODE="$(curl -sk --cacert "$TRUST" -o /dev/null -w '%{http_code}' \
  --user 'wrong:wrong' -X POST --data 'invalid' \
  -H 'Content-Type: application/pkcs10' \
  "$BASE/simpleenroll")"
if [[ "$AUTH_CODE" != "401" ]]; then
  echo "expected simpleenroll HTTP 401 for bad Basic, got $AUTH_CODE" >&2
  exit 1
fi

openssl req -nodes -newkey rsa:2048 \
  -keyout "$ART/smoke-device.key" \
  -out "$ART/smoke-device.csr" \
  -outform DER \
  -subj '/CN=est-smoke.my.cloud'
openssl base64 -in "$ART/smoke-device.csr" -out "$ART/smoke-device.b64"
chmod 600 "$ART/smoke-device.key"

curl -sk --cacert "$TRUST" --user "$ESTUSER:$ESTPASS" \
  --data @"$ART/smoke-device.b64" \
  -H 'Content-Type: application/pkcs10' \
  -H 'Content-Transfer-Encoding: base64' \
  -o "$ART/smoke-device-p7.b64" \
  "$BASE/simpleenroll"

openssl base64 -A -d -in "$ART/smoke-device-p7.b64" -out "$ART/smoke-device-p7.der"
openssl pkcs7 -inform DER -in "$ART/smoke-device-p7.der" -print_certs -out "$ART/smoke-device-cert.pem"
openssl x509 -in "$ART/smoke-device-cert.pem" -noout -subject -issuer

CODE="$(curl -sk --cacert "$TRUST" -o /dev/null -w '%{http_code}' -X POST "$BASE/simplereenroll")"
if [[ "$CODE" != "501" ]]; then
  echo "expected simplereenroll HTTP 501, got $CODE" >&2
  exit 1
fi

echo "EST smoke OK"
