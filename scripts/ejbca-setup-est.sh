#!/usr/bin/env bash
# Configure EJBCA CMP RA alias and local EST artifacts for the companion EST service.
# Run from my-cloud-pki repo root after the issuing CA is imported.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART="$ROOT/est/artifacts"
mkdir -p "$ART"
chmod 700 "$ART"

if [[ ! -f bootstrap/artifacts/issuing-ca.crt ]]; then
  echo "bootstrap/artifacts/issuing-ca.crt missing; run bootstrap software root first." >&2
  exit 1
fi

cp bootstrap/artifacts/bootstrap-root-ca.crt "$ART/"
cp bootstrap/artifacts/issuing-ca.crt "$ART/IssuingCA.cacert.pem"

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ca getcacert --caname 'My Cloud Issuing CA' -f /tmp/IssuingCA.cacert.pem"
docker compose cp ejbca:/tmp/IssuingCA.cacert.pem "$ART/IssuingCA.cacert.pem"

if [[ ! -f "$ART/est-ra.user" ]]; then
  echo "estra" > "$ART/est-ra.user"
fi
if [[ ! -f "$ART/est-ra.pass" ]]; then
  openssl rand -base64 18 | tr -d '/+=' | cut -c1-18 > "$ART/est-ra.pass"
fi
if [[ ! -f "$ART/cmp-ra.pass" ]]; then
  openssl rand -base64 18 | tr -d '/+=' | cut -c1-18 > "$ART/cmp-ra.pass"
fi
chmod 600 "$ART/est-ra.user" "$ART/est-ra.pass" "$ART/cmp-ra.pass"

CMPPASS="$(cat "$ART/cmp-ra.pass")"

# Resolve MyCloudServerEE numeric id from EJBCA (do not hardcode).
# Match "<digits> (MyCloudServerEE)" explicitly — avoid greedy sed eating into the id.
EEPROFILE_ID="$(
  docker compose exec -T ejbca bash -lc \
    "/opt/keyfactor/bin/ejbca.sh config cmp updatealias --help" 2>&1 \
    | grep -oE '[0-9]+ \(MyCloudServerEE\)' \
    | awk '{print $1}' \
    | head -1
)"
if [[ -z "$EEPROFILE_ID" || "$EEPROFILE_ID" == "1" ]]; then
  echo "MyCloudServerEE profile not found in EJBCA; import issuing-ca/profiles first." >&2
  exit 1
fi
echo "Using end entity profile MyCloudServerEE id=$EEPROFILE_ID"

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh config cmp addalias --alias mycloud" 2>/dev/null || true

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key operationmode --value ra
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key defaultca --value 'My Cloud Issuing CA'
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key ra.caname --value 'My Cloud Issuing CA'
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key ra.certificateprofile --value MyCloudServer
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key ra.endentityprofileid --value '$EEPROFILE_ID'
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key ra.namegenerationscheme --value DN
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key ra.namegenerationparameters --value CN
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key authenticationmodule --value HMAC
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key authenticationparameters --value '$CMPPASS'
   /opt/keyfactor/bin/ejbca.sh config cmp updatealias --alias mycloud --key responseprotection --value pbe"

if [[ ! -f "$ART/est-server.key" ]]; then
  openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$ART/est-server.key" \
    -out "$ART/est-server.csr" \
    -subj "/CN=est.my.cloud"
  openssl x509 -req -in "$ART/est-server.csr" \
    -CA bootstrap/artifacts/issuing-ca.crt \
    -CAkey bootstrap/artifacts/issuing-ca.key \
    -CAcreateserial \
    -out "$ART/est-server.crt" \
    -days 825 -sha256
  rm -f "$ART/est-server.csr"
  chmod 600 "$ART/est-server.key" "$ART/est-server.crt"
fi

cat > "$ART/est.env" <<EOF
EST_RA_USER=$(cat "$ART/est-ra.user")
EST_RA_PASS=$(cat "$ART/est-ra.pass")
EJBCA_CMP_SECRET=$(cat "$ART/cmp-ra.pass")
EOF
chmod 600 "$ART/est.env"

echo "EST artifacts ready under est/artifacts/"
echo "  HTTP Basic (clients -> EST): $(cat "$ART/est-ra.user") / (see est-ra.pass)"
echo "  CMP HMAC (EST -> EJBCA): see cmp-ra.pass"
echo "  Note: Basic RA is lab-only; anyone with the password can request any CN."
