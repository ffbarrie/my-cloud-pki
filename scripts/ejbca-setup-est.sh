#!/usr/bin/env bash
# Configure EJBCA CMP RA alias and local EST artifacts for the companion EST service.
# Run from my-cloud-pki repo root after the issuing CA is imported.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  echo "Usage: $0 --root bootstrap|hsm" >&2
}

CA_SOURCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      CA_SOURCE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$CA_SOURCE" in
  bootstrap)
    ROOT_CERT="$ROOT/bootstrap/artifacts/bootstrap-root-ca.crt"
    ;;
  hsm)
    ROOT_CERT="$ROOT/offline-ca/root-ca.crt"
    ;;
  *)
    echo "--root must be either bootstrap or hsm." >&2
    usage
    exit 2
    ;;
esac

ART="$ROOT/est/artifacts"
mkdir -p "$ART"
chmod 700 "$ART"

if [[ ! -f "$ROOT_CERT" ]]; then
  echo "Root certificate missing: $ROOT_CERT" >&2
  exit 1
fi

cp "$ROOT_CERT" "$ART/root-ca.crt"

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ca getcacert --caname 'My Cloud Issuing CA' -f /tmp/IssuingCA.cacert.pem"
docker compose cp ejbca:/tmp/IssuingCA.cacert.pem "$ART/IssuingCA.cacert.pem"
docker compose exec -T ejbca bash -c 'rm -f /tmp/IssuingCA.cacert.pem'

if ! openssl verify -CAfile "$ART/root-ca.crt" "$ART/IssuingCA.cacert.pem"; then
  echo "EJBCA's issuing CA is not signed by the selected $CA_SOURCE root." >&2
  exit 1
fi

# A source change requires a listener certificate under the new CA chain.
if [[ ! -f "$ART/ca-source" ]] || [[ "$(cat "$ART/ca-source")" != "$CA_SOURCE" ]]; then
  rm -f "$ART/est-server.crt" "$ART/est-server.key"
fi
printf '%s\n' "$CA_SOURCE" > "$ART/ca-source"

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

if [[ ! -f "$ART/est-server.key" || ! -f "$ART/est-server.crt" ]]; then
  # The issuing private key belongs to EJBCA in HSM Path A. Have EJBCA generate
  # this leaf key pair and certificate in both modes; never use a host CA key.
  # Use MyCloudServerEE (not EMPTY): EMPTY cannot select MyCloudServer.
  EST_SERVER_CN="${EST_SERVER_CN:-est.my.cloud}"
  EST_SERVER_PASS="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-18)"
  CONTAINER_PEM="/opt/keyfactor/p12/pem/${EST_SERVER_CN}.pem"
  LOCAL_PEM="$ART/.est-server-combined.pem"

  printf 'y\n' | docker compose exec -T ejbca bash -lc \
    "/opt/keyfactor/bin/ejbca.sh ra delendentity --username '$EST_SERVER_CN'" \
    2>/dev/null || true
  docker compose exec -T ejbca bash -lc \
    "set -e
     rm -f '$CONTAINER_PEM'
     /opt/keyfactor/bin/ejbca.sh ra addendentity --username '$EST_SERVER_CN' \
       --dn 'CN=$EST_SERVER_CN' --caname 'My Cloud Issuing CA' \
       --certprofile MyCloudServer --eeprofile MyCloudServerEE \
       --type 1 --token PEM --password '$EST_SERVER_PASS'
     /opt/keyfactor/bin/ejbca.sh ra setclearpwd '$EST_SERVER_CN' '$EST_SERVER_PASS'
     /opt/keyfactor/bin/ejbca.sh batch --username '$EST_SERVER_CN'"

  docker compose cp "ejbca:$CONTAINER_PEM" "$LOCAL_PEM"
  openssl pkey -in "$LOCAL_PEM" -out "$ART/est-server.key"
  openssl x509 -in "$LOCAL_PEM" -out "$ART/est-server.crt"
  rm -f "$LOCAL_PEM"
  docker compose exec -T ejbca bash -lc \
    "rm -f '$CONTAINER_PEM'
     printf 'y\n' | /opt/keyfactor/bin/ejbca.sh ra delendentity \
       --username '$EST_SERVER_CN'" >/dev/null
  chmod 600 "$ART/est-server.key" "$ART/est-server.crt"
fi

cat > "$ART/est.env" <<EOF
EST_RA_USER=$(cat "$ART/est-ra.user")
EST_RA_PASS=$(cat "$ART/est-ra.pass")
EJBCA_CMP_SECRET=$(cat "$ART/cmp-ra.pass")
EOF
chmod 600 "$ART/est.env"

echo "EST artifacts ready under est/artifacts/"
echo "  Root mode: $CA_SOURCE ($ROOT_CERT)"
echo "  HTTP Basic (clients -> EST): $(cat "$ART/est-ra.user") / (see est-ra.pass)"
echo "  CMP HMAC (EST -> EJBCA): see cmp-ra.pass"
echo "  Note: Basic RA is lab-only; anyone with the password can request any CN."
