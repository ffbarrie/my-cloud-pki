# My Cloud PKI

This repository is the canonical implementation of the My Cloud private PKI: online services, offline CA ceremonies, bootstrap tooling, and operational docs.

Architecture decisions live in the central [My Cloud](https://github.com/ffbarrie/my-cloud) repository:

- [ADR-0001: Nitrokey HSM 2 for Offline CA](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0001-nitrokey-hsm2-offline-ca.md)
- [ADR-0002: my-cloud-pki Repository Layout](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0002-my-cloud-pki-repository-layout.md)
- [ADR-0003: PKI Certificate Naming and Subject DN Policy](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md)
- [ADR-0004: EJBCA Community as Online Issuing CA](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md)
- [ADR-0005: PostgreSQL for Online Stateful Services](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0005-postgresql-datastore.md)

## Bootstrap without an HSM

If you do not have Nitrokey HSM 2 devices yet, or do not plan to use an HSM,
create a temporary OpenSSL software root and sign the issuing CA with the
[bootstrap software root CA runbook](bootstrap/software-root-ca.md). Replace that
root with the HSM offline ceremony when hardware is available.

## Online issuing CA (EJBCA)

The always-on issuing CA is **EJBCA Community** on **PostgreSQL**. See
[issuing-ca/](issuing-ca/) and [issuing-ca/getting-started.md](issuing-ca/getting-started.md).

```sh
cp .env.example .env
# set EJBCA_DB_PASSWORD
docker compose up -d
```

## Repository layout

```text
my-cloud-pki
├── compose.yaml      # Online PKI services
├── .env.example
├── README.md
├── docs/             # Runbooks and operational docs
├── bootstrap/        # One-time / rare setup helpers (incl. software root CA)
├── offline-ca/       # Offline root CA (docs, HSM init, ceremonies; not always-on)
│   └── profiles/     # Certificate profile templates (*.cnf.example)
├── issuing-ca/       # Online intermediate / issuing CA (EJBCA CE)
├── ocsp/             # OCSP responder
├── est/              # Companion EST front-end (RFC 7030; CMP backend)
├── scep/             # Native EJBCA CE SCEP (CA/Client mode; docs + artifacts)
├── crl/              # CRL publication
├── keycloak/         # Identity integration for PKI flows
├── monitoring/       # Observability for online PKI components
├── scripts/          # Shared utilities
└── backups/          # Backup procedures and tooling
```

The offline CA does **not** run continuously in Docker. Its documentation, bootstrap scripts, ceremony notes, and HSM initialization instructions still live here so this repo remains the single source of truth for the PKI.

## License

All code, scripts, and documentation in this repository are licensed under the [Apache License 2.0](LICENSE).
