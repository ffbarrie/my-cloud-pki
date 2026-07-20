#!/usr/bin/env bash
# Configure native EJBCA CE SCEP alias (CA / Client mode) and local challenge secret.
# Run from my-cloud-pki repo root after the issuing CA and TLS profiles exist.
#
# CE note: SCEP RA mode can be set in the CLI but enrollment is rejected at runtime
# ("not included in the community version"). This lab uses CA mode only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART="$ROOT/scep/artifacts"
ALIAS="${SCEP_ALIAS:-mycloud}"
CANAME="${SCEP_CA_NAME:-My Cloud Issuing CA}"

mkdir -p "$ART"
chmod 700 "$ART"

if [[ ! -f bootstrap/artifacts/issuing-ca.crt ]]; then
  echo "bootstrap/artifacts/issuing-ca.crt missing; run bootstrap software root first." >&2
  exit 1
fi

cp bootstrap/artifacts/bootstrap-root-ca.crt "$ART/"
cp bootstrap/artifacts/issuing-ca.crt "$ART/IssuingCA.cacert.pem"

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ca getcacert --caname '$CANAME' -f /tmp/IssuingCA.cacert.pem"
docker compose cp ejbca:/tmp/IssuingCA.cacert.pem "$ART/IssuingCA.cacert.pem"

if [[ ! -f "$ART/scep-challenge.pass" ]]; then
  # Avoid characters that break some SCEP clients / shell quoting.
  openssl rand -base64 18 | tr -d '/+=' | cut -c1-18 > "$ART/scep-challenge.pass"
fi
chmod 600 "$ART/scep-challenge.pass"

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh config scep addalias --alias '$ALIAS'" 2>/dev/null || true

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh config scep updatealias --alias '$ALIAS' --key operationmode --value ca
   /opt/keyfactor/bin/ejbca.sh config scep updatealias --alias '$ALIAS' --key includeca --value true
   /opt/keyfactor/bin/ejbca.sh config scep updatealias --alias '$ALIAS' --key returnCaChainInGetCaCert --value false"

# Fetch DER CA cert for clients that need a local encrypt-to cert (classic GetCACert).
SCEP_PORT="${EJBCA_HTTP_PORT:-8080}"
SCEP_HOST="${SCEP_HOST:-localhost}"
CA_MSG="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$CANAME")"
curl -sS -o "$ART/ca.der" \
  "http://${SCEP_HOST}:${SCEP_PORT}/ejbca/publicweb/apply/scep/${ALIAS}/pkiclient.exe?operation=GetCACert&message=${CA_MSG}"
openssl x509 -inform DER -in "$ART/ca.der" -out "$ART/ca.crt"
chmod 644 "$ART/ca.crt" "$ART/ca.der"

cat > "$ART/client.env" <<EOF
SCEP_URL=http://${SCEP_HOST}:${SCEP_PORT}/ejbca/publicweb/apply/scep/${ALIAS}/pkiclient.exe
SCEP_ALIAS=${ALIAS}
SCEP_CA_NAME=${CANAME}
SCEP_CHALLENGE=$(cat "$ART/scep-challenge.pass")
EOF
chmod 600 "$ART/client.env"

echo "SCEP (CE CA/Client mode) ready under scep/artifacts/"
echo "  Alias:     $ALIAS"
echo "  URL:       http://${SCEP_HOST}:${SCEP_PORT}/ejbca/publicweb/apply/scep/${ALIAS}/pkiclient.exe"
echo "  CA name:   $CANAME  (use URL-encoded as GetCACert message=)"
echo "  Challenge: see scep/artifacts/scep-challenge.pass"
echo "  Next:      ./scripts/scep-add-ee.sh <cn>   then enroll with your SCEP client"
echo "  Note:      SCEP RA mode is Enterprise-only; CE rejects PKCSReq when operationmode=ra."
