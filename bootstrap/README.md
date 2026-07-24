# Bootstrap

One-time or rarely run setup helpers for bringing up My Cloud PKI prerequisites
and initial configuration.

## Software root CA (no HSM)

Use this while waiting for Nitrokey HSM 2 devices, or if you will not use an HSM
at all. It creates a file-based OpenSSL root and signs the issuing CA.

- [software-root-ca.md](software-root-ca.md) — full runbook
- [profiles/](profiles/) — OpenSSL profile examples

This path is explicitly non-secure relative to [ADR-0001](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0001-nitrokey-hsm2-offline-ca.md).
When HSMs are available, initialize them with
[hsm-initialization.md](../offline-ca/hsm-initialization.md), then migrate using
the [offline CA ceremony runbook](../offline-ca/ceremony-runbook.md).
