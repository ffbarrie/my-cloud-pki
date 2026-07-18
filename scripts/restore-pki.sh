#!/usr/bin/env bash
# Restore my-cloud-pki from age-encrypted dump + secrets bundle.
# See backups/runbook.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

umask 077

SECRETS_AGE=""
DUMP_AGE=""
IDENTITY="${AGE_IDENTITY:-}"
FORCE=0
SKIP_DB=0
SKIP_SECRETS=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: scripts/restore-pki.sh --secrets FILE.age --dump FILE.age [options]

  --secrets PATH    Age-encrypted secrets tarball (pki-secrets-*.tar.gz.age)
  --dump PATH       Age-encrypted Postgres custom dump (ejbca-*.dump.age)
  --identity PATH   Age identity file (or set AGE_IDENTITY)
  --force           Allow overwriting existing .env / artifacts / postgres data
  --skip-db         Restore secrets only (no pg_restore)
  --skip-secrets    Restore database only (artifacts must already exist)
  --dry-run         Print actions without changing the system
  -h, --help        Show this help

Restores into this checkout. Prefer a drill with alternate COMPOSE_PROJECT_NAME,
ports, and data dir so a live lab is not clobbered.

After restore, the script prints the crypto-token activation and EST smoke checklist.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secrets) SECRETS_AGE="${2:-}"; shift ;;
    --dump) DUMP_AGE="${2:-}"; shift ;;
    --identity) IDENTITY="${2:-}"; shift ;;
    --force) FORCE=1 ;;
    --skip-db) SKIP_DB=1 ;;
    --skip-secrets) SKIP_SECRETS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

need_cmd age
need_cmd docker
need_cmd tar

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

if [[ "$SKIP_SECRETS" -eq 0 && -z "$SECRETS_AGE" ]]; then
  echo "--secrets is required (or pass --skip-secrets)" >&2
  usage >&2
  exit 1
fi
if [[ "$SKIP_DB" -eq 0 && -z "$DUMP_AGE" ]]; then
  echo "--dump is required (or pass --skip-db)" >&2
  usage >&2
  exit 1
fi
if [[ -z "$IDENTITY" ]]; then
  echo "Age identity required: set AGE_IDENTITY or pass --identity" >&2
  exit 1
fi
if [[ ! -f "$IDENTITY" ]]; then
  echo "Identity file not found: $IDENTITY" >&2
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pki-restore.XXXXXX")"
cleanup() {
  if [[ -d "$TMP" ]]; then
    find "$TMP" -type f -exec rm -f {} + 2>/dev/null || true
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

refuse_if_exists() {
  local path="$1"
  if [[ -e "$path" && "$FORCE" -ne 1 ]]; then
    echo "Refusing to overwrite $path (pass --force)" >&2
    exit 1
  fi
}

restore_secrets() {
  echo "Decrypting secrets bundle..."
  if [[ ! -f "$SECRETS_AGE" ]]; then
    echo "Secrets file not found: $SECRETS_AGE" >&2
    exit 1
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] age -d -i $IDENTITY $SECRETS_AGE | tar xz → repo"
    return 0
  fi

  local bundle="$TMP/bundle"
  mkdir -p "$bundle"
  age -d -i "$IDENTITY" -o "$TMP/secrets.tar.gz" "$SECRETS_AGE"
  tar -C "$bundle" -xzf "$TMP/secrets.tar.gz"
  rm -f "$TMP/secrets.tar.gz"

  refuse_if_exists "$ROOT/.env"
  refuse_if_exists "$ROOT/bootstrap/artifacts"
  refuse_if_exists "$ROOT/est/artifacts"

  if [[ -f "$bundle/dotenv" ]]; then
    cp -a "$bundle/dotenv" "$ROOT/.env"
    chmod 600 "$ROOT/.env"
  else
    echo "Bundle missing dotenv (.env)" >&2
    exit 1
  fi
  if [[ -d "$bundle/bootstrap/artifacts" ]]; then
    mkdir -p "$ROOT/bootstrap"
    rm -rf "$ROOT/bootstrap/artifacts"
    cp -a "$bundle/bootstrap/artifacts" "$ROOT/bootstrap/artifacts"
    chmod 700 "$ROOT/bootstrap/artifacts" 2>/dev/null || true
  else
    echo "Bundle missing bootstrap/artifacts" >&2
    exit 1
  fi
  if [[ -d "$bundle/est/artifacts" ]]; then
    mkdir -p "$ROOT/est"
    rm -rf "$ROOT/est/artifacts"
    cp -a "$bundle/est/artifacts" "$ROOT/est/artifacts"
    chmod 700 "$ROOT/est/artifacts" 2>/dev/null || true
  fi
  if [[ -f "$bundle/backups-private/superadmin.p12" ]]; then
    mkdir -p "$ROOT/backups/private"
    cp -a "$bundle/backups-private/superadmin.p12" "$ROOT/backups/private/superadmin.p12"
    chmod 600 "$ROOT/backups/private/superadmin.p12"
    echo "Restored SuperAdmin P12 to backups/private/superadmin.p12"
  fi
  echo "Secrets restored (.env, bootstrap/artifacts, est/artifacts)."
}

