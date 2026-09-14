# GCP database

Creates private Cloud SQL PostgreSQL when `default_cloud` is `gcp` and
`default_db` is `cloud`. Inputs are `config` and `network`, like the AWS database
module. Disabled mode creates no database resources and returns null.

The module reads every sizing field directly from
`config.database_profile_map[config.database_profile].gcp`: tier, edition,
engine version, disk size/type/autoresize, availability, and backup count.
There are no fallback profile values. Region and primary zone come from the
selected region mapping. The economy configuration uses PostgreSQL 18,
`db-f1-micro`, Enterprise, 10 GiB SSD, no disk autoresize, ZONAL, and one backup.
This is an economy profile, not a GCP Free Tier guarantee. Other tier/edition
combinations must be supported by Cloud SQL; Terraform does not replace them.

The GCP network module reserves the explicit
`clouds.gcp.cloud_sql_network.allocated_cidr` for private services access.
Its output carries a dependency on service networking, so the database waits
for the connection. Choose a range that does not overlap existing subnets or
connected networks. This range is dedicated to this database deployment;
the firewall denies other traffic to it. Only Fetcher and History network
tags may connect on Cloud SQL's fixed PostgreSQL port 5432 — UI's session
store moved to Redis, so it has no PostgreSQL connection and is not in this
allow rule.

The instance has no public IP. TLS is required with a Google-managed shared
CA and automatic certificate rotation during maintenance. An exact-host private
DNS zone maps the instance's PSA certificate DNS name to its private address.
The `connection` output includes `verify-full` and Google's regional shared-CA
bundle URL. Deployment must download and mount that bundle and configure
clients; `server_ca_cert` is not treated as a complete shared-CA trust bundle.

Terraform creates `oil_tracker` and a built-in `oil_tracker_admin` user. A
32-character generated password is stored in a dedicated Secret Manager secret
as JSON containing `username` and `password`. Only the secret resource ID is
exported. The password is also present in sensitive Terraform state; restrict
state access. Do not use this administrator for normal application traffic.
Ansible now creates runtime roles through `database_migrate`, using controller
operator credentials to retrieve secrets and short-lived containers on History
to run SQL. The operator needs secret read access; no administrator-secret IAM
grant is added to the VM. The module intentionally
does not grant application VMs access to the administrator secret.

Backups are enabled with the JSON retention count. PITR is enabled for REGIONAL
availability, which requires it, and disabled for the economy ZONAL profile.
Both deletion-protection controls, final backups, and retained backups on delete
are disabled, matching the agreed disposable database policy. Database/user
resources use `ABANDON` so their individual deletion cannot fail on connections
or object ownership during instance teardown; destroying the instance still
removes them. Removing only these child resources would leave them on a retained
instance. APIs stay enabled on module removal because they are project-wide.
Deleting private services access can require a later retry after Cloud SQL has
finished releasing its service-side networking; do not force removal while
another service still uses it.

The root exports `gcp_database_connection`. This module provisions infrastructure;
it does not run SQL migrations, move existing data, or deploy RabbitMQ/Redis.
No tests are included per the user's decision. Static Terraform validation does
not establish live connectivity, regional capacity, DNS/TLS behavior, or a safe
mode switch.

References: [private services access](https://cloud.google.com/sql/docs/postgres/configure-private-services-access),
[shared CA and hostname verification](https://docs.cloud.google.com/sql/docs/postgres/authorize-ssl),
[regional CA bundles](https://docs.cloud.google.com/sql/docs/postgres/manage-ssl-instance#download-ca-bundles),
[Cloud SQL user state handling](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_user).
