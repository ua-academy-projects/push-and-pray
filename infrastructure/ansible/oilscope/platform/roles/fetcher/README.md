# Fetcher role

Pulls the OilScope Fetcher image, starts the Fetcher service, and waits for
its Docker health check.

## Requirements

The target must have Docker with the Compose plugin installed. The supported
Compose definition must already be installed on the target; use the
`oilscope.platform.compose_project` role for that step.

In self-hosted mode, Fetcher publishes through PGMQ and requires PostgreSQL. In managed
mode it publishes through RabbitMQ and receives no PostgreSQL endpoint or password.

## Required variables

- `fetcher_postgres_password`: self-hosted database password. It is empty and unused in
  managed mode.
- `fetcher_oilpriceapi_key`: price data provider API key supplied by the
  deployment secret mechanism. Same `no_log` handling as the password.

## Optional variables

- `fetcher_compose_project_dir`: Compose directory; defaults to
  `/opt/oilscope/app`.
- `fetcher_compose_file`: Compose file; defaults to `compose.yaml` in that
  directory.
- `fetcher_compose_project_name`: Compose project name; defaults to
  `petroscope`.
- `fetcher_service`: Compose service name; defaults to `fetcher`.
- `fetcher_postgres_user` and `fetcher_postgres_name`: both default to
  `oil_tracker`.
- `fetcher_database_host`: defaults to `postgres`; override to the database
  VM's address when Fetcher and the database run on separate hosts.
- `fetcher_messaging_backend`: `pgmq` or `rabbitmq`.
- `fetcher_rabbitmq_host`, `fetcher_rabbitmq_port`, and
  `fetcher_rabbitmq_password`: managed-mode broker connection.
- `fetcher_bind_address`: defaults to `0.0.0.0`.
- `fetcher_host_port`: defaults to `8002`.
- `fetcher_health_retries` and `fetcher_health_delay`: health polling
  controls, defaulting to 30 attempts every 2 seconds.
- `fetcher_compose_environment`: additional non-secret Compose environment.

## Example playbook

```yaml
---
- name: Deploy the Fetcher service
  hosts: fetcher
  become: true
  roles:
    - role: oilscope.platform.fetcher
      vars:
        fetcher_postgres_password: "{{ vault_database_password }}"
        fetcher_oilpriceapi_key: "{{ vault_oilpriceapi_key }}"
        fetcher_database_host: 10.0.1.2
```

Running the role again is safe: Compose reconciles the existing Fetcher
container, and the health wait re-confirms it is running before the role
finishes.

## License

GPL-2.0-or-later
