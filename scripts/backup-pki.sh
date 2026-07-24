#!/usr/bin/env bash
# Backup my-cloud-pki: age-encrypted Postgres dump + secrets bundle, append-only rsync.
# See backups/runbook.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

umask 077

DRY_RUN=0
NO_RSYNC=0
PRUNE=0
DB_ONLY=0
SECRETS_ONLY=0
DO_DB=1
DO_SECRETS=1

usage() {
  cat <<'EOF'
Usage: scripts/backup-pki.sh [options]

  --dry-run       Print actions without writing or rsyncing
  --no-rsync      Skip NAS rsync (local staging only)
  --prune         After backup, prune remote dumps/secrets/manifests to KEEP_* counts
  --db-only       Encrypted Postgres dump only
  --secrets-only  Encrypted secrets bundle only
  -h, --help      Show this help

Config: backups/config.env (from backups/config.example.env)
Requires: age, docker compose; rsync+ssh unless --no-rsync
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-rsync) NO_RSYNC=1 ;;
    --prune) PRUNE=1 ;;
    --db-only) DB_ONLY=1; DO_SECRETS=0 ;;
    --secrets-only) SECRETS_ONLY=1; DO_DB=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [[ "$DB_ONLY" -eq 1 && "$SECRETS_ONLY" -eq 1 ]]; then
  echo "Use only one of --db-only or --secrets-only" >&2
  exit 1
fi

CONFIG_FILE="${BACKUP_CONFIG:-$ROOT/backups/config.env}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  # shellcheck disable=SC1091
  source "$CONFIG_FILE"
  set +a
fi

