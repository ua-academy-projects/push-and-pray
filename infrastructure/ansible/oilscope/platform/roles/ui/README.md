# UI role

Pulls and starts only the OilScope `ui` Compose service, then waits for its
existing Docker health check.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The dynamic inventory contains hosts in the `database` and `history`
  groups, each with an `internal_ip` variable.
- Database is healthy and migrated, and History is healthy.

The deployment workflow retrieves `REDIS_PASSWORD` and passes it as
`ui_redis_password`. UI never receives PostgreSQL or RabbitMQ credentials.

## Variables

- `ui_redis_password`: Redis password injected by the deployment workflow.
- `ui_redis_host` and `ui_redis_port`: authenticated Redis endpoint on the infra VM.
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
        ui_redis_password: "{{ resolved_secrets.REDIS_PASSWORD }}"
```

The role gets `REDIS_HOST` from the first `database` host's `internal_ip` and forms
`HISTORY_SERVICE_URL` from the first `history` host's `internal_ip`.
It uses `docker compose pull ui` and
`docker compose up --detach --no-deps ui`.
