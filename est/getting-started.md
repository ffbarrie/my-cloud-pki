# Getting started with EST

Enrollment over Secure Transport (RFC 7030) for leaf certificates from the
online issuing CA.

**This is preparation for future work.** Near-term lab enrollment is **CMP /
SCEP on EJBCA CE** ([ADR-0004](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md)).
EST must still be **built** later (companion front-end or Enterprise revisit).

Official Keyfactor references:

- https://docs.keyfactor.com/ejbca/latest/est
- https://docs.keyfactor.com/ejbca/latest/est-ra-mode-configuration

## Enrollment strategy

| Phase | Approach |
| ----- | -------- |
| **Now** | Path 1 — stay on CE; enroll with **CMP** and **SCEP** |
| **Later** | Build **EST** (required end-state); keep EJBCA as the issuing CA |

## Status on EJBCA Community (`keyfactor/ejbca-ce`)

**EST is not available in EJBCA Community Edition.**

On this lab stack (`keyfactor/ejbca-ce:latest`, EJBCA 9.3.x):

| Check | Result |
| ----- | ------ |
| Protocol toggle | `ejbca.sh config protocols enable EST` succeeds |
| Alias config | `ejbca.sh config est …` works (alias `est` configured) |
| Deployed WAR | **No `est.war`** in `ejbca.ear` (CE ships `cmp.war` / `scep.war`) |
| HTTP endpoint | `https://localhost:8443/.well-known/est/…` → **404** |

Keyfactor’s Community vs Enterprise matrix lists EST (and ACME) under Enterprise.

What *is* ready and shared with CMP/SCEP:

- Certificate profile **`MyCloudServer`**
- End entity profile **`MyCloudServerEE`**
- Example EST RA alias properties under [`aliases/`](aliases/) (for when EST exists)

## Prerequisites

- Issuing CA imported per [../issuing-ca/getting-started.md](../issuing-ca/getting-started.md)
- Profiles imported (or recreated) as below

## 1. Import TLS profiles

Profiles live in [`../issuing-ca/profiles/`](../issuing-ca/profiles/). They are
cloned from EJBCA’s `SERVER` template, with **serverAuth + clientAuth** EKUs so
reenroll / mTLS can work when EST is available.

```sh
# From repo root
docker compose exec -T ejbca bash -c 'mkdir -p /tmp/profiles-import && rm -rf /tmp/profiles-import/*'
docker compose cp issuing-ca/profiles/. ejbca:/tmp/profiles-import/
docker compose exec -T ejbca bash -lc \
  '/opt/keyfactor/bin/ejbca.sh ca importprofiles -d /tmp/profiles-import \
     --caname "My Cloud Issuing CA"'
```

If a profile name already exists, delete it in the Admin UI
(**CA Functions → Certificate Profiles** / **RA Functions → End Entity Profiles**)
before re-importing.

Expected profiles:

| Name | Type | Notes |
| ---- | ---- | ----- |
| `MyCloudServer` | Certificate profile | 2y validity; EKU serverAuth + clientAuth; SAN allowed |
| `MyCloudServerEE` | End entity profile | Required CN; optional DNS SAN; CA = My Cloud Issuing CA; token = User Generated |

After import, note the end-entity profile **numeric id** (Admin UI or
`config est updatealias` help text). The EST alias references that id.

## 2. EST alias (when EST servlet exists)

These steps succeed on CE for *configuration storage*, but enrollment will still
404 until an Enterprise (or otherwise EST-enabled) deployment provides
`est.war`.

```sh
# Lab-only RA credential — do not commit
mkdir -p est/artifacts
ESTUSER=estrauser
ESTPASS=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-18)
echo "$ESTUSER" > est/artifacts/est-ra.user
echo "$ESTPASS" > est/artifacts/est-ra.pass
chmod 600 est/artifacts/est-ra.*

# Look up MyCloudServerEE id after import (example: 928545354)
EEPROFILE_ID=<id-from-admin-ui-or-export-filename>

docker compose exec -T ejbca bash -lc \
  '/opt/keyfactor/bin/ejbca.sh config protocols enable EST'

# Copy and fill aliases/est.properties.example, then:
docker compose cp est/aliases/est.properties ejbca:/tmp/est.properties
docker compose exec -T ejbca bash -lc \
  '/opt/keyfactor/bin/ejbca.sh config est addalias --alias est
   /opt/keyfactor/bin/ejbca.sh config est uploadfile --alias est --file /tmp/est.properties
   /opt/keyfactor/bin/ejbca.sh config est dumpalias --alias est'
```

