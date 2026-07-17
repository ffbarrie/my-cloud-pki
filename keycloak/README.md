# Keycloak

Identity integration used by PKI enrollment or administrative flows.

Keycloak does not replace the issuing CA. EJBCA remains the CA
([ADR-0004](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0004-ejbca-online-issuing-ca.md));
Keycloak is planned for admin / enrollment identity once the online CA is
stable.

Keycloak should use **PostgreSQL**, consistent with
[ADR-0005](https://github.com/ffbarrie/my-cloud/blob/main/docs/adr/0005-postgresql-datastore.md).
Give Keycloak its own database on Postgres—do not share the EJBCA schema.

See [../issuing-ca/](../issuing-ca/).
