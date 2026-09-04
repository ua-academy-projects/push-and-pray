# UI role

Pulls and starts only the OilScope `ui` Compose service, then waits for its
existing Docker health check.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The dynamic inventory contains hosts in the `database` and `history`
  groups, each with an `internal_ip` variable.
- Database is healthy and migrated, and History is healthy.

The role declares and retrieves `POSTGRES_PASSWORD` before starting UI.

## Variables

- `ui_postgres_password`: resolved from the role declaration unless passed explicitly.
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
