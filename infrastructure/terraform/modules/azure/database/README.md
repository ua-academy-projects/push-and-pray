# Azure database module

PostgreSQL Flexible Server with VNet integration, active only when
`default_cloud` is `azure` **and** `managed_database` is `true`. In application mode
it creates nothing and `connection` is null, exactly as the RDS and Cloud SQL
modules behave.

## Private networking

The server sits in the delegated subnet the network module created, resolves
through the linked private DNS zone, and has `public_network_access_enabled =
false`. The server resource depends on the zone *link*, not just the zone ID —
creating it before the link exists fails.

`host` is the server's own FQDN inside that zone. Nothing here publishes an IP
address or an alias, because `sslmode = verify-full` checks the certificate
against the name actually used to connect.

## Trust material

AWS has one bundle URL and so does Cloud SQL. Azure has neither: Flexible Server
presents certificates chaining to **DigiCert Global Root G2** or **Microsoft RSA
Root CA 2017**, and there is no maintained endpoint serving both in one PEM.

So the connection output reports `ca_bundle_url = null` and lists both roots in
`ca_certificate_urls`. Deployment assembles one PEM from that list and mounts it
at the existing path; it must not guess a single-URL equivalent.

## Profile

`database_profile_map.<profile>.azure`:

| Key | Notes |
| --- | --- |
| `sku_name` | e.g. `B_Standard_B1ms`; burstable tiers support no high availability |
| `postgres_version` | Major version as a string |
| `storage_mb` | 32768 is the smallest Flexible Server size |
| `storage_tier` | Must be valid for `storage_mb` |
| `backup_retention_days` | 7–35. There is no one-day RDS equivalent |
| `high_availability` | `Disabled`, `SameZone` or `ZoneRedundant` |
| `standby_availability_zone` | Required by `ZoneRedundant`, null otherwise |

Verify the chosen major version and SKU are offered in the target location
before applying; provider support is not the same as regional availability.

## Administrator credential

`random_password` generates it, the server takes it, and the secrets module's
vault stores it as `{"username": ..., "password": ...}` under
`<prefix>-database-admin`. The output carries only the versionless URI.

This means the administrator password is in Terraform state — the same
trade-off Cloud SQL already makes here. Treat state and saved plans as secret.

Azure's administrator is **not** a PostgreSQL superuser. Check the existing role
and grant SQL against that before assuming a migration that works on RDS works
here.

## Destruction

`require_secure_transport` stays on, deletion protection is not set, and no
final backup is retained: a mode switch intentionally discards this database.
Azure keeps a dropped server recoverable for a few days and recommends
restoring under a *different* name, so a name is not guaranteed to be
immediately reusable.
