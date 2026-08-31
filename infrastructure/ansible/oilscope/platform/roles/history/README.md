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
