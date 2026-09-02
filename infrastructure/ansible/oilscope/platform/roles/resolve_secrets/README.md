# Resolve secrets role

Resolves only the secret values mapped to the current workload, using the
VM's provider-native runtime identity rather than operator credentials. GCP
uses the attached service account and metadata token. AWS uses boto3's normal
instance-profile credential chain.

Terraform creates containers without values and grants least-privilege read
access. This role keeps returned values in Ansible facts under `no_log`; it
does not write them to disk.

## Requirements

- `resolve_secrets_config_path` must point to the shared project config.
- GCP hosts need the Terraform-managed service account.
- AWS hosts need the Terraform-managed instance profile and `python3-boto3`,
  which the `host_baseline` role installs.
- Inventory must expose `oilscope_cloud` and use Terraform's instance name,
  `<name_prefix>-<environment>-<vms key>`.

The exact VM key is derived from `inventory_hostname`, so `vms.infra` still
uses its own mappings even though its functional role is `database`.

Optional GCP settings are `resolve_secrets_project_id`,
`resolve_secrets_metadata_url`, and `resolve_secrets_secretmanager_url`.
Project lookup falls back to `$GOOGLE_PROJECT`, then
`clouds.gcp.project_id`.

The result is `resolve_secrets_result`, keyed by the application environment
variable names from `secret_mappings`. Hosts without mappings get an empty
dictionary.

## License

GPL-2.0-or-later
