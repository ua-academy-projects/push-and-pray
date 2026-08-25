# Database role

Pulls the immutable OilScope PostgreSQL image, starts the database service,
waits for its Docker health check, and applies the bundled SQL migrations.

## Requirements

The target must have Docker with the Compose plugin installed. The supported
Compose definition must already be installed on the target; use the
`oilscope.platform.compose_project` role for that step.

The database image must contain `petroscope-migrate` and the migrations under
`/opt/petroscope/migrations`, as defined by `Dockerfile.database`.

## Required variables

- `database_postgres_image`: complete image reference pinned with
  `@sha256:<64 hexadecimal characters>`.
- `database_application_image_tag`: full 40-character Git SHA required while
  rendering the shared Compose definition. Application services are not
  started by this role.
- `database_postgres_password`: password supplied by the deployment secret
  mechanism. The role marks tasks receiving it with `no_log` and does not write
  it to disk.

## Optional variables

- `database_compose_project_dir`: Compose directory; defaults to
  `/opt/oilscope/app`.
- `database_compose_file`: Compose file; defaults to `compose.yaml` in that
  directory.
- `database_postgres_user` and `database_postgres_name`: both default to
  `oil_tracker`.
- `database_bind_address`: defaults to `0.0.0.0`.
- `database_host_port`: defaults to `5432`.
- `database_health_retries` and `database_health_delay`: health polling
  controls, defaulting to 30 attempts every 2 seconds.
- `database_compose_environment`: additional non-secret Compose environment.

## Example

```yaml
---
- name: Deploy the database
  hosts: database
  become: true
  roles:
    - role: oilscope.platform.database
      vars:
        database_postgres_image: >-
          ghcr.io/ua-academy-projects/push-and-pray/database@sha256:...
        database_application_image_tag: 0123456789abcdef0123456789abcdef01234567
        database_postgres_password: "{{ vault_database_password }}"
```

Running the role again is safe: Compose reconciles the existing PostgreSQL
container and the bundled migrations use idempotent SQL operations. The
migration container is removed after every successful run.

## License

GPL-2.0-or-later
