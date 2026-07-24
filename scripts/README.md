# Scripts

Shared operational utilities used across PKI components.

| Script | Purpose |
|--------|---------|
| [`ejbca-setup-est.sh`](ejbca-setup-est.sh) | Configure CMP alias and EST artifacts |
| [`est-smoke.sh`](est-smoke.sh) | End-to-end EST enrollment smoke test |
| [`ejbca-setup-scep.sh`](ejbca-setup-scep.sh) | Configure native SCEP alias (CE CA/Client mode) |
| [`scep-add-ee.sh`](scep-add-ee.sh) | Pre-register end entity for SCEP enroll |
| [`scep-smoke.sh`](scep-smoke.sh) | SCEP GetCACaps/GetCACert (+ enroll if `sscep`) |
| [`backup-pki.sh`](backup-pki.sh) | Age-encrypted Postgres dump + secrets; NAS rsync |
| [`restore-pki.sh`](restore-pki.sh) | Restore from encrypted dump + secrets bundle |

Backup procedures: [`../backups/runbook.md`](../backups/runbook.md).
