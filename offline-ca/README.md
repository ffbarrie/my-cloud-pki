# Offline CA

Documentation, HSM initialization, and ceremony scripts for the offline root CA.

## Runbooks

- [Nitrokey HSM 2 initialization and redundancy](hsm-initialization.md) —
  Linux tooling, DKEK setup, wrap/unwrap smoke test
- [Offline CA Ceremony Runbook](ceremony-runbook.md) — root and intermediate
  ceremonies after HSMs are initialized
- Waiting for HSMs, or no HSM at all?
  [Bootstrap software root CA](../bootstrap/software-root-ca.md)

## Public trust anchors

- [root-ca.crt](root-ca.crt) — My Cloud Offline Root CA (public certificate only;
  private key remains on the Nitrokey HSM 2 devices)
- [issuing-ca.crt](issuing-ca.crt) — My Cloud Issuing CA (public intermediate;
  private key is OpenSSL file-based until imported into EJBCA — never commit the
  key)
- [issuing-ca-chain.pem](issuing-ca-chain.pem) — intermediate + offline root
  (convenience chain)

## Certificate profiles

- [profiles/README.md](profiles/README.md)
- [profiles/root-ca.cnf.example](profiles/root-ca.cnf.example)
- [profiles/intermediate-ca.cnf.example](profiles/intermediate-ca.cnf.example)

Copy `*.cnf.example` to local `*.cnf` files and optionally `.env.example` to `.env`
before a ceremony. Local profile files and unredacted working notes under
`ceremonies/` are gitignored.

This directory is the canonical home for offline CA material even though the root
does not run as a continuous Docker service. See:

- [ADR-0001: Nitrokey HSM 2 for Offline CA](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0001-nitrokey-hsm2-offline-ca.md)
- [ADR-0002: my-cloud-pki Repository Layout](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0002-my-cloud-pki-repository-layout.md)
- [ADR-0003: PKI Certificate Naming and Subject DN Policy](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md)

Do not store PINs, SO-PINs, or other secrets in this repository.
