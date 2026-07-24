# PKI docs

Operational runbooks, ceremony notes, and PKI-specific documentation for this repository.

Cross-cutting architecture decisions stay in [my-cloud/docs/adr](https://github.com/ffbarrie/my-cloud/tree/main/docs/adr).

## Start here

| Doc | When to use |
| --- | ----------- |
| [Bootstrap software root CA](../bootstrap/software-root-ca.md) | No HSM yet, or lab without HSM |
| [EJBCA getting started](../issuing-ca/getting-started.md) | Bring up the online issuing CA |
| [HSM initialization](../offline-ca/hsm-initialization.md) | Nitrokey HSM 2 Linux setup, DKEK, wrap/unwrap |
| [Offline CA ceremony runbook](../offline-ca/ceremony-runbook.md) | Nitrokey HSM 2 offline root ceremonies |
| [Backup and restore runbook](../backups/runbook.md) | Encrypted Postgres + secrets backup / restore |
