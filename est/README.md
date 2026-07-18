# EST

Companion **Enrollment over Secure Transport (EST)** front-end for My Cloud PKI.

Clients speak RFC 7030 to this service; certificates are issued by **EJBCA Community**
via **CMP RA mode** (`p10cr` over the internal `mycloud` alias).

## MVP scope

| Operation | Status |
| --------- | ------ |
| `GET /.well-known/est/cacerts` | Implemented |
| `POST /.well-known/est/simpleenroll` | Implemented (HTTP Basic RA) |
| `POST /.well-known/est/simplereenroll` | **Deferred v1.1** (returns HTTP 501) |

## Deferred: simplereenroll (v1.1) — do not forget

MVP intentionally ships **without** certificate renewal over EST.

- **Why:** CE end-entity status lifecycle, mTLS trust design, and renewal-aware backend
  wiring need a dedicated v1.1 pass (see [getting-started.md](getting-started.md)).
- **MVP behavior:** `/simplereenroll` returns **501 Not Implemented** with a pointer to docs.
- **Do not** treat EST as “complete” until v1.1 acceptance criteria pass.

Native EJBCA CE `est.war` / `/.well-known/est` on port 8443 remains unavailable; this
companion service is the lab EST surface.

## Layout

```text
est/
├── README.md
├── getting-started.md
├── Dockerfile
├── go.mod
├── cmd/est-server/          # EST HTTP service
├── internal/                # config, CMP backend, handlers
├── aliases/                 # Enterprise-native EST alias example (unused on CE)
└── artifacts/             # Local secrets, TLS, smoke output (gitignored)
```

## Quick start

After [issuing-ca/getting-started.md](../issuing-ca/getting-started.md):

```sh
./scripts/ejbca-setup-est.sh
docker compose up -d est
./scripts/est-smoke.sh
```

Default EST URL: `https://localhost:8444/.well-known/est`

## Related

- [getting-started.md](getting-started.md)
- [ADR-0004](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md)
- [../scripts/ejbca-setup-est.sh](../scripts/ejbca-setup-est.sh)
