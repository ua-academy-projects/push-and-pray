# History role

Pulls and starts only the OilScope `history` Compose service, then verifies its
local health endpoint.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The dynamic GCP inventory contains one host in the `database` group with an `internal_ip` variable.
- Database is healthy and migrated.

The deployment workflow retrieves `POSTGRES_PASSWORD` from Secret Manager and
passes it as `history_postgres_password`. This role does not retrieve or store
secret values.

## Variables

- `history_application_image_tag`: History image Git SHA.
- `history_postgres_image`: PostgreSQL image required to parse the shared
  Compose file.
- `history_postgres_password`: password injected by the deployment workflow.

## Example

```yaml
- name: Deploy History
  hosts: history
  become: true
  roles:
    - role: oilscope.platform.history
      vars:
        history_application_image_tag: "0123456789abcdef0123456789abcdef01234567"
        history_postgres_image: "ghcr.io/example/database@sha256:..."
        history_postgres_password: "{{ resolved_secrets.POSTGRES_PASSWORD }}"
```

The role uses `docker compose pull history` and
`docker compose up --detach --no-deps history`.
