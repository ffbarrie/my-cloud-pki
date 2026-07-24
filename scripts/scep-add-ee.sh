#!/usr/bin/env bash
# Pre-register an end entity for EJBCA CE SCEP CA/Client mode enrollment.
# Username must equal the CN in the client's PKCS#10; challengePassword must match.
#
# Usage: ./scripts/scep-add-ee.sh <cn> [challenge]
#   challenge defaults to scep/artifacts/scep-challenge.pass
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <cn> [challenge]" >&2
  exit 1
fi

CN="$1"
ART="$ROOT/scep/artifacts"
CANAME="${SCEP_CA_NAME:-My Cloud Issuing CA}"

if [[ $# -eq 2 ]]; then
  CHAL="$2"
else
  if [[ ! -f "$ART/scep-challenge.pass" ]]; then
    echo "Missing $ART/scep-challenge.pass; run ./scripts/ejbca-setup-scep.sh first." >&2
    exit 1
  fi
  CHAL="$(cat "$ART/scep-challenge.pass")"
fi

# Revoke/delete if present so re-runs are idempotent for lab use.
printf 'y\n' | docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ra revokeendentity --username '$CN' -r 4" 2>/dev/null || true
printf 'y\n' | docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ra delendentity --username '$CN'" 2>/dev/null || true

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ra addendentity --username '$CN' \
    --dn 'CN=$CN' --caname '$CANAME' \
    --certprofile MyCloudServer --eeprofile MyCloudServerEE \
    --type 1 --token USERGENERATED --password '$CHAL'"

docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ra setclearpwd '$CN' '$CHAL'"

echo "End entity ready for SCEP:"
echo "  username (must = CSR CN): $CN"
echo "  challengePassword:        (supplied / scep-challenge.pass)"
echo "  profiles:                 MyCloudServer / MyCloudServerEE"
