# Getting started with SCEP (EJBCA CE)

Native SCEP on EJBCA Community — **CA / Client mode** only. There is no separate
SCEP companion process (unlike EST).

Per [ADR-0004](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md),
CMP and SCEP are CE-native enrollment paths. On CE, SCEP means **pre-registered
end entities** (Client/CA mode). **SCEP RA mode** (create EE on enroll, static RA
password or Intune) is Enterprise; the CE image accepts `operationmode=ra` in the
CLI but rejects PKCSReq with:
`SCEP RA mode is enabled, but not included in the community version of EJBCA`.

## Architecture

```text
Client --SCEP--> ejbca:8080 /publicweb/apply/scep/mycloud/pkiclient.exe
                      |
                      v
              My Cloud Issuing CA  (pre-created end entity + challengePassword)
```

| Item | Lab value |
| ---- | --------- |
| Alias | `mycloud` |
| URL | `http://localhost:8080/ejbca/publicweb/apply/scep/mycloud/pkiclient.exe` |
| Mode | `ca` (Client mode) |
| Auth | CSR `CN` = EJBCA username; CSR `challengePassword` = EE enrollment code |
| Profiles | `MyCloudServer` / `MyCloudServerEE` |
| GetCACert `message=` | `My Cloud Issuing CA` (**URL-encoded**) |

## Prerequisites

- Issuing CA imported; crypto token active after any EJBCA restart
- Profiles `MyCloudServer` / `MyCloudServerEE` imported
- Docker Compose stack up (`docker compose up -d`)

## 1. One-time setup

```sh
./scripts/ejbca-setup-scep.sh
```

This configures alias `mycloud` in CA mode (`includeca=true`,
`returnCaChainInGetCaCert=false` for classic `application/x-x509-ca-cert` clients),
writes `scep/artifacts/scep-challenge.pass`, and caches the issuing CA cert.

## 2. Register a device (per enrollment)

```sh
./scripts/scep-add-ee.sh device01.my.cloud
```

Re-run after a successful enroll if you need another certificate for the same CN
(status becomes GENERATED; the helper revokes/deletes and recreates).

## 3. Point your SCEP client

| Setting | Value |
| ------- | ----- |
| Server URL | `http://<host>:8080/ejbca/publicweb/apply/scep/mycloud/pkiclient.exe` |
| CA identifier | `My Cloud Issuing CA` (encode spaces as `%20`) |
| Challenge | contents of `scep/artifacts/scep-challenge.pass` (or per-EE password) |
| CSR subject | `CN=<same as username>` |
| Key type | **RSA** (SCEP message encryption requires RSA) |

`scep/artifacts/client.env` is generated for convenience (mode `600`).

### GetCACert tip

Some clients (e.g. sscep) put the CA identifier in `message=` **without** URL-encoding.
A space in `My Cloud Issuing CA` then yields HTTP 400. Prefer:

- omitting the identifier when the client allows it **and** the server can default
  the CA (RA mode only — not available on CE), or
- fetching the CA cert with a properly encoded URL / using `scep/artifacts/ca.crt`.

## 4. Smoke test

```sh
./scripts/scep-smoke.sh
```

Always checks GetCACaps + GetCACert. Full PKCSReq enroll runs if `sscep` is on
`PATH` or `SSCEP` points at a binary
([certnanny/sscep](https://github.com/certnanny/sscep)).

## Security notes

- Do not expose EJBCA `:8080` SCEP to untrusted networks without TLS termination
  and tighter enrollment controls.
- Lab challenge in `scep-challenge.pass` is a shared secret for convenience; use a
  unique password per EE in anything beyond smoke tests.
- After `docker compose restart ejbca`, reactivate the imported crypto token before
  enrolling (see issuing-ca getting-started).

---

## Structural differences vs Microsoft NDES / SCEP

Notes from standing up this lab against the usual Active Directory Certificate
Services + NDES shape (and Intune’s NDES/SCEP usage). Useful when verifying a
client that was written or tested against Microsoft.

| Concern | Microsoft NDES (+ ADCS) | This lab (EJBCA CE SCEP) |
| ------- | ----------------------- | ------------------------ |
| **Deployment shape** | Separate **NDES** role (IIS) in front of a CA; NDES is the RA | SCEP servlet **in-process** on the issuing CA — no NDES-equivalent service |
| **Enrollment mode** | RA-style: challenge (or Intune) authorizes issuance against a **template**; device account often not pre-created the same way | **CA/Client mode only on CE**: end entity must exist **before** PKCSReq; CN + challengePassword authenticate |
| **RA mode / dynamic EE** | Normal NDES behavior | **Enterprise** on EJBCA (`operationmode=ra`). CE configures it but refuses PKCSReq at runtime |
| **URL** | Typically `http://<ndes>/certsrv/mscep/mscep.dll` (or mscep_admin for challenges) | `…/ejbca/publicweb/apply/scep/<alias>/pkiclient.exe` (Cisco-era path name kept by EJBCA) |
| **Policy object** | ADCS **certificate template** (+ NDES service account / enrollment agent) | EJBCA **certificate + end-entity profiles** bound at EE creation (here: `MyCloudServer` / `MyCloudServerEE`) |
| **Challenge password** | NDES admin pages issue **one-time** (or configured) passwords; Intune supplies dynamic challenges to NDES | Static **EE enrollment code** (lab: `scep-challenge.pass`). No NDES “password page” |
| **Intune** | Intune → NDES → ADCS is the common Microsoft path | EJBCA **Intune SCEP validation** is Enterprise RA mode — out of scope on CE |
| **GetCACert response** | Usually a single CA cert, MIME `application/x-x509-ca-cert` | Same when `returnCaChainInGetCaCert=false` (lab default). If `true`, EJBCA may return a PKCS#7 chain as `application/x-x509-ca-ra-cert` (RFC 8894-style) — breaks some classic clients |
| **CA identifier** | Often empty or a simple CA name; single-CA deployments are common | Multi-CA aware: pass `message=<CA name>` URL-encoded, or rely on alias/CA naming rules |
| **RA encryption / signing certs** | NDES uses enrollment-agent / RA certificates distinct from the CA in many setups | Default: **CA key** encrypts/signs SCEP messages. Separate RA keys exist as an option (FIPS/HSM cases) |
| **Renewal** | NDES/Intune renewal flows are first-class in Microsoft deployments | EJBCA **client certificate renewal** over SCEP is Enterprise; CE lab expects re-register EE + new enroll |
| **Transport** | Often HTTP internally; TLS via IIS reverse proxy in hardened setups | Lab uses cleartext HTTP on Compose publish port **8080** — treat as lab-only |
| **Identity backing** | Active Directory (templates, permissions, device/user objects) | EJBCA end entities in PostgreSQL; no AD dependency |

### Practical client-verification implications

1. If your client assumes **NDES RA behavior** (one shared challenge mints any CN without
   pre-registration), it will **not** match this CE lab — pre-create the EE with
   `scep-add-ee.sh` (or move to EJBCA Enterprise RA mode later).
2. If your client was tested against **Intune + NDES**, challenge and approval live in
   Intune, not in a local `challengePassword` file — different trust model than CE CA mode.
3. Prefer **RSA** keys; SCEP’s legacy encryption model does not work with EC-only keys
   the way EST/CMP can.
4. Watch **GetCACert MIME and encoding**: Microsoft stacks are usually tolerant of the
   single-cert response; strict or old clients may choke on PKCS#7 CA chains or
   unencoded spaces in `message=`.
