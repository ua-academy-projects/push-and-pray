# Secrets

Application roles own their secret requirements in `vars/secrets.yml`. Each
entry keeps four meanings separate:

- the mapping key is the application's runtime variable, such as
  `POSTGRES_PASSWORD`;
- `secret_id` is the reusable logical identifier, such as
  `db-password-history`;
- `source_env` is the operator environment variable used during provisioning,
  such as `DB_PASSWORD_HISTORY`;
- the physical provider name is derived as
  `<name_prefix>-<environment>-<secret_id>`.

VM entries in project configuration contain neither secret mappings nor values.

The Ansible `secret_versions` role creates provider-specific secret containers
and uploads their values. It reads only the declarations for roles used by the
configured workloads, adds registry credentials only when registry
authentication is configured, and deduplicates containers within each GCP
project or AWS region. Terraform does not manage application secrets.

At deployment time each application role passes its declaration to
`oilscope.platform.resolve_secrets`. The resolver selects the provider from the
target host's effective cloud, supplied by dynamic inventory:

- GCP values use `google.cloud.gcp_secret_manager` and the configured project.
- AWS values use `amazon.aws.secretsmanager_secret` and the workload region.

These lookups run on the Ansible controller, so the controller's GCP/AWS
credentials need permission to read the required containers. Retrieved values
remain in Ansible variables and value-bearing tasks use `no_log`. They are not
passed through Terraform configuration, output, plan, or state.

The `secret_versions` role reads values from each declaration's `source_env`.
It resolves explicit `vm.cloud` first and otherwise uses `default_cloud`, then
ensures each required physical container exists and uploads one version per used
GCP project or AWS region with `gcloud` or the AWS CLI. Both clients must be
authenticated for the clouds present in the configuration. Those operator
credentials need permission to describe and create containers and add versions.

Provisioning the current roles uses these operator variables:

```text
DB_PASSWORD_ADMIN
DB_PASSWORD_FETCHER
DB_PASSWORD_HISTORY
DB_PASSWORD_UI
OILPRICEAPI_KEY
GHCR_TOKEN
```

```sh
ansible-playbook oilscope.platform.upload_secret_versions \
  -e project_config_path=/absolute/path/project-config.json
```

Use `secret_versions_only` to select by runtime variable, source environment
variable, logical secret ID, or final physical provider name. Upload tasks pass
values through standard input and use `no_log`; they do not run in check mode.
