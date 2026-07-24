# Backups

Backup procedures and non-secret backup tooling for My Cloud PKI.

**Do not** store private keys, age identity keys, plaintext database dumps,
HSM secrets, or credentials in this directory (or in git). Staging ciphertext,
local `config.env`, and optional SuperAdmin drop files are gitignored.

## Docs and tooling

| Path | Purpose |
|------|---------|
| [`runbook.md`](runbook.md) | Tiers, cadence, age custody, disaster scenarios, restore order |
| [`config.example.env`](config.example.env) | Copy to `config.env` (NAS path, retention, recipient file) |
| [`../scripts/backup-pki.sh`](../scripts/backup-pki.sh) | Encrypted dump + secrets bundle, append-only rsync, `--prune` |
| [`../scripts/restore-pki.sh`](../scripts/restore-pki.sh) | Decrypt, restore artifacts + Postgres, post-restore checklist |

Online CA state lives in PostgreSQL under `issuing-ca/data/postgres/`
([ADR-0005](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0005-postgresql-datastore.md)).
Backups use logical `pg_dump` streamed through [age](https://github.com/FiloSottile/age),
not raw volume copies.

## Quick start

Works on **Linux and macOS** (Bash + Docker Compose v2). Install `age` first:

- macOS: `brew install age`
- Linux: distro package (e.g. `sudo dnf install age`, or Debian/Ubuntu `age` when
  available) or a binary from [age releases](https://github.com/FiloSottile/age/releases)

Platform notes (checksum tools, `stat`, NAS): see [runbook.md](runbook.md#host-os-linux-and-macos).

```sh
# One-time: age recipient on the PKI host (identity stays offline)
age-keygen -o identity.txt
grep '^# public key:' identity.txt | sed 's/^# public key: //' > backups/age-recipient.txt
# Store identity.txt offline (password manager + encrypted USB)

cp backups/config.example.env backups/config.env
# Edit NAS_* as needed

./scripts/backup-pki.sh --no-rsync    # local staging only
./scripts/backup-pki.sh               # + append-only rsync when NAS is configured
./scripts/backup-pki.sh --prune       # also prune remote keep-counts
```

Restore (identity required):

```sh
export AGE_IDENTITY=/secure/path/identity.txt
./scripts/restore-pki.sh \
  --secrets backups/staging/secrets/pki-secrets-TIMESTAMP.tar.gz.age \
  --dump backups/staging/dumps/ejbca-TIMESTAMP.dump.age \
  --force
```

Full procedures: [`runbook.md`](runbook.md).
