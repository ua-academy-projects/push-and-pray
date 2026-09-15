# Database migrations role

Runs the one-shot `migrate` service from the infra VM's Compose definition,
which applies the SQL under `database/migrations` with `petroscope-migrate`.
The same role serves both database modes; only the target differs:

- self-hosted: the PostgreSQL container on the same VM, reached as `postgres`
  over the Compose network;
- managed: the Cloud SQL or RDS endpoint, over TLS.

One machine owns the schema either way. The migrations are idempotent and the
ones that need an extension the managed services lack - PGMQ, and pg_cron for
the session cleanup - skip themselves on such a server.

## Requirements

Docker with the Compose plugin, the Compose definition installed by
`oilscope.platform.compose_project`, and registry credentials from
`oilscope.platform.registry_auth`. In managed mode the VM must be able to reach
the database endpoint, which the Terraform firewall rules allow.

## Required variables

- `database_migrations_postgres_password`: password of the application role.
  Passed to the job through the environment and marked `no_log`.

## Optional variables

- `database_migrations_host`, `database_migrations_port`,
  `database_migrations_sslmode`: where to connect; default to `postgres`,
  `5432` and `disable`, the self-hosted case.
- `database_migrations_postgres_user`, `database_migrations_postgres_name`:
  both default to `oil_tracker`.
- `database_migrations_compose_project_dir`, `database_migrations_compose_file`,
  `database_migrations_compose_project_name`: Compose location; default to
  `/opt/oilscope/app`, its `compose.yaml` and `petroscope`.
- `database_migrations_compose_environment`: additional non-secret Compose
  environment.

## Example

```yaml
- role: oilscope.platform.database_migrations
  vars:
    database_migrations_postgres_password: "{{ resolve_secrets_result.POSTGRES_PASSWORD }}"
    database_migrations_host: "{{ oilscope_database_host if oilscope_database_managed else 'postgres' }}"
    database_migrations_sslmode: "{{ oilscope_database_sslmode }}"
```

## License

GPL-2.0-or-later
