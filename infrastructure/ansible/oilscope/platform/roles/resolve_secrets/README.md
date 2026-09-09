# Resolve secrets role

Resolves the secret values permitted for the current host from Secret
Manager (GCP) or Secrets Manager (AWS), using the workload VM's own attached
identity — its service account on GCP, its instance role on AWS — never the
operator's credentials. It runs on the workload host itself, as part of a
deployment play, not on `localhost`.

Terraform creates the containers and grants each workload access only to its
own secrets; `secret_versions` writes values into them from an operator's
environment — see [docs/secrets.md](../../../../../../docs/secrets.md). This
role is the read side used at deploy time: it turns `secret_mappings` into an
in-memory mapping the workload's own role can use to configure the running
containers.

## What it guarantees

- Only the secrets listed in the current host's own `secret_mappings` are
  ever requested — never another workload's, and never a sibling VM that
  happens to share the same `role`.
- Authentication is the instance's attached service account, obtained from
  the metadata server. No credential is supplied by the operator or stored
  on the host.
- Nothing is written to disk. The result exists only as an in-memory fact
  for the duration of the play.
- Every task that could carry a token or a secret value is marked `no_log`,
  so nothing appears in Ansible output or a callback log, at any verbosity.
- A missing or inaccessible secret fails the task immediately, before any
  container is started.

## Requirements

On GCP, the host must be a GCE instance with a service account attached,
granted `roles/secretmanager.secretAccessor` on the secrets in its own
`secret_mappings` — this is what `infrastructure/terraform/modules/gcp/secrets`
grants automatically.

On AWS, the host must be an EC2 instance with an instance profile attached,
granted `secretsmanager:GetSecretValue` on the secrets in its own
`secret_mappings` — this is what `infrastructure/terraform/modules/aws/secrets`
grants automatically. The role installs the AWS CLI itself; no credential is
ever supplied by the operator or written to disk, since the CLI's default
credential chain discovers the instance's own role via IMDS.

The role identifies which `vms` entry is "this host" from `oilscope_vm_key`,
a host variable set by the dynamic inventory plugin (`oilscope_gcp` /
`oilscope_aws`), which derives it from the instance's own name (GCP) or
`Name` tag (AWS) — not from a role or group name, and not by re-parsing
`inventory_hostname` here. This matters because a VM's `role` is not always
its `vms` key (the database VM's key is `infra`, its role is `database`), and
the schema does not require `role` to be unique across `vms` — two VMs could
share one. Matching by the exact key, rather than by role, means a host can
never resolve to a sibling's secrets even in that case. `oilscope_cloud`
(also set by the inventory plugin) selects which cloud's read path runs. An
`oilscope_vm_key` that isn't in the configuration's `vms`, or an
`oilscope_cloud` that isn't `gcp`/`aws`, fails the play immediately rather
than silently resolving nothing.

## Required variables

- `resolve_secrets_config_path`: path to the project configuration JSON —
  the same file `project_config_path` points at in Terraform.
- `oilscope_vm_key`, `oilscope_cloud`: normally inherited automatically from
  the dynamic inventory (see above); only need setting by hand outside of it,
  such as in a role test against a static inventory.

## Optional variables

GCP only - AWS needs no equivalent, since the region is always derived from
`region_map` in the project configuration:

- `resolve_secrets_project_id`: target project. Falls back to
  `$GOOGLE_PROJECT`, then to `clouds.gcp.project_id` in the configuration.
- `resolve_secrets_metadata_url`: the instance metadata token endpoint.
- `resolve_secrets_secretmanager_url`: the Secret Manager REST API base URL.

## Output

`resolve_secrets_result`: a dict keyed by application variable name — the
key side of `secret_mappings` — mapping to the resolved secret value. A host
with no `secret_mappings` gets an empty result rather than a failure.

## License

GPL-2.0-or-later
