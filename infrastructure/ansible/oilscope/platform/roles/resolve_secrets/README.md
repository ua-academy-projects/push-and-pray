# Resolve secrets role

Resolves only the secret values mapped to the current workload, using the
VM's provider-native runtime identity rather than operator credentials. GCP
uses the attached service account and metadata token. AWS uses boto3's normal
instance-profile credential chain.

Terraform creates containers and grants least-privilege read access. In managed mode it
also creates versions for the generated PostgreSQL host/password, RabbitMQ password, and
Redis password. This role keeps returned values in Ansible facts under `no_log`; it does
not write them to disk.

## Requirements

- `resolve_secrets_config_path` must point to the shared project config.
- GCP hosts need the Terraform-managed service account.
- AWS hosts need the Terraform-managed instance profile and `python3-boto3`,
  which the `host_baseline` role installs.
- Inventory must expose `oilscope_cloud` and `oilscope_role`.
- Inventory must expose `oilscope_region`; the AWS client uses it explicitly
  instead of relying on an ambient SDK default region.

Mappings are selected by role, so `vms.infra` consumes the `database` application mapping
without deriving a VM key from its hostname. Managed mode removes Fetcher's configured
`POSTGRES_PASSWORD`, adds `DATABASE_HOST` only to database and History, and adds
`RABBITMQ_PASSWORD` only to database, History, and Fetcher. UI receives neither managed
database nor RabbitMQ credentials.

Optional GCP settings are `resolve_secrets_project_id`,
`resolve_secrets_metadata_url`, and `resolve_secrets_secretmanager_url`.
Project lookup falls back to `$GOOGLE_PROJECT`, then
`clouds.gcp.project_id`.

The result is `resolve_secrets_result`, keyed by the application environment
variable names from `application.secret_mappings[oilscope_role]`. Hosts without
mappings get an empty dictionary.

## License

GPL-2.0-or-later
