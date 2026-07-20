# Getting started with EJBCA (online issuing CA)

Bring up EJBCA Community as the online issuing CA, create the first SuperAdmin
credential, then import or create the My Cloud Issuing CA under either the
bootstrap software root or the HSM offline root.

Official Keyfactor tutorial (MariaDB-oriented reference):
https://docs.keyfactor.com/ejbca/latest/tutorial-start-out-with-ejbca-docker-container

This lab uses **PostgreSQL** instead of MariaDB
([ADR-0005](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0005-postgresql-datastore.md)).

## Prerequisites

- Docker Engine with Compose v2
- A checkout of this repository on `develop` (or a feature branch)
- Local `.env` copied from [`.env.example`](../.env.example)

```sh
cp .env.example .env
# Edit EJBCA_DB_PASSWORD before first start.
```

## 1. Start the stack

```sh
mkdir -p issuing-ca/data/postgres
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

### While waiting for Nitrokeys (bootstrap, verified path)

This imports the bootstrap-signed issuing CA (key + cert) produced by the
[bootstrap software root runbook](../bootstrap/software-root-ca.md) into EJBCA as
an externally-signed CA. All commands use the in-container EJBCA CLI.

1. Build a PKCS#12 from the issuing CA key and cert, including the bootstrap root
   in the chain (run from the repo root on the host):

   ```sh
   cd bootstrap/artifacts
   KSPASS=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-18)
   echo "$KSPASS" > issuing-ca.p12.pass && chmod 600 issuing-ca.p12.pass
   openssl pkcs12 -export \
     -name "My Cloud Issuing CA" \
     -inkey issuing-ca.key \
     -in issuing-ca.crt \
     -certfile bootstrap-root-ca.crt \
     -out issuing-ca.p12 \
     -passout pass:"$KSPASS"
   chmod 600 issuing-ca.p12
   cd ../..
   ```

2. Stream the P12 into the container as the `ejbca` user (a plain
   `docker compose cp` lands as an unreadable root-owned file), then import.

   Use `bash -c` (not `-lc`) for file staging: a login shell sources
   `/etc/profile`, which prints a harmless
   `id: cannot find name for user ID 10001` because the image runs as UID
   10001 with no matching `/etc/passwd` entry. Keep `-lc` for `ejbca.sh`
   so the CLI picks up the image's Java/`PATH` profile settings (ignore the
   same warning there).

   ```sh
   KSPASS=$(cat bootstrap/artifacts/issuing-ca.p12.pass)
   docker compose exec -T ejbca bash -c \
     'cat > /opt/keyfactor/issuing-ca.p12 && chmod 600 /opt/keyfactor/issuing-ca.p12' \
     < bootstrap/artifacts/issuing-ca.p12

   docker compose exec -T ejbca bash -lc \
     "/opt/keyfactor/bin/ejbca.sh ca importca \
       --caname 'My Cloud Issuing CA' \
       --p12 /opt/keyfactor/issuing-ca.p12 \
       -kspassword '$KSPASS'"

   # Remove the staged keystore from the container afterward
   docker compose exec -T ejbca bash -c 'rm -f /opt/keyfactor/issuing-ca.p12'
   ```

3. Verify the CA exists and the health check passes:

   ```sh
   docker compose exec -T ejbca bash -lc \
     "/opt/keyfactor/bin/ejbca.sh ca listcas" | grep 'CA Name'
   curl -s http://localhost:8080/ejbca/publicweb/healthcheck/ejbcahealth   # -> ALLOK
   ```

> **Restart caveat:** the imported soft crypto token uses **manual** activation.
> The CA is active immediately after import, but after `docker compose restart`
> (or `up` following a `down`) reactivate it with:
>
> ```sh
> KSPASS=$(cat bootstrap/artifacts/issuing-ca.p12.pass)
> TOKEN=$(docker compose exec -T ejbca bash -lc \
>   "/opt/keyfactor/bin/ejbca.sh cryptotoken list" | awk -F'"' '/Imported/{print $2}')
> docker compose exec -T ejbca bash -lc \
>   "/opt/keyfactor/bin/ejbca.sh cryptotoken activate --token '$TOKEN' --pin '$KSPASS'"
> ```

### After Nitrokeys arrive

1. Generate a fresh issuing CA CSR from EJBCA (recommended when cutting over).
2. Sign it in an
   [offline CA ceremony](../offline-ca/ceremony-runbook.md#intermediate-ca-issuance-ceremony).
3. Import the signed certificate and offline root into EJBCA.
4. Remove the bootstrap root from lab trust stores.

### Validate issuance (optional)

Prove the CA can sign, then clean up the test entity:

```sh
docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ra addendentity --username testsvc01 \
    --dn 'CN=test-service.my.cloud,O=My Cloud' --caname 'My Cloud Issuing CA' \
    --type 1 --token PEM --password foo123"
docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ra setclearpwd testsvc01 foo123"
docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh batch --username testsvc01"
# Inspect /opt/keyfactor/p12/pem/test-service.my.cloud.pem, then:
docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ra revokeendentity --username testsvc01 -r 5"
printf 'y\n' | docker compose exec -T ejbca bash -lc \
  "/opt/keyfactor/bin/ejbca.sh ra delendentity testsvc01"
```

## 4. Profiles, EST companion, and other protocols

After the issuing CA exists:

- Import TLS profiles from [`profiles/`](profiles/) (`MyCloudServer` /
  `MyCloudServerEE`)
- **EST (companion):** `./scripts/ejbca-setup-est.sh` then `docker compose up -d est`
  — see [`../est/getting-started.md`](../est/getting-started.md). MVP:
  `/cacerts` + `/simpleenroll` on host port **8444**; `/simplereenroll` deferred v1.1.
- **CMP:** native CE servlet (also backs EST); alias `mycloud` from EST setup
- **SCEP:** native CE servlet in **CA/Client mode** — `./scripts/ejbca-setup-scep.sh`
  then [`../scep/getting-started.md`](../scep/getting-started.md). RA mode is
  Enterprise-only (CE rejects PKCSReq if `operationmode=ra`).
- Confirm CRL and OCSP URLs for issued certificates (`crl/`, `ocsp/`)
- Plan Keycloak integration for admin or enrollment identity (`keycloak/`),
  also on PostgreSQL per ADR-0005

After `docker compose restart ejbca`, reactivate the imported crypto token before
EST, CMP, or SCEP enrollment (see restart caveat in section 3).

## 5. Stop and data

```sh
docker compose down
```

PostgreSQL data persists under `issuing-ca/data/postgres/` (gitignored). Treat
that directory as sensitive: it holds CA state. Back it up according to
[`../backups/`](../backups/).

If you previously started the MariaDB-based scaffold, remove
`issuing-ca/data/mariadb/` and start fresh with Postgres—do not mix engines on
the same volume.

## Security notes

- Change `EJBCA_DB_PASSWORD` before the first `compose up`.
- `TLS_SETUP_ENABLED=simple` is for lab bootstrap only.
- Do not commit `.env`, database dumps, SuperAdmin P12 files, or CA private
  keys.
- EJBCA CE is accepted for this home lab per ADR-0004; it is not Keyfactor’s
  commercially supported Enterprise product.
