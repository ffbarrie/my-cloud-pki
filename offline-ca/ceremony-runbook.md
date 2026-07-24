# Offline CA Ceremony Runbook

This runbook defines how My Cloud performs offline root CA ceremonies using two
Nitrokey HSM 2 devices. It is intentionally operational: follow it when creating
or using the offline CA, and update it as scripts and tooling mature.

## Scope

This runbook covers:

- Preparing for an offline CA ceremony.
- Verifying the offline workstation and Nitrokey HSM 2 devices.
- Creating or using the offline root CA.
- Issuing, renewing, or revoking intermediate CA certificates.
- Recording ceremony evidence without committing secrets.

This runbook does not cover day-to-day leaf certificate issuance. Workload
certificates are issued by online intermediate CAs.

If Nitrokey HSM 2 devices are not available yet, or will not be used, create a
temporary file-based root with the
[bootstrap software root CA runbook](../bootstrap/software-root-ca.md) instead of
this ceremony. Migrate to this runbook when HSMs are in place.

Before the first root CA ceremony, initialize both devices with a shared DKEK
and run the wrap/unwrap smoke test in
[HSM initialization and redundancy](hsm-initialization.md).

## Security Model

The offline root CA private key is held on Nitrokey HSM 2 hardware and is not
stored as a software key. The offline CA is only used during deliberate
ceremonies, such as creating the root CA or signing an intermediate CA
certificate.

The root CA ceremony must preserve these invariants:

- The root private key is never exported from the HSM.
- The offline workstation is disconnected from all networks during CA
  operations.
- PINs, SO-PINs, recovery material, and other secrets are never committed to
  this repository.
- Public artifacts, redacted logs, and certificate metadata can be committed
  after review.
- Both Nitrokey HSM 2 devices are accounted for before and after the ceremony.

## Ceremony Types

| Ceremony | When it happens | Output |
| -------- | --------------- | ------ |
| Root CA initialization | One time, or during disaster recovery | Root CA key on HSM, self-signed root certificate |
| Intermediate CA issuance | When creating or renewing an issuing CA | Signed intermediate CA certificate |
| Intermediate CA revocation | If an issuing CA is compromised or retired | Updated root CRL |
| Root CA inspection | Periodic verification or audit | Redacted ceremony record |

## Roles

For now, the operator and witness may be the same person in a home-lab setting,
but the ceremony record should still identify the roles explicitly.

| Role | Responsibility |
| ---- | -------------- |
| Operator | Runs the ceremony steps and handles the HSMs |
| Witness | Reviews checklist completion and validates outputs |
| Custodian | Stores HSMs, PINs, and recovery material after the ceremony |

## Materials

Prepare these before starting:

- Offline workstation with required tooling installed.
- Nitrokey HSM 2 device A.
- Nitrokey HSM 2 device B.
- Printed or offline copy of this runbook.
- Trusted transfer media for moving CSRs and public certificates.
- Current `my-cloud-pki` repository checkout.
- Local root CA profile (`profiles/root-ca.cnf`, copied from
  `profiles/root-ca.cnf.example`).
- Local intermediate profile (`profiles/intermediate-ca.cnf`, copied from
  `profiles/intermediate-ca.cnf.example`) when signing an intermediate CA.
- Intermediate CA CSR, if this is an intermediate issuance ceremony.
- OpenSSL PKCS#11 engine package (`libengine-pkcs11-openssl` on Debian/Ubuntu)
  for HSM-backed `openssl req` / signing (see root self-sign steps below).

Do not bring unnecessary networked devices into the ceremony workspace.

## Artifacts

Allowed to commit:

- Public root CA certificate.
- Public intermediate CA certificates.
- Redacted ceremony records.
- Redacted command transcripts.
- OpenSSL configuration files and non-secret profiles.
- Scripts that do not embed secrets.

Never commit:

- HSM user PINs or SO-PINs.
- Recovery secrets or backup key material.
- Private keys, even if encrypted.
- Unredacted shell history.
- Unredacted HSM initialization logs.

## Pre-Ceremony Checklist

Record this checklist in the ceremony record.

- [ ] Ceremony purpose is written down.
- [ ] Operator is identified.
- [ ] Witness is identified, or the record states why there is no witness.
- [ ] Offline workstation is powered on.
- [ ] Network interfaces are disabled.
- [ ] Date and time are recorded.
- [ ] Repository revision is recorded with `git rev-parse HEAD`.
- [ ] Required scripts and configuration files are present.
- [ ] Transfer media has been inspected.
- [ ] Nitrokey HSM 2 device A is present.
- [ ] Nitrokey HSM 2 device B is present.
- [ ] Secrets are available to the operator but are not written into the record.

