# UI role

Pulls and starts only the OilScope `ui` Compose service, then waits for its
existing Docker health check.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The dynamic cloud inventory contains hosts in the `infrastructure` and
  `history` groups, each with an `internal_ip` variable.
- Database is healthy and migrated, and History is healthy.

The deployment workflow retrieves `POSTGRES_PASSWORD` and passes it as
`ui_postgres_password`. This role does not retrieve or store secret values.

## Variables

- `ui_postgres_password`: password injected by the deployment workflow.
- `ui_session_backend`: `postgresql` for a self-managed database or `redis` for
  a managed database; defaults to `postgresql`.
- `ui_database_host`: PostgreSQL host passed to Compose; defaults to `postgres`.
- `ui_redis_url`: Redis connection URL required for a managed database.
- `ui_docker_config_dir`: transient Docker client configuration directory;
  defaults to `/run/oilscope/docker-auth`.
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
        ui_database_host: "{{ hostvars[groups['infrastructure'][0]].internal_ip }}"
```

The deployment playbook supplies `ui_database_host` from the selected database
architecture and constructs `ui_redis_url` for a managed database. The role
forms `HISTORY_SERVICE_URL` from the first `history` host's `internal_ip`. It
uses `docker compose pull ui` and
`docker compose up --detach --no-deps ui`.
