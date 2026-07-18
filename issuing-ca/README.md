# Issuing CA (EJBCA Community)

The online intermediate / issuing CA for My Cloud PKI is
**[EJBCA Community Edition](https://www.ejbca.org/)**, per
[ADR-0004](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md).

Persistent state uses **PostgreSQL**, per
[ADR-0005](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0005-postgresql-datastore.md).

EJBCA is the system of record for:

- Issuing CA key and certificate lifecycle
- Certificate / end-entity profiles
- Enrollment protocols (CMP/SCEP now on CE; EST to build later — see `../est/`)
- CRL and OCSP publication (initially; see `../ocsp/`, `../crl/`, `../est/`)

## Docs

| Doc | Purpose |
| --- | ------- |
| [getting-started.md](getting-started.md) | Bring up Compose, first admin access, next steps |
| [../bootstrap/software-root-ca.md](../bootstrap/software-root-ca.md) | Temporary OpenSSL root while waiting for Nitrokeys |
| [../offline-ca/ceremony-runbook.md](../offline-ca/ceremony-runbook.md) | HSM offline root ceremonies |

## Layout

```text
issuing-ca/
├── README.md
├── getting-started.md
├── profiles/             # Exported MyCloudServer / MyCloudServerEE XML
└── data/                 # Local only (gitignored)
    └── postgres/         # PostgreSQL volume for EJBCA
```

Compose services live in the repository root [`compose.yaml`](../compose.yaml).

## Trust chain

1. **Bootstrap (now):** OpenSSL software root signs the EJBCA issuing CA CSR.
2. **Target:** Nitrokey HSM 2 offline root signs the EJBCA issuing CA CSR; retire
   the bootstrap root from trust stores.

Subject naming follows
[ADR-0003](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md)
(`My Cloud Issuing CA` for this deployment’s examples).