AGE_RECIPIENT_FILE="${AGE_RECIPIENT_FILE:-backups/age-recipient.txt}"
# Resolve relative to ROOT
if [[ "$AGE_RECIPIENT_FILE" != /* ]]; then
  AGE_RECIPIENT_FILE="$ROOT/$AGE_RECIPIENT_FILE"
fi

NAS_USER="${NAS_USER:-}"
NAS_HOST="${NAS_HOST:-}"
NAS_PATH="${NAS_PATH:-}"
KEEP_DUMPS="${KEEP_DUMPS:-8}"
KEEP_SECRETS="${KEEP_SECRETS:-5}"
KEEP_MANIFESTS="${KEEP_MANIFESTS:-8}"
CLEAR_STAGING_AFTER_RSYNC="${CLEAR_STAGING_AFTER_RSYNC:-0}"

STAGING="$ROOT/backups/staging"
DUMP_DIR="$STAGING/dumps"
SECRETS_DIR="$STAGING/secrets"
MANIFEST_DIR="$STAGING/manifests"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

need_cmd age
need_cmd docker
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "Required command not found: sha256sum or shasum" >&2
  exit 1
fi

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
    return 0
  fi
  "$@"
}

ensure_staging() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] mkdir -p $DUMP_DIR $SECRETS_DIR $MANIFEST_DIR (mode 700)"
    return 0
  fi
  mkdir -p "$DUMP_DIR" "$SECRETS_DIR" "$MANIFEST_DIR"
  chmod 700 "$STAGING" "$DUMP_DIR" "$SECRETS_DIR" "$MANIFEST_DIR"
  # Refuse world-readable staging
  local mode
  mode="$(stat -f '%Lp' "$STAGING" 2>/dev/null || stat -c '%a' "$STAGING")"
  if [[ "$mode" != "700" ]]; then
    echo "backups/staging must be mode 700 (got $mode)" >&2
    exit 1
  fi
}

require_recipient() {
  if [[ ! -f "$AGE_RECIPIENT_FILE" ]]; then
    echo "Age recipient file missing: $AGE_RECIPIENT_FILE" >&2
    echo "See backups/runbook.md (age key custody)." >&2
    exit 1
  fi
  if ! grep -qE '^age1' "$AGE_RECIPIENT_FILE"; then
    echo "No age1... recipient line in $AGE_RECIPIENT_FILE" >&2
    exit 1
  fi
}

nas_dest() {
  if [[ -z "$NAS_HOST" || -z "$NAS_PATH" ]]; then
    return 1
  fi
  local user_part=""
  if [[ -n "$NAS_USER" ]]; then
    user_part="${NAS_USER}@"
  fi
  echo "${user_part}${NAS_HOST}:${NAS_PATH}"
}

TS="$(date +%Y%m%d-%H%M%S)"
DUMP_NAME="ejbca-${TS}.dump.age"
SECRETS_NAME="pki-secrets-${TS}.tar.gz.age"
MANIFEST_NAME="manifest-${TS}.json"

DUMP_PATH="$DUMP_DIR/$DUMP_NAME"
SECRETS_PATH="$SECRETS_DIR/$SECRETS_NAME"
MANIFEST_PATH="$MANIFEST_DIR/$MANIFEST_NAME"

backup_db() {
  require_recipient
  echo "Creating encrypted Postgres dump → $DUMP_PATH"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] docker compose exec -T ejbca-database pg_dump ... | age -R ... > $DUMP_PATH"
    return 0
  fi
  if ! docker compose ps --status running --services 2>/dev/null | grep -qx 'ejbca-database'; then
    echo "ejbca-database is not running; start it with: docker compose up -d ejbca-database" >&2
    exit 1
  fi
  # Load DB name/user from .env if present
  local db_name="${EJBCA_DB_NAME:-ejbca}"
  local db_user="${EJBCA_DB_USER:-ejbca}"
  if [[ -f "$ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source "$ROOT/.env"
    set +a
    db_name="${EJBCA_DB_NAME:-ejbca}"
    db_user="${EJBCA_DB_USER:-ejbca}"
  fi
  docker compose exec -T ejbca-database \
    pg_dump -U "$db_user" -Fc "$db_name" \
    | age -R "$AGE_RECIPIENT_FILE" \
    >"$DUMP_PATH"
  chmod 600 "$DUMP_PATH"
}

backup_secrets() {
  require_recipient
  echo "Creating encrypted secrets bundle → $SECRETS_PATH"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] tar + age → $SECRETS_PATH"
    return 0
  fi
  if [[ ! -d "$ROOT/bootstrap/artifacts" ]]; then
    echo "bootstrap/artifacts missing" >&2
    exit 1
  fi
  if [[ ! -f "$ROOT/.env" ]]; then
    echo ".env missing at repo root" >&2
    exit 1
  fi

  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/pki-secrets.XXXXXX")"
  cleanup_tmp() { rm -rf "$tmp"; }
  trap cleanup_tmp EXIT

  mkdir -p "$tmp/bundle/bootstrap" "$tmp/bundle/est/artifacts" \
    "$tmp/bundle/scep/artifacts" "$tmp/bundle/backups-private"
  cp -a "$ROOT/bootstrap/artifacts" "$tmp/bundle/bootstrap/"
  if [[ -d "$ROOT/est/artifacts" ]]; then
    # Copy EST artifacts but exclude regenerable smoke / device scratch
    tar -C "$ROOT/est/artifacts" -cf - \
      --exclude='device.key' \
      --exclude='device.b64' \
      --exclude='device-p7.b64' \
      --exclude='smoke-*' \
      --exclude='cacerts.p7' \
      . | tar -C "$tmp/bundle/est/artifacts" -xf -
  fi
  if [[ -d "$ROOT/scep/artifacts" ]]; then
    tar -C "$ROOT/scep/artifacts" -cf - \
      --exclude='smoke-*' \
      --exclude='device.*' \
      . | tar -C "$tmp/bundle/scep/artifacts" -xf -
  fi
  cp -a "$ROOT/.env" "$tmp/bundle/dotenv"
  if [[ -f "$ROOT/backups/private/superadmin.p12" ]]; then
    cp -a "$ROOT/backups/private/superadmin.p12" "$tmp/bundle/backups-private/superadmin.p12"
  fi

  tar -C "$tmp/bundle" -czf - . \
    | age -R "$AGE_RECIPIENT_FILE" \
    >"$SECRETS_PATH"
  chmod 600 "$SECRETS_PATH"

  trap - EXIT
  cleanup_tmp
}

git_rev() {
  git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "unknown"
}

ejbca_image_info() {
  local tag="${EJBCA_IMAGE_TAG:-latest}"
  if [[ -f "$ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source "$ROOT/.env"
    set +a
    tag="${EJBCA_IMAGE_TAG:-latest}"
  fi
  local digest=""
  if docker image inspect "keyfactor/ejbca-ce:${tag}" >/dev/null 2>&1; then
    digest="$(docker image inspect "keyfactor/ejbca-ce:${tag}" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
  fi
  echo "$tag|$digest"
}

postgres_version() {
  if docker compose ps --status running --services 2>/dev/null | grep -qx 'ejbca-database'; then
    docker compose exec -T ejbca-database psql -U "${EJBCA_DB_USER:-ejbca}" -d "${EJBCA_DB_NAME:-ejbca}" -tAc 'SHOW server_version;' 2>/dev/null | tr -d '[:space:]' || echo "unknown"
  else
    echo "unknown"
  fi
}

write_manifest() {
  local dump_sha="" secrets_sha="" img_info img_tag img_digest dump_file secrets_file
  img_info="$(ejbca_image_info)"
  img_tag="${img_info%%|*}"
  img_digest="${img_info#*|}"
  dump_file=""
  secrets_file=""
  if [[ "$DO_DB" -eq 1 ]]; then
    dump_file="$DUMP_NAME"
  fi
  if [[ "$DO_SECRETS" -eq 1 ]]; then
    secrets_file="$SECRETS_NAME"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] write manifest $MANIFEST_PATH"
    return 0
  fi

  if [[ -f "$DUMP_PATH" ]]; then
    dump_sha="$(sha256_file "$DUMP_PATH")"
  fi
  if [[ -f "$SECRETS_PATH" ]]; then
    secrets_sha="$(sha256_file "$SECRETS_PATH")"
  fi

  cat >"$MANIFEST_PATH" <<EOF
{
  "timestamp": "${TS}",
  "git_rev": "$(git_rev)",
  "postgres_version": "$(postgres_version)",
  "ejbca_image_tag": "${img_tag}",
  "ejbca_image_digest": "${img_digest}",
  "dump_file": "${dump_file}",
  "dump_sha256": "${dump_sha}",
  "secrets_file": "${secrets_file}",
  "secrets_sha256": "${secrets_sha}"
}
EOF
  chmod 644 "$MANIFEST_PATH"
  echo "Wrote manifest $MANIFEST_PATH"
}

# Args: ssh_target remote_file
remote_sha256() {
  local ssh_target="$1"
  local remote_file="$2"
  ssh "$ssh_target" "if command -v sha256sum >/dev/null 2>&1; then sha256sum '$remote_file'; else shasum -a 256 '$remote_file'; fi" | awk '{print $1}'
}

# Args: ssh_target remote_path subdir keep pattern
prune_remote_dir() {
  local ssh_target="$1"
  local remote_path="$2"
  local subdir="$3"
  local keep="$4"
  local pattern="$5"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] prune ${remote_path}/${subdir} keep $keep pattern $pattern"
    return 0
  fi
  ssh "$ssh_target" "cd '${remote_path}/${subdir}' 2>/dev/null || exit 0; ls -1 ${pattern} 2>/dev/null | sort -r | tail -n +$((keep + 1)) | while IFS= read -r f; do rm -f -- \"\$f\"; echo \"Removed ${subdir}/\$f\"; done"
}

rsync_to_nas() {
  if [[ "$NO_RSYNC" -eq 1 ]]; then
    echo "Skipping rsync (--no-rsync)"
    return 0
  fi
  local dest ssh_target remote_path local_sha remote_sha
  if ! dest="$(nas_dest)"; then
    echo "NAS_HOST/NAS_PATH not set; skipping rsync (use backups/config.env or --no-rsync)" >&2
    return 0
  fi
  need_cmd rsync
  echo "Append-only rsync → ${dest}"
  ssh_target="${dest%%:*}"
  remote_path="${dest#*:}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] ssh $ssh_target mkdir -p ${remote_path}/dumps ${remote_path}/secrets ${remote_path}/manifests"
    echo "[dry-run] rsync -av $DUMP_DIR/ ${dest}/dumps/"
    echo "[dry-run] rsync -av $SECRETS_DIR/ ${dest}/secrets/"
    echo "[dry-run] rsync -av $MANIFEST_DIR/ ${dest}/manifests/"
    return 0
  fi
  ssh "$ssh_target" "mkdir -p '${remote_path}/dumps' '${remote_path}/secrets' '${remote_path}/manifests'"
  if [[ "$DO_DB" -eq 1 && -f "$DUMP_PATH" ]]; then
    rsync -av "$DUMP_DIR/" "${dest}/dumps/"
  fi
  if [[ "$DO_SECRETS" -eq 1 && -f "$SECRETS_PATH" ]]; then
    rsync -av "$SECRETS_DIR/" "${dest}/secrets/"
  fi
  if [[ -f "$MANIFEST_PATH" ]]; then
    rsync -av "$MANIFEST_DIR/" "${dest}/manifests/"
  fi

  if [[ "$DO_DB" -eq 1 && -f "$DUMP_PATH" ]]; then
    local_sha="$(sha256_file "$DUMP_PATH")"
    remote_sha="$(remote_sha256 "$ssh_target" "${remote_path}/dumps/${DUMP_NAME}")"
    if [[ "$local_sha" != "$remote_sha" ]]; then
      echo "Checksum mismatch for dump on NAS (local=$local_sha remote=$remote_sha)" >&2
      exit 1
    fi
    echo "Verified dump sha256 on NAS: $local_sha"
  fi
  if [[ "$DO_SECRETS" -eq 1 && -f "$SECRETS_PATH" ]]; then
    local_sha="$(sha256_file "$SECRETS_PATH")"
    remote_sha="$(remote_sha256 "$ssh_target" "${remote_path}/secrets/${SECRETS_NAME}")"
    if [[ "$local_sha" != "$remote_sha" ]]; then
      echo "Checksum mismatch for secrets on NAS (local=$local_sha remote=$remote_sha)" >&2
      exit 1
    fi
    echo "Verified secrets sha256 on NAS: $local_sha"
  fi

  if [[ "$CLEAR_STAGING_AFTER_RSYNC" == "1" ]]; then
    echo "Clearing staging ciphertext (CLEAR_STAGING_AFTER_RSYNC=1)"
    rm -f "$DUMP_PATH" "$SECRETS_PATH"
  fi
}

prune_remote() {
  local dest ssh_target remote_path
  if ! dest="$(nas_dest)"; then
    echo "Cannot prune: NAS_HOST/NAS_PATH not set" >&2
    return 1
  fi
  ssh_target="${dest%%:*}"
  remote_path="${dest#*:}"
  echo "Pruning remote keep dumps=$KEEP_DUMPS secrets=$KEEP_SECRETS manifests=$KEEP_MANIFESTS"
  prune_remote_dir "$ssh_target" "$remote_path" dumps "$KEEP_DUMPS" 'ejbca-*.dump.age'
  prune_remote_dir "$ssh_target" "$remote_path" secrets "$KEEP_SECRETS" 'pki-secrets-*.tar.gz.age'
  prune_remote_dir "$ssh_target" "$remote_path" manifests "$KEEP_MANIFESTS" 'manifest-*.json'
}

# --- main ---
ensure_staging

DID_WORK=0
if [[ "$DO_DB" -eq 1 ]]; then
  backup_db
  DID_WORK=1
fi
if [[ "$DO_SECRETS" -eq 1 ]]; then
  backup_secrets
  DID_WORK=1
fi

if [[ "$DID_WORK" -eq 1 ]]; then
  write_manifest
  rsync_to_nas
fi

if [[ "$PRUNE" -eq 1 ]]; then
  if [[ "$NO_RSYNC" -eq 1 ]]; then
    echo "Ignoring --prune with --no-rsync" >&2
  else
    prune_remote
  fi
fi

echo "Backup complete (${TS}). Reminder: copy newest secrets .age to offline USB after secrets changes."
if [[ "$DO_SECRETS" -eq 1 ]]; then
  echo "Cold USB: copy $SECRETS_PATH (and keep age identity separately)."
fi
