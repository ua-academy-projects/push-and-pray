# UI role

Pulls and starts only the OilScope `ui` service from the shared deployment
Compose project, then verifies its public `/health` endpoint.

## Requirements

The target must have Docker with the Compose plugin installed. The
`oilscope.platform.compose_project` role must already have installed the shared
Compose definition at `/opt/oilscope/app/compose.yaml`.

Inventory must contain exactly one host in each of the `database` and `history`
groups. Both hosts must define `internal_ip`, the private address field in the
project configuration contract. All three names can be changed through
`ui_database_inventory_group`, `ui_history_inventory_group`, and
`ui_inventory_private_address_var` if an external inventory maps the same
contract differently.

## Required variables

- `ui_application_image_tag`: full 40-character Git SHA for the UI image.
- `ui_postgres_image`: complete PostgreSQL image reference pinned with
  `@sha256:<64 hexadecimal characters>`. Compose requires this while parsing
  the shared file, but this role never pulls or starts that image.
- `ui_postgres_password`: PostgreSQL password injected by the runtime secret
  mechanism. Sensitive Compose operations use `no_log`, and the value is not
  written to disk by this role.
- `ui_health_host`: public UI DNS name or external IP reachable from
  `ui_health_delegate_to`. The repository exposes UI addresses through the
  Terraform `workload_external_ips` output, but does not currently define how
  that output is mapped into Ansible inventory. The deployment inventory or
  playbook must therefore set this variable explicitly. It deliberately does
  not default to `ansible_host`, which may be a private SSH transport address.

The pending `gcp_runtime_secrets` role can provide `ui_postgres_password`
directly when it is introduced. This role deliberately has no Secret Manager
lookup or fallback credential.

## Optional variables

- `ui_compose_project_dir`, `ui_compose_file`, and
  `ui_compose_project_name`: shared Compose project settings; defaults match
  the existing roles (`/opt/oilscope/app`, `compose.yaml`, and `petroscope`).
- `ui_database_port` and `ui_history_port`: internal service ports; default to
  `5432` and `8001`.
- `ui_bind_address` and `ui_http_port`: public listener; default to `0.0.0.0:80`.
- `ui_postgres_user`, `ui_postgres_name`, and `ui_database_sslmode`: database
  connection settings.
- `ui_session_ttl_seconds`, `ui_session_cookie_secure`, and `ui_log_level`: UI
  runtime settings.
- `ui_compose_environment`: additional Compose environment values. Explicit
  role values take precedence when dictionaries are combined.
- `ui_health_delegate_to`: host that performs the public check; defaults to the
  Ansible controller (`localhost`).
- `ui_health_scheme`, `ui_health_path`, `ui_health_status_code`,
  `ui_health_retries`, `ui_health_delay`, and `ui_health_validate_certs`: public
  health-check settings.

## Example

```yaml
---
- name: Deploy the UI
  hosts: ui
  become: true
  roles:
    - role: oilscope.platform.ui
      vars:
        ui_application_image_tag: 0123456789abcdef0123456789abcdef01234567
        ui_postgres_image: >-
          ghcr.io/ua-academy-projects/push-and-pray/database@sha256:...
        ui_postgres_password: "{{ runtime_secrets.POSTGRES_PASSWORD }}"
        ui_health_host: "{{ ui_public_address }}"
```

The role runs the equivalents of `docker compose pull ui` and
`docker compose up --detach --no-deps ui`. It does not start PostgreSQL,
Migrate, History, or Fetcher.

## License

GPL-2.0-or-later
