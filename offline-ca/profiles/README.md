# Certificate profiles

OpenSSL profile templates for offline CA ceremonies.

| File | Purpose |
| ---- | ------- |
| [root-ca.cnf.example](root-ca.cnf.example) | Offline root CA subject and extensions |
| [intermediate-ca.cnf.example](intermediate-ca.cnf.example) | Issuing / intermediate CA CSR subject reference |

## Customize for your lab

1. Read [ADR-0003: PKI Certificate Naming and Subject DN Policy](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md).
2. Copy each `*.cnf.example` to a local `*.cnf` file (gitignored).
3. Optionally copy [../.env.example](../.env.example) to `../.env` for the same values in shell scripts.
4. Use the local profile during [ceremony-runbook.md](../ceremony-runbook.md) steps.

Forks must choose their own `CN`, `O`, and `OU` values. Do not reuse `My Cloud`
names unless you intend to operate a separate trust anchor with that identity.
