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
and uploads their values. For K3s it reads the database, history, fetcher, and
UI declarations, using the bootstrap server's cloud and location as the secret
provider scope. The Tailscale role also declares an auth key. Its secret is
provisioned in every K3s node's provider scope so nodes in different clouds
can join the same tailnet. The catalog deduplicates containers within each GCP
project or AWS region. Terraform does not manage these secrets.

The selected `database_mode` also filters the catalog. Managed mode adds
`RABBITMQ_PASSWORD` and `REDIS_PASSWORD` and does not request the unused Fetcher
or UI database passwords. RDS is the administrator-credential exception: AWS
generates that password in Secrets Manager, and Ansible retrieves it by the
non-secret ARN passed through Terraform inventory metadata.

At deployment time each application role passes its declaration to
`oilscope.platform.resolve_secrets`. The resolver selects the provider from the
target host's effective cloud, supplied by dynamic inventory:

- GCP values use `google.cloud.gcp_secret_manager` and the configured project.
- AWS values use the AWS CLI and the workload region.

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

Existing provider secrets are preserved when their `source_env` is absent.
RabbitMQ and Redis credentials are internal service secrets, so the role
generates a 256-bit hexadecimal value when either secret is not yet provisioned.
Supplying `RABBITMQ_PASSWORD` or `REDIS_PASSWORD` still performs an explicit
rotation.

Provisioning the current roles uses these operator variables:

```text
DB_PASSWORD_ADMIN
DB_PASSWORD_FETCHER
DB_PASSWORD_HISTORY
DB_PASSWORD_UI
OILPRICEAPI_KEY
RABBITMQ_PASSWORD
REDIS_PASSWORD
TAILSCALE_AUTH_KEY
```

Only the subset required by the selected mode is requested. Cloud SQL managed
mode uses `DB_PASSWORD_ADMIN`; RDS managed mode uses the AWS-generated
administrator password instead.

Private GHCR authentication is separate from application-secret provisioning.
The normal workload deployment reads these values from the Ansible controller
environment, logs in each target using a transient Docker configuration under
`/run`, and removes that configuration after the play:

```text
GHCR_USERNAME
GHCR_TOKEN
```

Cloudflare DNS and certificate automation use `CLOUDFLARE_API_TOKEN` from the
Terraform and Ansible controller environment. It is not an application secret
and is never uploaded by `secret_versions`. The aggregate K3s workload role stores it as a Kubernetes Secret for
the cert-manager Cloudflare DNS-01 Issuer. The legacy standalone Compose UI role
uses a VM-local Certbot renewal credential. See
[Cloudflare DNS and UI HTTPS](cloudflare-https.md).

```sh
ansible-playbook oilscope.platform.upload_secret_versions \
  -e project_config_path=/absolute/path/project-config.json
```

Use `secret_versions_only` to select by runtime variable, source environment
variable, logical secret ID, or final physical provider name. Upload tasks pass
values through standard input and use `no_log`; they do not run in check mode.
For Tailscale provisioning, set `TAILSCALE_AUTH_KEY` on the controller only
while uploading `secret_versions_only=['TAILSCALE_AUTH_KEY']`. The deployment
reads the stored value only for a node that needs to join. See
[Tailscale networking](tailscale.md).