## Offline Workstation Verification

The supported ceremony host is Linux. Tool install, `pcscd` / polkit access, and
`PKCS11_MODULE` paths are in
[hsm-initialization.md](hsm-initialization.md#linux-workstation-setup).

Before inserting either HSM:

```sh
git status --short
git rev-parse HEAD
openssl version
pkcs11-tool --version
echo "$PKCS11_MODULE"
```

Then confirm the workstation is offline using local OS controls. Do not rely on
network tests that require connecting to a network.

Record tool versions in the ceremony record.

## HSM Inventory Verification

Perform this for each Nitrokey HSM 2 device, one device at a time.

```sh
opensc-tool --list-readers
pkcs11-tool --module "$PKCS11_MODULE" --list-slots
pkcs11-tool --module "$PKCS11_MODULE" --login --list-objects
sc-hsm-tool
pkcs15-tool --list-keys
```

Record non-secret identifying details:

- Device label / OpenSC serial.
- Token label.
- DKEK key check value (KCV), if already initialized.
- Public object labels and **Key ref** values from `pkcs15-tool` (not only
  PKCS#11 IDs).
- Public key fingerprints, if available.

Do not record PINs or SO-PINs.

When wrapping or unwrapping keys with `sc-hsm-tool`, use `--key-reference` from
`pkcs15-tool --list-keys`. That value is not the same as `pkcs11-tool --id`.
See [hsm-initialization.md](hsm-initialization.md#key-reference-vs-pkcs11-id-important).

## Root CA Initialization Ceremony

This ceremony is expected to be rare. Run it only when creating the My Cloud
root CA for the first time or during an approved disaster recovery event.

1. Complete the pre-ceremony checklist.
2. Verify the offline workstation.
3. Verify both Nitrokey HSM 2 devices.
4. Confirm the root CA subject against the local profile in `profiles/root-ca.cnf`
   and [ADR-0003](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md).
   Verify validity period, key algorithm, and certificate extensions.
5. Ensure both devices were initialized with a shared DKEK per
   [hsm-initialization.md](hsm-initialization.md) (or initialize them now,
   before generating the root key). Confirm both devices list **no** leftover
   smoke-test keys (`pkcs15-tool --list-keys`).
6. Generate the root CA key on device A (only A inserted):

   ```sh
   export PKCS11_MODULE=/usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
   # PIN: enter interactively or from custody notes — do not commit it
   pkcs11-tool --module "$PKCS11_MODULE" --login \
     --keypairgen --key-type rsa:4096 --id 01 --label 'MyCloud-Offline-Root'
   pkcs15-tool --list-keys
   ```

   Record the PKCS#11 **ID** (`01`) and the **Key ref** from `pkcs15-tool`
   (needed later for wrap; often `1`, but always confirm).

7. Create the self-signed root CA certificate using the HSM-held key
   (OpenSSL PKCS#11 **engine**, proven on Linux with OpenSC):

   Install the engine if missing:

   ```sh
   sudo apt install libengine-pkcs11-openssl
   ```

   Create a local engine config **without** embedding a PIN (example path
   `~/hsm-ceremony/openssl-engine-pkcs11.cnf`). Confirm `dynamic_path` exists
   on the host (`engines-3` vs distro-specific path):

   ```ini
   openssl_conf = openssl_init

   [openssl_init]
   engines = engine_section

   [engine_section]
   pkcs11 = pkcs11_section

   [pkcs11_section]
   engine_id = pkcs11
   dynamic_path = /usr/lib/x86_64-linux-gnu/engines-3/pkcs11.so
   MODULE_PATH = /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so
   init = 0
   ```

   Self-sign (subject and `v3_ca` extensions come from `profiles/root-ca.cnf`;
   pass `-days` explicitly to match the ceremony validity decision):

   ```sh
   mkdir -p ~/hsm-ceremony
   OPENSSL_CONF=~/hsm-ceremony/openssl-engine-pkcs11.cnf \
   openssl req -new -x509 -sha256 -days 7300 \
     -config offline-ca/profiles/root-ca.cnf \
     -engine pkcs11 -keyform engine \
     -key 'pkcs11:object=MyCloud-Offline-Root;type=private' \
     -out ~/hsm-ceremony/root-ca.crt
   ```

   The engine prompts for the user PIN. Do not put `PIN=` in the engine conf or
   `pin-value` in the URI for ceremony records.

   If the object URI fails, list private-key URIs with `p11tool` (from
   `gnutls-bin`) or try the engine legacy form `-key 0:01` (slot:PKCS#11 id).

   Optionally store the public certificate on the token next to the key (same
   id / label). This does not export the private key:

   ```sh
   pkcs11-tool --module "$PKCS11_MODULE" --login \
     --write-object ~/hsm-ceremony/root-ca.crt --type cert \
     --id 01 --label 'MyCloud-Offline-Root'
   ```

8. Verify the root CA certificate:

   ```sh
   openssl x509 -in ~/hsm-ceremony/root-ca.crt -noout \
     -subject -issuer -dates -fingerprint -sha256
   openssl x509 -in ~/hsm-ceremony/root-ca.crt -noout -text
   ```

   Confirm subject equals issuer, `CA:TRUE`, `keyCertSign` / `cRLSign`, and the
   expected validity window. Record the SHA-256 fingerprint in the ceremony
   record.

9. Wrap the root key on A and unwrap it on B (same DKEK), using the correct
   `--key-reference` from `pkcs15-tool --list-keys`. See the smoke-test pattern
   in [hsm-initialization.md](hsm-initialization.md#dkek-smoke-test-wrap-a--unwrap-b).
10. Verify device B lists the restored root key material.
11. Export only public artifacts from the offline workstation
    (`root-ca.crt` and redacted record). Do not export wrap files, `.pbe`
    shares, or anything containing PIN material.
12. Complete the post-ceremony checklist.

Implementation notes:

- Device init, DKEK, and wrap/unwrap details live in
  [hsm-initialization.md](hsm-initialization.md).
- Prefer the OpenSSL **engine** (`libengine-pkcs11-openssl`) for root self-sign
  on this stack. The OpenSSL 3 `pkcs11-provider` path is an alternative but is
  easier to misconfigure via `OPENSSL_CONF` clashes with `-config`.
- If a step would expose private key material outside the HSM (except as a
  DKEK-wrapped blob), stop the ceremony and revise the procedure.

## Intermediate CA Issuance Ceremony

Use this ceremony to sign an intermediate CA CSR from the online issuing CA
environment.

1. Complete the pre-ceremony checklist.
2. Verify the offline workstation.
3. Verify the active Nitrokey HSM 2 device.
4. Inspect the intermediate CA CSR:

   ```sh
   openssl req -in intermediate-ca.csr -noout -subject -text
   ```

5. Confirm the CSR subject matches `profiles/intermediate-ca.cnf` and
   [ADR-0003](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md).
   Verify key usage, extended key usage, path length, and validity period.
6. Sign the CSR with the offline root CA using the HSM-held root key.
7. Verify the issued intermediate certificate:

   ```sh
   openssl x509 -in intermediate-ca.crt -noout -subject -issuer -dates -fingerprint -sha256
   openssl verify -CAfile root-ca.crt intermediate-ca.crt
   ```

8. Export the intermediate certificate, root certificate, and redacted ceremony
   record to trusted transfer media.
9. Complete the post-ceremony checklist.

## Intermediate CA Revocation Ceremony

Use this ceremony if an intermediate CA must be revoked.

1. Complete the pre-ceremony checklist.
2. Verify the offline workstation.
3. Verify the active Nitrokey HSM 2 device.
4. Confirm the intermediate certificate serial number and reason for revocation.
5. Revoke the intermediate certificate with the offline root CA.
6. Generate an updated root CRL.
7. Verify the CRL:

   ```sh
   openssl crl -in root-ca.crl -noout -text
   ```

8. Export the updated CRL and redacted ceremony record to trusted transfer
   media.
9. Complete the post-ceremony checklist.

## Post-Ceremony Checklist

- [ ] Public artifacts are verified.
- [ ] Redacted ceremony record is complete.
- [ ] No secrets are present in files that will be committed.
- [ ] Shell history and temporary files are reviewed and cleared as needed.
- [ ] Transfer media contains only expected artifacts.
- [ ] HSM device A is accounted for.
- [ ] HSM device B is accounted for.
- [ ] Offline workstation is powered down.
- [ ] HSMs and secret material are returned to storage.
- [ ] Public artifacts are committed to the repository, if appropriate.

## Ceremony Record Template

Copy this template into a dated record when a ceremony is performed.

```text
Ceremony:
Date:
Operator:
Witness:
Repository revision:
Offline workstation:
HSM device used:
Other HSM device verified:

Purpose:

Inputs:

Commands run:

Outputs:

Verification:

Exceptions or deviations:

Follow-up actions:
```

## Open Items

- Add scripts for repeatable CSR inspection, signing, and artifact verification.
- Document exact OpenSSL PKCS#11 engine commands for **intermediate CSR
  signing** and root CRL issuance on the HSM-held key (root self-sign is
  documented above).
- Decide where redacted ceremony records will be stored.
- Document device custody and PIN policy (see ADR-0001 follow-ups).
