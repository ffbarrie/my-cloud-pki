# Getting started with EJBCA (online issuing CA)

Bring up EJBCA Community as the online issuing CA, create the first SuperAdmin
credential, then import or create the My Cloud Issuing CA under either the
bootstrap software root or the HSM offline root.

Official Keyfactor tutorial (reference):
https://docs.keyfactor.com/ejbca/latest/tutorial-start-out-with-ejbca-docker-container

## Prerequisites

- Docker Engine with Compose v2
- A checkout of this repository on `develop` (or a feature branch)
- Local `.env` copied from [`.env.example`](../.env.example)

```sh
cp .env.example .env
# Edit EJBCA_DB_PASSWORD and EJBCA_DB_ROOT_PASSWORD before first start.
```

## 1. Start the stack

```sh
mkdir -p issuing-ca/data/mariadb
docker compose up -d
docker compose ps
docker compose logs -f ejbca
```

Wait until EJBCA reports that it is ready. First boot initializes the database
and can take several minutes.

Default published ports (override in `.env`):

| Port | Purpose |
| ---- | ------- |
| `8080` | HTTP (redirect / public RA surfaces as configured) |
| `8443` | HTTPS admin / RA |

## 2. Initial admin access (`TLS_SETUP_ENABLED=simple`)

With `EJBCA_TLS_SETUP_ENABLED=simple` (the `.env.example` default), open:

```text
https://localhost:8443/ejbca/adminweb/
```

Accept the temporary TLS warning if the container is using its built-in
certificate. Enroll the SuperAdmin credential from the RA enrollment link shown
in the EJBCA container logs (`docker compose logs ejbca`), import the P12 into
your browser or OS trust store, then tighten access.

After SuperAdmin works with a client certificate:

1. Set `EJBCA_TLS_SETUP_ENABLED=true` in `.env`
2. Recreate the EJBCA container: `docker compose up -d ejbca`
3. Confirm unauthenticated admin access is no longer allowed

## 3. Create or import the Issuing CA

Goal: an intermediate CA whose subject matches
[ADR-0003](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md)
— for My Cloud examples, `CN=My Cloud Issuing CA, O=My Cloud, OU=PKI`.

### While waiting for Nitrokeys (bootstrap)

1. In EJBCA, create a CA of type **Subordinate CA** (or generate a CSR for an
   external signing ceremony—prefer the CSR path so the offline/bootstrap root
   remains outside EJBCA).
2. Export the CSR.
3. Sign it with the
   [bootstrap software root](../bootstrap/software-root-ca.md).
4. Import the signed certificate (and bootstrap root as an external CA / trust
   anchor as required by EJBCA) back into EJBCA.

### After Nitrokeys arrive

1. Generate a fresh issuing CA CSR from EJBCA (recommended when cutting over).
2. Sign it in an
   [offline CA ceremony](../offline-ca/ceremony-runbook.md#intermediate-ca-issuance-ceremony).
3. Import the signed certificate and offline root into EJBCA.
4. Remove the bootstrap root from lab trust stores.

Detailed EJBCA click-paths and profile templates will be added as follow-up
runbooks once the first lab CA is stood up.

## 4. Profiles and protocols (next)

After the issuing CA exists:

- Create certificate and end-entity profiles for server / client TLS
- Enable EST under the `est/` integration notes when ready
- Confirm CRL and OCSP URLs for issued certificates (`crl/`, `ocsp/`)
- Plan Keycloak integration for admin or enrollment identity (`keycloak/`)

## 5. Stop and data

```sh
docker compose down
```

MariaDB data persists under `issuing-ca/data/mariadb/` (gitignored). Treat that
directory as sensitive: it holds CA state. Back it up according to
[`../backups/`](../backups/).

## Security notes

- Change database passwords before the first `compose up`.
- `TLS_SETUP_ENABLED=simple` is for lab bootstrap only.
- Do not commit `.env`, database dumps, SuperAdmin P12 files, or CA private
  keys.
- EJBCA CE is accepted for this home lab per ADR-0004; it is not Keyfactor’s
  commercially supported Enterprise product.
