#!/usr/bin/env bash
# Smoke-test native EJBCA CE SCEP (CA/Client mode): GetCACaps, GetCACert, PKCSReq enroll.
# Full enroll requires sscep on PATH (or SSCEP=/path/to/sscep). Caps/CACert always run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART="$ROOT/scep/artifacts"
ALIAS="${SCEP_ALIAS:-mycloud}"
CANAME="${SCEP_CA_NAME:-My Cloud Issuing CA}"
SCEP_HOST="${SCEP_HOST:-localhost}"
SCEP_PORT="${EJBCA_HTTP_PORT:-8080}"
URL="http://${SCEP_HOST}:${SCEP_PORT}/ejbca/publicweb/apply/scep/${ALIAS}/pkiclient.exe"
CN="${SCEP_SMOKE_CN:-scep-smoke.my.cloud}"

if [[ ! -f "$ART/scep-challenge.pass" ]]; then
  echo "Missing $ART/scep-challenge.pass; run ./scripts/ejbca-setup-scep.sh first." >&2
  exit 1
fi
CHAL="$(cat "$ART/scep-challenge.pass")"
CA_MSG="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$CANAME")"

# GetCACaps
CAPS="$(curl -sS "$URL?operation=GetCACaps")"
echo "$CAPS" | head -20
echo "$CAPS" | grep -q 'POSTPKIOperation' || {
  echo "GetCACaps missing POSTPKIOperation" >&2
  exit 1
}

# GetCACert — must URL-encode CA name (sscep -i with spaces sends a bare space → HTTP 400)
curl -sS -o "$ART/smoke-ca.der" "$URL?operation=GetCACert&message=${CA_MSG}"
openssl x509 -inform DER -in "$ART/smoke-ca.der" -out "$ART/smoke-ca.crt"
openssl x509 -in "$ART/smoke-ca.crt" -noout -subject -issuer

SSCEP_BIN="${SSCEP:-}"
if [[ -z "$SSCEP_BIN" ]] && command -v sscep >/dev/null 2>&1; then
  SSCEP_BIN="$(command -v sscep)"
fi

if [[ -z "$SSCEP_BIN" ]]; then
  echo "SCEP GetCACaps/GetCACert OK (install sscep and re-run for PKCSReq enroll smoke)"
  echo "  hint: build https://github.com/certnanny/sscep and export SSCEP=/path/to/sscep"
  exit 0
fi

./scripts/scep-add-ee.sh "$CN" "$CHAL"

cat > "$ART/smoke-req.cnf" <<EOF
[req]
distinguished_name = dn
attributes = req_attrs
prompt = no
[dn]
CN = $CN
[req_attrs]
challengePassword = $CHAL
EOF

openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$ART/smoke-device.key" \
  -out "$ART/smoke-device.csr" \
  -config "$ART/smoke-req.cnf"
chmod 600 "$ART/smoke-device.key"

# Do not pass -i with spaces; provide CA cert via -c instead.
"$SSCEP_BIN" enroll -u "$URL" \
  -c "$ART/smoke-ca.crt" \
  -k "$ART/smoke-device.key" \
  -r "$ART/smoke-device.csr" \
  -l "$ART/smoke-device.crt" \
  -E aes -S sha256

openssl x509 -in "$ART/smoke-device.crt" -noout -subject -issuer
SUBJ="$(openssl x509 -in "$ART/smoke-device.crt" -noout -subject)"
echo "$SUBJ" | grep -q "$CN" || {
  echo "enrolled cert subject mismatch: $SUBJ" >&2
  exit 1
}

echo "SCEP smoke OK"
