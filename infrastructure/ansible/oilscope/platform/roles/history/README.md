# History role

Pulls and starts only the OilScope `history` Compose service, then verifies its
local health endpoint.

## Requirements

- Docker and the Compose plugin are installed.
- `/opt/oilscope/app/compose.yaml` is installed.
- The dynamic inventory contains one host in the `database` group with an `internal_ip` variable.
- Database is healthy and migrated.

The role declares and retrieves `POSTGRES_PASSWORD` before starting History.

## Variables

- `history_postgres_password`: resolved from the role declaration unless passed explicitly.

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
