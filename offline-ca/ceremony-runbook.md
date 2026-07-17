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

Before inserting either HSM:

```sh
git status --short
git rev-parse HEAD
openssl version
pkcs11-tool --version
```

Then confirm the workstation is offline using local OS controls. Do not rely on
network tests that require connecting to a network.

Record tool versions in the ceremony record.

## HSM Inventory Verification

Perform this for each Nitrokey HSM 2 device, one device at a time.

```sh
pkcs11-tool --module "$PKCS11_MODULE" --list-slots
pkcs11-tool --module "$PKCS11_MODULE" --login --list-objects
```

Record non-secret identifying details:

- Device label.
- Token label.
- Public object labels.
- Public key fingerprints, if available.

Do not record PINs or SO-PINs.

## Root CA Initialization Ceremony

This ceremony is expected to be rare. Run it only when creating the My Cloud
root CA for the first time or during an approved disaster recovery event.

1. Complete the pre-ceremony checklist.
2. Verify the offline workstation.
3. Verify both Nitrokey HSM 2 devices.
4. Confirm the root CA subject against the local profile in `profiles/root-ca.cnf`
   and [ADR-0003](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md).
   Verify validity period, key algorithm, and certificate extensions.
5. Initialize device A according to the HSM initialization procedure.
6. Generate the root CA key on device A.
7. Create the self-signed root CA certificate using the HSM-held key.
8. Verify the root CA certificate:

   ```sh
   openssl x509 -in root-ca.crt -noout -subject -issuer -dates -fingerprint -sha256
   openssl x509 -in root-ca.crt -noout -text
   ```

9. Initialize or provision device B according to the redundancy procedure.
10. Verify that device B can support the documented recovery or continuity path.
11. Export only public artifacts from the offline workstation.
12. Complete the post-ceremony checklist.

Implementation notes:

- The exact HSM initialization and redundancy procedure will be documented in a
  dedicated HSM runbook.
- If a step would expose private key material outside the HSM, stop the
  ceremony and revise the procedure.

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

- Document the Nitrokey HSM 2 initialization procedure.
- Document the two-device recovery or continuity procedure.
- Add scripts for repeatable CSR inspection, signing, and artifact verification.
- Decide where redacted ceremony records will be stored.
