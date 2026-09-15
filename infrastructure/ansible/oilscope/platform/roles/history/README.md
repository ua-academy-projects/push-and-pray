# History role

Pulls and starts only the OilScope `history` Compose service, then verifies its
local health endpoint.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The inventory built by `oilscope_cloud` supplies `oilscope_database_host`,
  `oilscope_queue_backend` and the related group variables; the database is
  healthy and migrated.

The deployment workflow retrieves `POSTGRES_PASSWORD` and, in managed mode,
`RABBITMQ_PASSWORD` from the secret store and passes them as
`history_postgres_password` and `history_amqp_password`. This role does not
retrieve or store secret values.

## Variables

- `history_postgres_password`: password injected by the deployment workflow.
- `history_amqp_password`: broker password, required when
  `history_queue_backend` is `amqp`.
- `history_database_host`, `history_database_port`, `history_database_sslmode`:
  where PostgreSQL is; default to the group variables the inventory derives
  from the database mode.
- `history_queue_backend`: `pgmq` or `amqp`; `history_amqp_host`,
  `history_amqp_port`, `history_amqp_user`, `history_amqp_vhost` describe the
  broker for the latter. All default to the group variables.

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