load_env() {
  if [[ -f "$ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source "$ROOT/.env"
    set +a
  fi
  EJBCA_DB_NAME="${EJBCA_DB_NAME:-ejbca}"
  EJBCA_DB_USER="${EJBCA_DB_USER:-ejbca}"
}

restore_db() {
  echo "Restoring Postgres from encrypted dump..."
  if [[ ! -f "$DUMP_AGE" ]]; then
    echo "Dump file not found: $DUMP_AGE" >&2
    exit 1
  fi
  load_env

  local pgdata="$ROOT/issuing-ca/data/postgres"
  if [[ -d "$pgdata" && -n "$(ls -A "$pgdata" 2>/dev/null || true)" && "$FORCE" -ne 1 ]]; then
    echo "Refusing to restore into non-empty $pgdata (pass --force)" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] stop ejbca/est; start ejbca-database; DROP/CREATE $EJBCA_DB_NAME; pg_restore"
    return 0
  fi

  age -d -i "$IDENTITY" -o "$TMP/ejbca.dump" "$DUMP_AGE"
  chmod 600 "$TMP/ejbca.dump"

  # Stop app containers; keep/start database only
  docker compose stop ejbca est 2>/dev/null || true
  mkdir -p "$ROOT/issuing-ca/data/postgres"
  docker compose up -d ejbca-database

  echo "Waiting for Postgres..."
  local i=0
  while [[ "$i" -lt 60 ]]; do
    i=$((i + 1))
    if docker compose exec -T ejbca-database \
      pg_isready -U "$EJBCA_DB_USER" -d postgres >/dev/null 2>&1; then
      break
    fi
    sleep 1
    if [[ "$i" -eq 60 ]]; then
      echo "Postgres did not become ready" >&2
      exit 1
    fi
  done

  # Terminate connections and recreate database
  docker compose exec -T ejbca-database \
    psql -U "$EJBCA_DB_USER" -d postgres -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${EJBCA_DB_NAME}' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS ${EJBCA_DB_NAME};
CREATE DATABASE ${EJBCA_DB_NAME} OWNER ${EJBCA_DB_USER};
SQL

  docker compose exec -T ejbca-database \
    pg_restore -U "$EJBCA_DB_USER" -d "$EJBCA_DB_NAME" --exit-on-error \
    <"$TMP/ejbca.dump"

  rm -f "$TMP/ejbca.dump"
  echo "pg_restore completed."
}

print_checklist() {
  cat <<'EOF'

=== Post-restore checklist ===

1. Start EJBCA (database should already be up):
     docker compose up -d ejbca

2. Wait until EJBCA is healthy, then activate the imported crypto token:
     KSPASS=$(cat bootstrap/artifacts/issuing-ca.p12.pass)
     TOKEN=$(docker compose exec -T ejbca bash -lc \
       "/opt/keyfactor/bin/ejbca.sh cryptotoken list" | awk -F'"' '/Imported/{print $2}')
     docker compose exec -T ejbca bash -lc \
       "/opt/keyfactor/bin/ejbca.sh cryptotoken activate --token '$TOKEN' --pin '$KSPASS'"

3. Start EST:
     docker compose up -d est

4. Smoke test:
     ./scripts/est-smoke.sh

5. If EJBCA_TLS_SETUP_ENABLED=true, import SuperAdmin P12 into the browser
   (from backups/private/superadmin.p12 if restored).

6. Confirm health:
     curl -s http://localhost:8080/ejbca/publicweb/healthcheck/ejbcahealth

See backups/runbook.md for disaster scenarios A/B/C and cold USB notes.
EOF
}

# --- main ---
if [[ "$SKIP_SECRETS" -eq 0 ]]; then
  restore_secrets
fi
if [[ "$SKIP_DB" -eq 0 ]]; then
  restore_db
fi

print_checklist
echo "Restore steps finished (see checklist above)."
