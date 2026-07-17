# Bootstrap Software Root CA

This runbook creates a **non-secure, OpenSSL file-based** self-signed root CA
and uses it to sign the online issuing CA. It exists so the issuing CA and the
rest of the online PKI can be developed before (or without) Nitrokey HSM 2
hardware.

This path does **not** satisfy [ADR-0001](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0001-nitrokey-hsm2-offline-ca.md).
The production offline root remains HSM-backed. Treat every certificate in this
bootstrap chain as lab/dev trust only until you replace it with a ceremony from
the [offline CA ceremony runbook](../offline-ca/ceremony-runbook.md).

## Who this is for

| Audience | Use this when | Then |
| -------- | ------------- | ---- |
| Operators without an HSM | You want a working issuing CA and accept a software root on disk | Keep using this root for the lab, or migrate later if you adopt HSMs |
| Operators waiting for Nitrokeys | You want to stand up the issuing CA now and re-root later | Follow [Migrate to the HSM offline root](#migrate-to-the-hsm-offline-root) when devices arrive |

Both audiences use the same commands. The difference is only how soon you plan
to retire the bootstrap root.

## Security model (read this)

- The root private key is a normal file (`*.key`). Anyone with the file can mint
  trusted certificates for this hierarchy.
- Do not use this root as a long-term trust anchor for anything you would regret
  re-issuing.
- Do not commit private keys, serial files, or unencrypted key material.
- Prefer an isolated machine or encrypted disk for key generation. Offline is
  still a good idea even for bootstrap.
- Name the bootstrap root differently from the eventual offline root so trust
  stores and `openssl` output cannot confuse them. See [ADR-0003](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md).

## Prerequisites

- OpenSSL 3.x (or a recent 1.1.1+ that supports these commands)
- A checkout of this repository
- Local copies of the bootstrap profiles (see below)
- An issuing CA CSR, or willingness to generate the issuing CA key and CSR in
  the same session

```sh
openssl version
git rev-parse HEAD
```

## Profiles and working directory

1. Copy the example profiles and optional env file:

   ```sh
   cp bootstrap/profiles/root-ca.cnf.example bootstrap/profiles/root-ca.cnf
   cp bootstrap/profiles/intermediate-ca.cnf.example bootstrap/profiles/intermediate-ca.cnf
   cp bootstrap/.env.example bootstrap/.env   # optional
   ```

2. Edit the local `*.cnf` (and `.env` if used) for your lab. Forks must choose
   their own `CN` / `O` values.

3. Create a local artifacts directory (gitignored):

   ```sh
   mkdir -p bootstrap/artifacts
   chmod 700 bootstrap/artifacts
   ```

My Cloud default bootstrap subject (examples only):

| Field | Bootstrap root | Issuing CA |
| ----- | -------------- | ---------- |
| `CN` | `My Cloud Bootstrap Root CA` | `My Cloud Issuing CA` |
| `O` | `My Cloud` | `My Cloud` |
| `OU` | `PKI` | `PKI` |

The issuing CA CN matches the production naming policy so the online stack can
keep the same subject when you re-sign under the HSM root later.

## 1. Create the bootstrap root CA

Choose a validity period:

| Situation | Suggested days | Why |
| --------- | -------------- | --- |
| Waiting for Nitrokeys | `730` (2 years) | Short enough to encourage migration; long enough to develop |
| No HSM planned | `3650` (10 years) | Typical lab root lifetime; still a software key |

Generate the key and self-signed root certificate:

```sh
cd bootstrap

openssl genrsa -out artifacts/bootstrap-root-ca.key 4096
chmod 600 artifacts/bootstrap-root-ca.key

openssl req -new -x509 \
  -days 730 \
  -key artifacts/bootstrap-root-ca.key \
  -out artifacts/bootstrap-root-ca.crt \
  -config profiles/root-ca.cnf
```

Verify:

```sh
openssl x509 -in artifacts/bootstrap-root-ca.crt -noout \
  -subject -issuer -dates -fingerprint -sha256
openssl x509 -in artifacts/bootstrap-root-ca.crt -noout -text
```

Confirm:

- Subject is the bootstrap root (`… Bootstrap Root CA`), not `… Offline Root CA`
- `CA:TRUE` is set
- Key usage includes `Certificate Sign` and `CRL Sign`

## 2. Create the issuing CA key and CSR

If the online issuing CA does not already have a key and CSR, generate them
here. Keep the issuing CA private key with the online issuing CA host or secret
store — not next to the bootstrap root key if you can avoid it.

```sh
openssl genrsa -out artifacts/issuing-ca.key 4096
chmod 600 artifacts/issuing-ca.key

openssl req -new \
  -key artifacts/issuing-ca.key \
  -out artifacts/issuing-ca.csr \
  -config profiles/intermediate-ca.cnf
```

Inspect the CSR:

```sh
openssl req -in artifacts/issuing-ca.csr -noout -subject -text
```

Subject must match [ADR-0003](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md)
(`My Cloud Issuing CA` for this deployment’s examples).

## 3. Sign the issuing CA with the bootstrap root

```sh
openssl x509 -req \
  -in artifacts/issuing-ca.csr \
  -CA artifacts/bootstrap-root-ca.crt \
  -CAkey artifacts/bootstrap-root-ca.key \
  -CAcreateserial \
  -out artifacts/issuing-ca.crt \
  -days 825 \
  -extfile profiles/intermediate-ca.cnf \
  -extensions v3_intermediate_ca
```

`825` days is a common intermediate lifetime (~2.25 years). Adjust if your lab
needs longer or shorter intermediates.

Verify the chain:

```sh
openssl x509 -in artifacts/issuing-ca.crt -noout \
  -subject -issuer -dates -fingerprint -sha256
openssl verify -CAfile artifacts/bootstrap-root-ca.crt artifacts/issuing-ca.crt
```

Expected verify output: `artifacts/issuing-ca.crt: OK`

Optional chain file for trust distribution:

```sh
cat artifacts/issuing-ca.crt artifacts/bootstrap-root-ca.crt \
  > artifacts/issuing-ca-chain.pem
```

## 4. Hand off to the online issuing CA

Copy only what the online stack needs:

| Artifact | Goes to | Commit? |
| -------- | ------- | ------- |
| `bootstrap-root-ca.crt` | Trust stores / issuing CA config as temporary root | Public cert only, if you want a shared lab trust anchor |
| `issuing-ca.crt` | Issuing CA service | Public cert only |
| `issuing-ca.key` | Issuing CA secret storage | **Never** |
| `bootstrap-root-ca.key` | Secure offline / encrypted storage | **Never** |
| `*.srl` | Local CA state next to the root key | **Never** |

Update `issuing-ca/` service configuration to use the issued certificate and key
once that service wiring exists. Until then, keep the verified artifacts under
`bootstrap/artifacts/` (local only).

## 5. Record what you did

Capture a short note (no secrets):

```text
Bootstrap software root created:
Date:
Operator:
Repository revision:
Root subject:
Root SHA-256 fingerprint:
Issuing CA subject:
Issuing CA SHA-256 fingerprint:
Root validity days:
Intermediate validity days:
Intended retirement: (e.g. "when Nitrokeys arrive" / "lab-only permanent")
```

## Migrate to the HSM offline root

When Nitrokey HSM 2 devices are available (or when you adopt any HSM-backed
offline root):

1. Run the [Root CA initialization ceremony](../offline-ca/ceremony-runbook.md#root-ca-initialization-ceremony)
   and produce the real offline root certificate.
2. Generate a **new** issuing CA CSR (recommended) or re-sign the existing CSR
   only if you accept keeping the same intermediate key.
3. Run the [Intermediate CA issuance ceremony](../offline-ca/ceremony-runbook.md#intermediate-ca-issuance-ceremony)
   with the HSM-held root.
4. Deploy the new issuing CA certificate (and key, if rotated) to the online
   stack.
5. Distribute the new offline root to trust stores; remove the bootstrap root.
6. Securely destroy `bootstrap/artifacts/bootstrap-root-ca.key` and related
   serial state after cutover is verified.
7. Optionally revoke the bootstrap-signed issuing CA if you still control the
   bootstrap root and maintain a CRL — otherwise rely on removing the bootstrap
   root from all trust stores.

After migration, stop using this runbook for production trust. Keep it for
forks and labs that deliberately choose a software root.

## Open items

- Wire `issuing-ca/` service config to consume these artifact paths.
- Add a thin script that wraps the OpenSSL steps once the paths stabilize.
- Document CRL generation for the bootstrap root if lab clients need revocation.
