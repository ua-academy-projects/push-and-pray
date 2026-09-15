# UI role

Pulls and starts only the OilScope `ui` Compose service, then waits for its
existing Docker health check.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The inventory built by `oilscope_cloud` contains a host in the `history`
  group with an `internal_ip` variable and supplies `oilscope_database_host`,
  `oilscope_session_backend` and the related group variables.
- Database is healthy and migrated, and History is healthy.

The deployment workflow retrieves `POSTGRES_PASSWORD` and, in managed mode,
`REDIS_PASSWORD` and passes them as `ui_postgres_password` and
`ui_redis_password`. This role does not retrieve or store secret values.

## Variables

- `ui_postgres_password`: password injected by the deployment workflow.
- `ui_redis_password`: cache password, required when `ui_session_backend` is
  `redis`.
- `ui_database_host`, `ui_database_port`, `ui_database_sslmode`: where
  PostgreSQL is; default to the group variables the inventory derives from
  the database mode.
- `ui_session_backend`: `postgres` or `redis`; `ui_redis_host` and
  `ui_redis_port` describe the cache for the latter. All default to the group
  variables.
- `ui_history_url`: where the History API is; defaults to the `history` host's
  internal address.
- `ui_health_retries` and `ui_health_delay`: Docker health-check polling
  controls, defaulting to 30 attempts every 2 seconds.

## Example

```yaml
- name: Deploy UI
  hosts: ui
  become: true
  roles:
    - role: oilscope.platform.ui
      vars:
        ui_postgres_password: "{{ resolved_secrets.POSTGRES_PASSWORD }}"
```

The role gets `DATABASE_HOST` from the first `database` host's `internal_ip`
and forms `HISTORY_SERVICE_URL` from the first `history` host's `internal_ip`.
It uses `docker compose pull ui` and
`docker compose up --detach --no-deps ui`.
