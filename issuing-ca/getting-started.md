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
certificate. Anyone with HTTPS access can manage the instance until you tighten
access.

Create the first SuperAdmin credential from the RA Web (current EJBCA Community
images do **not** print a SuperAdmin enrollment URL in the container logs when
using `simple`):

1. In the Admin UI, open **RA Web**
2. Under **Request new certificate**, choose **Make New Request**
3. Keep **ENDUSER**, generate the key pair **By the CA**, and pick a key
   algorithm (for example RSA 2048)
4. Set Common Name to `SuperAdmin`
5. Under **Provide User Credentials**, set a username (for example
   `superadmin`) and an enrollment password; clear **Key Recoverable** if shown
6. Download the PKCS#12 and import it into your browser or OS trust store

After SuperAdmin works with a client certificate:

1. Set `EJBCA_TLS_SETUP_ENABLED=true` in `.env`
2. Recreate the EJBCA container: `docker compose up -d ejbca`
3. Confirm unauthenticated admin access is no longer allowed

## 3. Create or import the Issuing CA

Goal: an intermediate CA whose subject matches
[ADR-0003](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md)
— for My Cloud examples, `CN=My Cloud Issuing CA, O=My Cloud, OU=PKI`.

Pick **one** option below:

- **Option A — Bootstrap software root** (verified path, while waiting for
  Nitrokeys). EJBCA imports an OpenSSL-generated issuing key + cert as a P12.
- **Option B — HSM offline root** (Path A: EJBCA generates the issuing key,
  the HSM offline root signs the CSR). Use this once the Nitrokey HSM 2 offline
  root exists.

### Option A — Bootstrap software root (verified path)

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

### Option B — HSM offline root (Path A: EJBCA-generated key)

Use this when the [Nitrokey HSM 2 offline root](../offline-ca/ceremony-runbook.md)
exists. **EJBCA generates and keeps the issuing CA private key**; the HSM offline
root only signs the CSR. This is why `offline-ca/` holds **only** public certs
(`root-ca.crt`, later `issuing-ca.crt`) — there is no issuing private key or CSR
to publish, and no ceremony-issued "issuing password." The one secret you create
here is the EJBCA **crypto token password**, which stays on the EJBCA host.

You need `offline-ca/root-ca.crt` (the published offline root) present in this
checkout before starting.

1. Choose a strong crypto token password and save it to your secrets bundle
   ([backups runbook](../backups/runbook.md)) — you will need it if you ever
   re-activate or export the token:

   ```sh
   CATOKENPASS=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-18)
   echo "$CATOKENPASS"   # copy into your password manager / secrets bundle now
   ```

2. Stage the offline root into the container so EJBCA registers it as the
   external signer, then create the CA. `ca init --signedby External` generates
   the issuing key pair **inside EJBCA** and writes a PKCS#10 CSR to disk; the CA
   is left in "waiting for certificate response" state.

   ```sh
   docker compose cp offline-ca/root-ca.crt ejbca:/opt/keyfactor/root-ca.crt

   docker compose exec -T ejbca bash -lc \
     "cd /opt/keyfactor && /opt/keyfactor/bin/ejbca.sh ca init \
       'My Cloud Issuing CA' \
       'CN=My Cloud Issuing CA,O=My Cloud,OU=PKI' \
       soft '$CATOKENPASS' \
       4096 RSA 825 null SHA256WithRSA \
       --signedby External -externalcachain /opt/keyfactor/root-ca.crt"
   ```

   The validity (`825`) and policy (`null`) args are required positionally but
   are overridden by the issuer at signing time.

3. Copy the CSR out of the container and convert DER → PEM. EJBCA names it after
   the CA (spaces preserved):

   ```sh
   docker compose cp \
     "ejbca:/opt/keyfactor/My Cloud Issuing CA_csr.der" /tmp/issuing-ca.csr.der
   openssl req -inform DER -in /tmp/issuing-ca.csr.der -out /tmp/issuing-ca.csr
   openssl req -in /tmp/issuing-ca.csr -noout -subject -verify
   ```

   Transport `/tmp/issuing-ca.csr` (public data) to the offline workstation as
   `~/hsm-ceremony/issuing-ca.csr`.

