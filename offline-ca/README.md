# Offline CA

Documentation, HSM initialization, and ceremony scripts for the offline root CA.

This directory is the canonical home for offline CA material even though the root
does not run as a continuous Docker service. See:

- [ADR-0001: Nitrokey HSM 2 for Offline CA](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0001-nitrokey-hsm2-offline-ca.md)
- [ADR-0002: my-cloud-pki Repository Layout](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0002-my-cloud-pki-repository-layout.md)

Do not store PINs, SO-PINs, or other secrets in this repository.
