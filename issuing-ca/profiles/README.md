# Issuing CA profiles (EJBCA)

Exported certificate and end-entity profiles for My Cloud leaf TLS.

| File | Profile |
| ---- | ------- |
| `certprofile_MyCloudServer-*.xml` | Certificate profile `MyCloudServer` |
| `entityprofile_MyCloudServerEE-*.xml` | End entity profile `MyCloudServerEE` |

## Contents (lab defaults)

- **MyCloudServer** — cloned from EJBCA `SERVER`; validity `2y`; EKU
  `serverAuth` + `clientAuth` (clientAuth added for EST reenroll / mTLS).
- **MyCloudServerEE** — required CN; optional DNS SAN; available CA
  `My Cloud Issuing CA`; default certificate profile `MyCloudServer`;
  token User Generated.

## Import

```sh
docker compose exec -T ejbca bash -c 'mkdir -p /tmp/profiles-import && rm -rf /tmp/profiles-import/*'
docker compose cp issuing-ca/profiles/. ejbca:/tmp/profiles-import/
docker compose exec -T ejbca bash -lc \
  '/opt/keyfactor/bin/ejbca.sh ca importprofiles -d /tmp/profiles-import \
     --caname "My Cloud Issuing CA"'
```

Fixed built-in profiles (`SERVER`, `ENDUSER`, …) are not exported. Delete a
custom profile in the Admin UI before re-importing the same name.

See [../est/getting-started.md](../est/getting-started.md) for EST alias wiring.
