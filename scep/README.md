# SCEP

Native **Simple Certificate Enrollment Protocol** on **EJBCA Community** (no companion
service). Clients talk to EJBCA’s SCEP servlet; certificates are issued by
**My Cloud Issuing CA** using profiles `MyCloudServer` / `MyCloudServerEE`.

## Lab scope (CE)

| Capability | Status |
| ---------- | ------ |
| SCEP CA / Client mode | Supported on CE — pre-register end entity, enroll with `challengePassword` |
| SCEP RA mode | **Enterprise only** — CLI accepts `operationmode=ra`, but PKCSReq is rejected at runtime on CE |
| Client certificate renewal | Enterprise |
| Microsoft Intune auth | Enterprise |

## Layout

```text
scep/
├── README.md
├── getting-started.md      # Setup, client notes, NDES differences
└── artifacts/              # Challenge secret, CA certs, smoke output (gitignored)
```

## Quick start

After [issuing-ca/getting-started.md](../issuing-ca/getting-started.md) and profile import:

```sh
./scripts/ejbca-setup-scep.sh
./scripts/scep-add-ee.sh your-device.my.cloud
./scripts/scep-smoke.sh   # optional; full enroll needs sscep
```

Default URL:

`http://localhost:8080/ejbca/publicweb/apply/scep/mycloud/pkiclient.exe`

## Related

- [getting-started.md](getting-started.md)
- [ADR-0004](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md)
- [../scripts/ejbca-setup-scep.sh](../scripts/ejbca-setup-scep.sh)
