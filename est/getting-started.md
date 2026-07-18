# Getting started with EST (companion service)

Enrollment over Secure Transport (RFC 7030) via the **companion EST service** in this
repo. EJBCA CE remains the issuing CA; EST talks to EJBCA over **CMP RA mode**.

Per [ADR-0004](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md),
native `/.well-known/est` on `keyfactor/ejbca-ce` is **not** available (no `est.war`).

## Architecture

```text
Client --EST--> est:8444 --CMP p10cr--> ejbca:8080 --sign--> My Cloud Issuing CA
```

| Layer | Auth | Notes |
| ----- | ---- | ----- |
| Client → EST | HTTP Basic (`est-ra.user` / `est-ra.pass`) | Lab RA mode; shared secret can mint **any CN** |
| EST → EJBCA | CMP HMAC (`cmp-ra.pass`) | Alias `mycloud`, RA mode; HTTP on `pki-internal` |

Backend choice (spike result): **CMP RA `p10cr`**, not Enrollment REST (REST Certificate
Management must be enabled in Admin UI and is not CLI-toggleable on CE). No EST-service
client certificate is used; CMP HMAC replaces that plan idea for the CE lab.

## Prerequisites

- Issuing CA imported per [../issuing-ca/getting-started.md](../issuing-ca/getting-started.md)
- Profiles `MyCloudServer` / `MyCloudServerEE` in EJBCA
- Docker Compose stack up (`docker compose up -d`)

After `docker compose restart ejbca`, reactivate the imported crypto token before
enrolling (see issuing-ca getting-started restart caveat).

## 1. One-time setup

From repo root:

```sh
./scripts/ejbca-setup-est.sh
docker compose up -d est
```

This script:

- Copies issuing + bootstrap root PEMs into `est/artifacts/`
- Configures CMP alias `mycloud` (RA mode, HMAC, PBE responses)
- Creates EST HTTP Basic and CMP HMAC secrets
- Issues `est-server.crt` (TLS for the EST listener, signed by the issuing CA)
- Writes `est/artifacts/est.env` for Compose

Published port (override in `.env`): host **8444** → EST container 8443.

## 2. Verify MVP

```sh
./scripts/est-smoke.sh
```

Or manually:

```sh
ART=est/artifacts
TRUST=$ART/IssuingCA.cacert.pem
ESTUSER=$(cat $ART/est-ra.user)
ESTPASS=$(cat $ART/est-ra.pass)
BASE=https://localhost:8444/.well-known/est

curl -sk --cacert "$TRUST" -o $ART/cacerts.b64 "$BASE/cacerts"
openssl base64 -A -d -in $ART/cacerts.b64 -out $ART/cacerts.p7
openssl pkcs7 -inform DER -in $ART/cacerts.p7 -print_certs -noout

openssl req -nodes -newkey rsa:2048 -keyout $ART/device.key \
  -out $ART/device.csr -outform DER -subj '/CN=est-test.my.cloud'
openssl base64 -in $ART/device.csr -out $ART/device.b64
chmod 600 $ART/device.key

curl -sk --cacert "$TRUST" --user "$ESTUSER:$ESTPASS" \
  --data @$ART/device.b64 -o $ART/device-p7.b64 \
  -H 'Content-Type: application/pkcs10' \
  -H 'Content-Transfer-Encoding: base64' \
  "$BASE/simpleenroll"

openssl base64 -A -d -in $ART/device-p7.b64 -out $ART/device-p7.der
openssl pkcs7 -inform DER -in $ART/device-p7.der -print_certs -out $ART/device-cert.pem
openssl x509 -in $ART/device-cert.pem -noout -subject -issuer
```

Trust the **issuing CA** PEM for TLS to EST (`--cacert IssuingCA.cacert.pem`). CSR subject
should use **CN only** to match `MyCloudServerEE` (no O/OU in the CSR).

## Deferred: simplereenroll (v1.1) — do not forget

**MVP does not implement certificate renewal.**

| Item | Detail |
| ---- | ------ |
| Endpoint | `POST /.well-known/est/simplereenroll` |
| MVP | Returns **501** with message pointing here |
| Blockers | mTLS trust (optional client cert on enroll, required on reenroll); CE end-entity `GENERATED` status; renewal via CMP `kur` or profile flags; revocation checks |

**v1.1 acceptance criteria:**

1. Spike-proven renewal path on CE (likely CMP `kur` from the companion).
2. EST listener trusts My Cloud Issuing CA for client certs on reenroll.
3. Valid leaf renews; revoked leaf rejected.
4. Same-key vs new-key policy aligned with profiles.
5. Smoke script covers reenroll success and auth failure.

Do not close the “deferred simplereenroll” tracking item when MVP merges.

## Enterprise-native EST (unused on CE)

[`aliases/est.properties.example`](aliases/est.properties.example) documents EJBCA
Enterprise native EST alias properties. On CE, `ejbca.sh config est …` stores config but
`/.well-known/est` still 404s without `est.war`.

## Security notes

- Treat `est/artifacts/*` and `est.env` as secrets; gitignored.
- HTTP Basic RA on EST is **lab only** (any holder can request any CN).
- CMP HMAC secret grants issuance rights to the companion only; kept off process
  argv via an openssl `file:` secret.
- EST→EJBCA CMP uses HTTP on the Compose internal network—do not publish EJBCA
  `:8080` beyond the lab host without TLS and tighter auth.
- Do not commit issuing CA private keys; setup uses local bootstrap artifacts.

## Related

- [README.md](README.md)
- [../scripts/ejbca-setup-est.sh](../scripts/ejbca-setup-est.sh)
- [../scripts/est-smoke.sh](../scripts/est-smoke.sh)
- [../issuing-ca/getting-started.md](../issuing-ca/getting-started.md)
