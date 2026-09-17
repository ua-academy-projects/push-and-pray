# History role

Pulls and starts only the OilScope `history` Compose service, then verifies its
local health endpoint.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- Dynamic inventory provides the selected database and queue connection metadata.
- Database is healthy and migrated.

The deployment workflow retrieves `POSTGRES_PASSWORD` from Secret Manager and
passes it as `history_postgres_password`. This role does not retrieve or store
secret values.

## Variables

- `history_postgres_password`: password injected by the deployment workflow.
- `history_queue_backend`: `pgmq` or `rabbitmq`.
- `history_rabbitmq_url`: required only for RabbitMQ.

## Example

```yaml
- name: Deploy History
  hosts: history
  become: true
  roles:
    - role: oilscope.platform.history
      vars:
        history_postgres_password: "{{ resolved_secrets.POSTGRES_PASSWORD }}"
```

The role uses `docker compose pull history` and
`docker compose up --detach --no-deps history`.
