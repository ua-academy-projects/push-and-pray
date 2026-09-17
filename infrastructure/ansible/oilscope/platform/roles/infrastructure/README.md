# Infrastructure role

Starts the infrastructure services required by the selected database
architecture and applies the database migrations.

For a self-managed database, the role starts PostgreSQL. For a managed database,
it starts RabbitMQ and Redis, plus the Cloud SQL Auth Proxy for GCP. The migration
job uses either the local PostgreSQL service or the managed PostgreSQL endpoint.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed by the
  `oilscope.platform.compose_project` role.
- `compose_project_config` is loaded from the project configuration.
- The required secrets have been resolved for the infrastructure VM.

## Variables

- `infrastructure_postgres_password`: PostgreSQL password injected by the
  deployment workflow.
- `infrastructure_rabbitmq_password` and `infrastructure_redis_password`:
  passwords required for a managed database deployment.
- `infrastructure_internal_ip`: private address on which infrastructure
  services listen.
- `infrastructure_database_host`: PostgreSQL host used by the migration job;
  defaults to `postgres`.
- `infrastructure_database_sslmode`: PostgreSQL SSL mode; defaults to `disable`.
- `infrastructure_cloud_sql_connection_name`: Cloud SQL instance connection name
  used by the proxy for a GCP managed database.
- `infrastructure_compose_project_dir`, `infrastructure_compose_file`, and
  `infrastructure_compose_project_name`: Compose location and project settings.
- `infrastructure_docker_config_dir`: transient Docker client configuration
  directory; defaults to `/run/oilscope/docker-auth`.

The role waits for RabbitMQ and Redis when using a managed database, then runs
the one-shot `migrate` service. Running the role again reconciles the selected
services and reapplies only pending migrations.

## License

GPL-2.0-or-later
