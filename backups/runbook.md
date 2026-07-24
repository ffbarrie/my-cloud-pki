# Backup and restore runbook

Operational procedures for backing up and restoring My Cloud PKI online state.
Tooling lives in [`../scripts/backup-pki.sh`](../scripts/backup-pki.sh) and
[`../scripts/restore-pki.sh`](../scripts/restore-pki.sh). Configuration example:
[`config.example.env`](config.example.env).

Do not commit private keys, age identity keys, database dumps, SuperAdmin P12
files, or credentials under `backups/`. Staging and local config are gitignored.

Online CA state lives in PostgreSQL
([ADR-0005](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0005-postgresql-datastore.md)).
The offline root path is HSM-backed later
([ADR-0001](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0001-nitrokey-hsm2-offline-ca.md));
until then the bootstrap software root key is P0 and needs a cold USB copy.

## Prerequisites

- Docker Engine with Compose v2, stack from the repo root (`compose.yaml`)
- Bash (scripts use `#!/usr/bin/env bash`; not POSIX `sh` / dash)
- [`age`](https://github.com/FiloSottile/age) and `age-keygen` on the PATH
- `rsync` and SSH access to the NAS (or use `--no-rsync`)
- `backups/config.env` copied from `config.example.env` and filled in
- `backups/age-recipient.txt` containing the **public** recipient line only

### Host OS: Linux and macOS

Backup/restore scripts are written for **Linux and macOS**. They do not assume
Homebrew paths or macOS-only tools.

| Need | Linux | macOS |
|------|-------|-------|
| `age` / `age-keygen` | Distro package or [upstream releases](https://github.com/FiloSottile/age/releases) (e.g. Debian/Ubuntu: `age` in newer releases; otherwise download the Linux amd64/arm64 tarball). Fedora: `sudo dnf install age`. | `brew install age` |
| Checksums | `sha256sum` (coreutils; usual default) | `shasum` (preinstalled); script falls back automatically |
| `stat` mode check | GNU `stat -c '%a'` | BSD `stat -f '%Lp'`; script tries BSD then GNU |
| `tar` / `rsync` / `ssh` | Usual distro packages (`tar`, `rsync`, OpenSSH client) | Preinstalled or Xcode CLT / brew |
| Shell | `bash` (install if you only have dash as `/bin/sh`) | `/bin/bash` is fine; newer bash via brew is optional |

**NAS side:** most Linux NAS appliances provide `sha256sum`. Remote prune/verify
commands prefer `sha256sum` and fall back to `shasum` if needed.

**Not tested / out of scope:** Windows hosts (use WSL2 with the Linux column, or
run backups from a Linux/macOS machine that can reach Docker and the repo).

## Backup tiers

| Tier | Asset | Location | Method |
|------|-------|----------|--------|
| P0 | Issuing CA key, P12, activation PIN | `bootstrap/artifacts/issuing-ca.{key,p12,p12.pass}` | Age secrets bundle + offline USB |
| P0 | Bootstrap root key (pre-HSM) | `bootstrap/artifacts/bootstrap-root-ca.key` | Age secrets bundle + **offline USB** |
| P0 | EJBCA Postgres | logical dump of `ejbca` | `pg_dump -Fc` → age → NAS |
| P0 | SuperAdmin client P12 | Browser/OS (not in repo) | Manual export into secrets bundle |
| P0 | Age identity key | Off-host only | Password manager + encrypted USB |
| P1 | EST + CMP secrets | `est/artifacts/` (excl. smoke scratch) | Age secrets bundle |
| P1 | SCEP challenge + client env | `scep/artifacts/` (excl. smoke scratch) | Age secrets bundle |
| P1 | Compose `.env` | repo root `.env` | Age secrets bundle |
| P2 | Profiles, compose, scripts | Git | Git is source of truth |
| Future P0 | Nitrokey HSM A + B | Physical | Device custody (not file backup) |

Do not back up regenerable smoke artifacts (`device.key`, `smoke-device.*`).

## Cadence

| Artifact | When |
|----------|------|
| Postgres dump (encrypted) | Weekly while the lab is active; also after issuance/revocation spikes, profile/CMP changes, or before upgrades |
| Secrets bundle (encrypted) | After bootstrap, EST/SCEP setup, password rotation, SuperAdmin export, or any ceremony |
| Cold USB copy of secrets + age identity | After every secrets-bundle change (software-root era) |

No scheduler in v1 — run `./scripts/backup-pki.sh` manually.

## Age key custody

1. On a recovery machine (or once offline):

   ```sh
   age-keygen -o identity.txt
   ```

2. Store `identity.txt` **off the PKI host**: password manager and encrypted USB.
3. Copy only the public recipient line (`age1...`) into
   `backups/age-recipient.txt` on the PKI host. The recipient is non-secret;
   the identity is not.
4. Backup scripts encrypt only. Restore requires
   `AGE_IDENTITY=/path/to/identity.txt` (or `--identity`) at runtime.

NAS compromise plus a stolen age identity key means all backups are readable.
Treat the identity like a root-of-trust secret.

## SuperAdmin P12

After enrolling SuperAdmin (see
[`../issuing-ca/getting-started.md`](../issuing-ca/getting-started.md)):

1. Export the SuperAdmin PKCS#12 from the browser or OS keychain.
2. Store the P12 passphrase in your password manager.
3. Place the file at `backups/private/superadmin.p12` (gitignored) before the
   next secrets backup, or encrypt it separately with age.
4. With `EJBCA_TLS_SETUP_ENABLED=true`, losing this P12 without a recoverable
   admin path locks the admin UI.

## Disaster scenarios

- **A — Host dies, backups intact:** Decrypt dump + secrets → follow restore
  order → full recovery including issued-certificate history.
- **B — DB corrupt, secrets intact:** Rebuild from `issuing-ca.p12` + profiles +
  `./scripts/ejbca-setup-est.sh`. You **lose** end-entity and revocation history
  unless a dump exists.
- **C — Dump exists, secrets incomplete:** Dump + `issuing-ca.p12.pass` may
  reactivate the soft token if the PIN matches what encrypts the token in the
  DB. Still keep the P12 and bootstrap root for scenario B and trust-anchor
  recovery. Never assume a dump alone is enough without the PIN.

## Backup procedure

From the repo root, with the database container healthy:

```sh
cp backups/config.example.env backups/config.env   # once
# Edit NAS_* and retention; ensure backups/age-recipient.txt exists

./scripts/backup-pki.sh                 # dump + secrets + rsync
./scripts/backup-pki.sh --db-only       # encrypted dump only
./scripts/backup-pki.sh --secrets-only  # encrypted secrets only
./scripts/backup-pki.sh --no-rsync      # local staging only
./scripts/backup-pki.sh --prune         # after backup, prune NAS by keep-counts
./scripts/backup-pki.sh --dry-run
```

What the script does:

1. Streams `pg_dump -Fc` through `age` into `backups/staging/dumps/`.
2. Builds a secrets tarball (bootstrap artifacts, EST artifacts minus smoke
   scratch, `.env`, optional `backups/private/superadmin.p12`) and age-encrypts
   it into `backups/staging/secrets/`.
3. Writes a non-secret manifest (checksums of ciphertext, git rev, image tag).
4. Append-only `rsync` to the NAS (no `--delete`).
5. Optionally prunes remote dumps/secrets by keep-count.

After a successful secrets backup, copy the newest
`pki-secrets-*.tar.gz.age` to encrypted USB (and keep the age identity there
separately).

## Restore order

Prefer a drill with alternate `COMPOSE_PROJECT_NAME`, ports, and data directory
so the live lab is not clobbered. Match Postgres 16 and the EJBCA image tag
recorded in the manifest; pin `EJBCA_IMAGE_TAG` in `.env` before relying on
backups across upgrades.

```text
1. Decrypt secrets bundle to a secure temp dir (AGE_IDENTITY required)
2. Restore .env, bootstrap/artifacts, est/artifacts, scep/artifacts
3. Start ejbca-database only
4. DROP/CREATE the ejbca database (or use a fresh postgres volume)
5. Decrypt dump and pg_restore (EJBCA stopped)
6. Start ejbca
7. Activate crypto token with issuing-ca.p12.pass
8. Start est (if used)
9. Run ./scripts/est-smoke.sh and ./scripts/scep-smoke.sh
10. Import SuperAdmin P12 if TLS is hardened
```

Automated helper:

```sh
export AGE_IDENTITY=/secure/path/identity.txt
./scripts/restore-pki.sh \
  --secrets backups/staging/secrets/pki-secrets-YYYYMMDD-HHMMSS.tar.gz.age \
  --dump backups/staging/dumps/ejbca-YYYYMMDD-HHMMSS.dump.age \
  --force
```

Without `--force`, the restore script refuses to overwrite an existing
`issuing-ca/data/postgres` tree or live `.env`.

### Crypto token activation (required after every EJBCA restart)

```sh
KSPASS=$(cat bootstrap/artifacts/issuing-ca.p12.pass)
TOKEN=$(docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh cryptotoken list" | awk -F'"' '/Imported/{print $2}')
docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh cryptotoken activate --token '$TOKEN' --pin '$KSPASS'"
```

## Verification

- After each backup: rsync exit 0; local sha256 of ciphertext matches the NAS
  copy; manifest present.
- Quarterly: full restore drill on an alternate compose project.
- Before upgrades: take a dump and smoke-restore against the pinned image tag.

## HSM migration (later)

When Nitrokeys replace the bootstrap root:

| Asset | Action |
|-------|--------|
| Bootstrap root key | Destroy after HSM root is live and intermediates re-chained |
| Nitrokey A + B | Physical custody is the backup |
| PINs / SO-PINs | Password manager + sealed offline record |
| Issuing CA | Ceremony CSR → EJBCA import → update EST trust chain |

Encrypted Postgres dumps and EST/compose secrets stay the same. The secrets
bundle drops the bootstrap root key; keep cold copies of the age identity and
SuperAdmin P12.