4. Sign the CSR with the HSM offline root using the **EJBCA-generated CSR** path
   of the
   [Intermediate CA Issuance Ceremony](../offline-ca/ceremony-runbook.md#intermediate-ca-issuance-ceremony).
   That produces `~/hsm-ceremony/issuing-ca.crt`. Export only the public
   certificate; commit it to `offline-ca/issuing-ca.crt` per the ceremony's
   post-steps.

5. Bring `offline-ca/issuing-ca.crt` back to the EJBCA host and import the
   response, which activates the CA:

   ```sh
   docker compose cp offline-ca/issuing-ca.crt ejbca:/opt/keyfactor/issuing-ca.crt
   docker compose exec -T ejbca bash -lc \
     "/opt/keyfactor/bin/ejbca.sh ca importcacert \
       'My Cloud Issuing CA' /opt/keyfactor/issuing-ca.crt"

   # Clean up staged files in the container
   docker compose exec -T ejbca bash -c \
     'rm -f "/opt/keyfactor/My Cloud Issuing CA_csr.der" \
       /opt/keyfactor/root-ca.crt /opt/keyfactor/issuing-ca.crt'
   ```

6. Verify the CA is active and the chain is correct:

   ```sh
   docker compose exec -T ejbca bash -lc \
     "/opt/keyfactor/bin/ejbca.sh ca listcas" | grep -A2 'My Cloud Issuing CA'
   docker compose exec -T ejbca bash -lc \
     "/opt/keyfactor/bin/ejbca.sh ca getcacert --caname 'My Cloud Issuing CA' -f /dev/stdout" \
     | openssl x509 -noout -subject -issuer
   curl -s http://localhost:8080/ejbca/publicweb/healthcheck/ejbcahealth   # -> ALLOK
   ```

   Expected: subject `CN=My Cloud Issuing CA, O=My Cloud, OU=PKI`, issuer
   `CN=My Cloud Offline Root CA, O=My Cloud, OU=PKI`.

> **No manual reactivation:** unlike the imported bootstrap P12 token (Option A),
> the soft crypto token created by `ca init` is auto-activated with
> `CATOKENPASS`, so the issuing CA comes back automatically after
> `docker compose restart`. Keep `CATOKENPASS` in the secrets bundle regardless.

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
- **EST (companion):** `./scripts/ejbca-setup-est.sh --root bootstrap` or
  `--root hsm`, then `docker compose up -d --force-recreate est`
  — see [`../est/getting-started.md`](../est/getting-started.md). MVP:
  `/cacerts` + `/simpleenroll` on host port **8444**; `/simplereenroll` deferred v1.1.
  The Issuing CA signs the EST **listener leaf** (`est-server.crt`) as
  `CN=pioche.local` with SAN `DNS:pioche.local`, `DNS:localhost`, `IP:127.0.0.1`
  (override with `EST_SERVER_CN` / `EST_SERVER_SANS`). The Issuing CA certificate
  itself remains `CN=My Cloud Issuing CA` (no host SAN).
- **CMP:** native CE servlet (also backs EST); alias `mycloud` from EST setup
- **SCEP:** native CE servlet in **CA/Client mode** —
  `SCEP_HOST=pioche.local ./scripts/ejbca-setup-scep.sh --root bootstrap` or
  `--root hsm`; then see [`../scep/getting-started.md`](../scep/getting-started.md).
  RA mode is Enterprise-only (CE rejects PKCSReq if `operationmode=ra`).
- Confirm CRL and OCSP URLs for issued certificates (`crl/`, `ocsp/`)
- Plan Keycloak integration for admin or enrollment identity (`keycloak/`),
  also on PostgreSQL per ADR-0005

If you used **Option A** (bootstrap import), reactivate the imported crypto token
after `docker compose restart ejbca` before EST, CMP, or SCEP enrollment (see the
restart caveat in section 3). **Option B** (HSM, `ca init`) auto-activates and
needs no manual step.

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
