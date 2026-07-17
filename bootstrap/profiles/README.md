# Certificate profiles for the bootstrap software root CA.

| File | Purpose |
| ---- | ------- |
| [root-ca.cnf.example](root-ca.cnf.example) | Bootstrap root CA subject and extensions |
| [intermediate-ca.cnf.example](intermediate-ca.cnf.example) | Issuing CA CSR subject and signing extensions |

## Customize for your lab

1. Read [ADR-0003: PKI Certificate Naming and Subject DN Policy](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0003-pki-certificate-naming.md).
2. Copy each `*.cnf.example` to a local `*.cnf` file (gitignored).
3. Optionally copy [../.env.example](../.env.example) to `../.env`.
4. Follow [../software-root-ca.md](../software-root-ca.md).

The bootstrap root CN must stay distinct from the offline root CN
(`… Bootstrap Root CA` vs `… Offline Root CA`).
