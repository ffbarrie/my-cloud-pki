# Offline CA

Documentation, HSM initialization, and ceremony scripts for the offline root CA.

## Runbooks

- [Offline CA Ceremony Runbook](ceremony-runbook.md)
- Waiting for HSMs, or no HSM at all?
  [Bootstrap software root CA](../bootstrap/software-root-ca.md)

## Certificate profiles

- [profiles/README.md](profiles/README.md)
- [profiles/root-ca.cnf.example](profiles/root-ca.cnf.example)
- [profiles/intermediate-ca.cnf.example](profiles/intermediate-ca.cnf.example)

Copy `*.cnf.example` to local `*.cnf` files and optionally `.env.example` to `.env`
before a ceremony. Local profile files are gitignored.

This directory is the canonical home for offline CA material even though the root
does not run as a continuous Docker service. See:

- [ADR-0001: Nitrokey HSM 2 for Offline CA](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0001-nitrokey-hsm2-offline-ca.md)
- [ADR-0002: my-cloud-pki Repository Layout](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0002-my-cloud-pki-repository-layout.md)
- [ADR-0003: PKI Certificate Naming and Subject DN Policy](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md)

Do not store PINs, SO-PINs, or other secrets in this repository.
