# EST

Enrollment over Secure Transport (EST) — **future work**.

## Decision

Per [ADR-0004](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md):

1. **Now (path 1):** Stay on EJBCA Community. Automated enrollment uses
   **CMP and SCEP** (native CE servlets). See
   [../issuing-ca/getting-started.md](../issuing-ca/getting-started.md).
2. **Later:** **Build EST**. CE does not ship `est.war`, so native
   `/.well-known/est/…` is unavailable. EST remains a required end-state
   protocol; implement it as a companion front-end that issues through EJBCA,
   or revisit EJBCA Enterprise in a follow-up ADR.

This directory holds preparation notes, alias examples, and verification
commands for when EST exists. It is **not** a working enrollment service on
`keyfactor/ejbca-ce` today.

TLS profiles shared with CMP/SCEP live under
[`../issuing-ca/profiles/`](../issuing-ca/profiles/).

## Layout

```text
est/
├── README.md
├── getting-started.md    # CE gap, profiles, future EST alias + curl verify
├── aliases/              # EST alias property examples (for later)
└── artifacts/            # Local only (gitignored)
```

## Related

- [getting-started.md](getting-started.md)
- [../issuing-ca/getting-started.md](../issuing-ca/getting-started.md)
- Keyfactor EST: https://docs.keyfactor.com/ejbca/latest/est
