# UI role

Pulls and starts only the OilScope `ui` Compose service, then waits for its
existing Docker health check.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The dynamic GCP inventory contains hosts in the `database` and `history`
  groups, each with an `internal_ip` variable.
- Database is healthy and migrated, and History is healthy.

The deployment workflow retrieves `POSTGRES_PASSWORD` and passes it as
`ui_postgres_password`. This role does not retrieve or store secret values.

## Variables

- `ui_application_image_tag`: UI image Git SHA.
- `ui_postgres_image`: PostgreSQL image required to parse the shared Compose
  file.
- `ui_postgres_password`: password injected by the deployment workflow.
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
        ui_application_image_tag: "0123456789abcdef0123456789abcdef01234567"
        ui_postgres_image: "ghcr.io/example/database@sha256:..."
        ui_postgres_password: "{{ resolved_secrets.POSTGRES_PASSWORD }}"
```

The role gets `DATABASE_HOST` from the first `database` host's `internal_ip`
and forms `HISTORY_SERVICE_URL` from the first `history` host's `internal_ip`.
It uses `docker compose pull ui` and
`docker compose up --detach --no-deps ui`.
