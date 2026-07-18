# Scripts

Shared operational utilities used across PKI components.

| Script | Purpose |
|--------|---------|
| [`ejbca-setup-est.sh`](ejbca-setup-est.sh) | Configure CMP alias and EST artifacts |
| [`est-smoke.sh`](est-smoke.sh) | End-to-end EST enrollment smoke test |
| [`backup-pki.sh`](backup-pki.sh) | Age-encrypted Postgres dump + secrets; NAS rsync |
| [`restore-pki.sh`](restore-pki.sh) | Restore from encrypted dump + secrets bundle |

Backup procedures: [`../backups/runbook.md`](../backups/runbook.md).
