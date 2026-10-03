# Azure database module

Creates the managed PostgreSQL of one environment: an Azure Database for
PostgreSQL flexible server without any network presence of its own, the
application database, and the private endpoint the workloads reach it through.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-database` | The flexible server; public access off |
| `azure.extensions` | The extensions the migrations create - `HSTORE`, `PGCRYPTO` |
| `shared_preload_libraries` | `pg_stat_statements`, and deliberately not `pg_cron` |
| `database.name` | The application database |
| `<prefix>-database-endpoint` | Private endpoint in the database subnet, interface `<prefix>-database-endpoint-nic` |
| `allow-database` | Rule in the network's security group: the port from fetcher, history, ui and infra to the database subnet |
| `<prefix>-database-lock` | `CanNotDelete` lock, only with `deletion_protection` |

## How it maps onto the other clouds

The shape is GCP's: the server lives outside the network and is reached
through an address in the database subnet - a private endpoint here, a Private
Service Connect forwarding rule there. That address is what the workloads see
as `DATABASE_HOST`, and what the Ansible inventory looks up by the endpoint's
name. There is no private DNS zone, the same trade-off as on GCP: clients use
`sslmode=require` and do not verify the certificate.

The filtering is AWS's: the security rule admits the client scopes, as the RDS
security group admits the client groups. It targets the subnet, because a
private endpoint cannot join an application security group.

## What Azure insists on

- **Extensions must be allow-listed** in `azure.extensions`, or `CREATE
  EXTENSION` fails whoever runs it.
- **pg_cron stays out of `shared_preload_libraries`.** Migration `003` creates
  it wherever it is preloaded, and Azure lets it into the `postgres` database
  only - the migration would fail in the application's. Sessions live in Redis
  in managed mode, so nothing needs it. The parameter is static: setting it
  restarts the server.
- **Storage comes in steps** starting at 32 GiB; `storage_gb` is rounded up.
- **Backups are kept 7 to 35 days** and cannot be turned off, so
  `backup_retention_days` below 7 - including 0 - becomes 7.
- **The server listens on 5432**, whatever `service_ports.postgresql` says;
  the variable is validated against it.
- **The name is global**: `<prefix>.postgres.database.azure.com` must be free
  across all of Azure.
- **No deletion protection flag**: a management lock refuses the delete, and
  must be removed before the server can go.

## The password

The server will not be created without an administrator password. It gets a
random one from an ephemeral resource, through a write-only argument, so it is
in neither the plan nor the state - and nobody knows it.
`managed_database_credentials` then sets the password the workloads read from
Key Vault. The administrator login is `database.username`, the application
role, as on AWS; Azure cannot rename it later.

## Outputs

| Name | Description |
| --- | --- |
| `host` | Address of the private endpoint |
| `port`, `name` | Port and application database |
| `server_name`, `fqdn` | The server, for the API and the CLI |
| `endpoint_name` | The private endpoint the inventory looks up |

## License

GPL-2.0-or-later
