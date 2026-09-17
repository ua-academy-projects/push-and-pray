# History role

Pulls and starts only the OilScope `history` Compose service, then verifies its
local health endpoint.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The dynamic cloud inventory contains one host in the `infrastructure` group with
  an `internal_ip` variable.
- Database is healthy and migrated.

The deployment workflow retrieves `POSTGRES_PASSWORD` from Secret Manager and
passes it as `history_postgres_password`. This role does not retrieve or store
secret values.

## Variables

- `history_postgres_password`: password injected by the deployment workflow.
- `history_messaging_backend`: `pgmq` for a self-managed database or `rabbitmq`
  for a managed database; defaults to `pgmq`.
- `history_database_host`: PostgreSQL host passed to Compose; defaults to
  `postgres`.
- `history_database_sslmode`: PostgreSQL SSL mode; the deployment uses `require`
  for an AWS managed database and `disable` otherwise.
- `history_rabbitmq_url`: RabbitMQ connection URL required for a managed
  database.
- `history_cloud_sql_connection_name`: Cloud SQL instance connection name used
  by the proxy for a GCP managed database.
- `history_docker_config_dir`: transient Docker client configuration directory;
  defaults to `/run/oilscope/docker-auth`.
- `history_health_retries` and `history_health_delay`: health polling controls,
  defaulting to 30 attempts every 2 seconds.

## Example

```yaml
- name: Deploy History
  hosts: history
  become: true
  roles:
    - role: oilscope.platform.history
      vars:
        history_postgres_password: "{{ resolved_secrets.POSTGRES_PASSWORD }}"
        history_database_host: "{{ hostvars[groups['infrastructure'][0]].internal_ip }}"
```

The role uses `docker compose pull history` and
`docker compose up --detach --no-deps history`.

The health wait accepts the current backend-neutral `messaging` response and
the legacy self-managed database image response containing
`pgmq_consumer: ready`.
