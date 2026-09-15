# History role

Pulls and starts only the OilScope `history` Compose service, then verifies its
local health endpoint.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The dynamic inventory contains one host in the `database` group with an `internal_ip` variable.
- Database is healthy and migrated.

History always receives PostgreSQL credentials. Self-hosted mode consumes PGMQ on the
infra PostgreSQL instance. Managed mode consumes RabbitMQ on the infra VM and writes to
private RDS or Cloud SQL with `sslmode=require`. The role does not retrieve or store
secret values itself.

## Variables

- `history_postgres_password`: password injected by the deployment workflow.

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
