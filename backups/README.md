# Backups

Backup procedures and non-secret backup tooling/configuration for PKI components.

Do not store private keys, HSM backups containing secrets, or credentials here.

Online CA state lives in PostgreSQL under `issuing-ca/data/postgres/`
([ADR-0005](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0005-postgresql-datastore.md)).
Document `pg_dump` / restore procedures here as the lab hardens.