Default alias name `est` maps to:

```text
https://<host>:8443/.well-known/est/<operation>
```

The `keyfactor/ejbca-ce` image uses a **single TLS port 8443 with optional client
certificates**, so initial enroll and reenroll share that port (no 8442).

## 3. Verify (requires EST-capable EJBCA)

Trust the HTTPS listener CA (ManagementCA on a default CE quickstart), not the
PKI issuing CA, for TLS to the EST URL:

```sh
docker compose exec -T ejbca bash -lc \
  '/opt/keyfactor/bin/ejbca.sh ca getcacert --caname ManagementCA -f /tmp/ManagementCA.cacert.pem'
docker compose cp ejbca:/tmp/ManagementCA.cacert.pem est/artifacts/ManagementCA.cacert.pem

CACERT=est/artifacts/ManagementCA.cacert.pem
ESTUSER=$(cat est/artifacts/est-ra.user)
ESTPASS=$(cat est/artifacts/est-ra.pass)
BASE=https://localhost:8443/.well-known/est

# CA certs (PKCS#7)
curl -sk --cacert "$CACERT" -o est/artifacts/cacerts.p7 "$BASE/cacerts"

# Initial enroll (RA username/password)
openssl req -nodes -newkey rsa:2048 -keyout est/artifacts/device.key \
  -out est/artifacts/device.csr -outform DER -subj '/CN=est-test.my.cloud'
openssl base64 -in est/artifacts/device.csr -out est/artifacts/device.b64
chmod 600 est/artifacts/device.key

curl -sk --cacert "$CACERT" --user "$ESTUSER:$ESTPASS" \
  --data @est/artifacts/device.b64 -o est/artifacts/device-p7.b64 \
  -H 'Content-Type: application/pkcs10' \
  -H 'Content-Transfer-Encoding: base64' \
  "$BASE/simpleenroll"

openssl base64 -d -in est/artifacts/device-p7.b64 -out est/artifacts/device-p7.der
openssl pkcs7 -inform DER -in est/artifacts/device-p7.der -print_certs \
  -out est/artifacts/device-cert.pem
openssl x509 -in est/artifacts/device-cert.pem -noout -subject -issuer
```

Reenroll always uses the existing client certificate (mTLS) against
`$BASE/simplereenroll`.

On CE today, expect **HTTP 404** from the curl steps above.

## Near-term enrollment (path 1 — do this instead of EST for now)

| Protocol | CE image | Notes |
| -------- | -------- | ----- |
| CMP | Yes (`cmp.war`) | Servlet at `/ejbca/publicweb/cmp` — **next to document/enable** |
| SCEP | Yes (`scep.war`) | Under `/ejbca/publicweb/apply/scep/…` — **next to document/enable** |
| Admin / CLI batch | Yes | Already used in issuing-ca getting-started |
| ACME | No (Enterprise) | Out of scope for now |

## Building EST later

Track under this directory. Likely options (pick in a follow-up ADR when ready):

1. **Companion EST front-end** — clients speak EST; the service asks EJBCA
   (WS/REST/CMP/etc.) to issue.
2. **EJBCA Enterprise** — native `est.war` if licensing becomes acceptable.

Until one of those ships, treat EST curl steps above as **not expected to
succeed** on CE.

## Security notes

- Treat `est/artifacts/est-ra.*` as secrets; they are gitignored.
- The EST RA username has broad RA rights for that alias—lab only.
- Do not commit ManagementCA private material; the PEM from `getcacert` is the
  public TLS trust anchor only.
