# Resolve secrets role

Resolves the cluster's secrets from the secret store of the host's cloud,
using the node's own attached identity — not the operator's credentials. It
runs on the node itself, as part of a deployment play, not on `localhost`.

Only a `k3s_server` node reads anything: Terraform grants the secrets to the
servers and to nothing else. The play then hands what it needs onward in
memory - the join token to the agents, the Tailscale auth key to the bastions,
the rest into Kubernetes Secrets - so no other host needs a grant of its own.

Which cloud a host is on comes from `oilscope_cloud`, which the dynamic
inventory stamps on every host. That name selects a task file — `tasks/fetch-
gcp.yml`, `tasks/fetch-aws.yml` or `tasks/fetch-azure.yml` — so supporting
another provider means adding a file, not a conditional.

Terraform creates the containers on every cloud that runs a server and grants
the servers read access; `secret_versions` writes values into them from an
operator's environment — see [docs/secrets.md](../../../../../../docs/secrets.md).
This role is the read side used at deploy time: it turns the configuration's
`secrets` block into an in-memory mapping.

## What it guarantees

- Only a host that is a `k3s_server` entry of `nodes` ever requests anything,
  and only what the `secrets` block lists. A bastion or an agent gets an empty
  result without a single request.
- Authentication is the instance's own attached identity: a service account
  on GCP, an instance role on AWS, a user-assigned managed identity on Azure. No credential is supplied by the operator
  or stored on the host.
- Nothing is written to disk. The result exists only as an in-memory fact
  for the duration of the play.
- Every task that could carry a token or a secret value is marked `no_log`,
  so nothing appears in Ansible output or a callback log, at any verbosity.
- A missing or inaccessible secret fails the task immediately, before any
  container is started.

## Requirements

The server must carry an identity granted read access to the secrets.
`infrastructure/terraform/modules/<cloud>/secrets.tf` grants it automatically: `roles/secretmanager.secretAccessor` per secret on GCP, an
inline role policy listing the secret ARNs on AWS, `Key Vault Secrets User` per
secret on Azure.

### How each cloud is read

| | GCP | AWS | Azure |
| --- | --- | --- | --- |
| Credential | bearer token from the metadata server | instance role, via IMDS | managed identity token from IMDS |
| Transport | two `uri` calls from the host | `aws secretsmanager get-secret-value` on the host | two `uri` calls from the host |
| Host dependency | none | the AWS CLI | none |

GCP's Secret Manager and Azure Key Vault accept a plain bearer token, so
nothing has to be installed. Every AWS API call must be SigV4-signed, which is impractical to do
from `uri`, so the CLI does the signing — and obtains the instance role through
IMDS on its own, including the IMDSv2 token exchange these instances require.
`host_baseline` installs it on AWS hosts.

The role identifies which `nodes` entry is "this host" from
`inventory_hostname` itself, not from a group name. Terraform names every
instance `<name_prefix>-<environment>-<nodes key>`, and the dynamic
inventory's `hostnames: - name` setting makes `inventory_hostname` exactly that
instance name — so stripping the known `<name_prefix>-<environment>-` prefix
recovers the literal `nodes` key, the same key Terraform uses for `for_each`.
The role read from that entry, not from the inventory group, decides: a host
placed in the `k3s_server` group by hand, or a bastion named like a node, is
still refused unless the configuration says it is a server.

## Required variables

- `resolve_secrets_config_path`: path to the cluster configuration JSON —
  the same file `project_config_path` points at in Terraform. Defaults to
  `project_config_path`, which `group_vars/all.yml` takes from
  `OILSCOPE_PROJECT_CONFIG`.

## Optional variables

- `resolve_secrets_cloud`: which cloud this host is on. Defaults to
  `oilscope_cloud` from the dynamic inventory; set it explicitly when running
  outside that inventory.
- `resolve_secrets_supported_clouds`: clouds a `fetch-<cloud>.yml` exists for.
  A host with secrets on anything else is refused by name.

GCP only:

- `resolve_secrets_project_id`: target project. Falls back to
  `$GOOGLE_PROJECT`, then to `clouds.gcp.project_id` in the configuration.
- `resolve_secrets_metadata_url`: the instance metadata token endpoint.
- `resolve_secrets_secretmanager_url`: the Secret Manager REST API base URL.

AWS only:

- `resolve_secrets_region`: target region. Falls back to `clouds.aws.region`.
- `resolve_secrets_aws_cli`: path to the CLI; defaults to `aws`.

Azure only:

- `resolve_secrets_key_vault_name`: target vault. Falls back to
  `clouds.azure.key_vault_name`.
- `resolve_secrets_azure_token_url`: the instance metadata token endpoint.
- `resolve_secrets_azure_identity_id`: resource ID of the user-assigned
  identity to read with. Defaults to the one named after the VM in
  `<name_prefix>-<environment>-rg`. Always named in the request, because a VM
  may carry a second identity - enabling Azure Monitor from the portal adds a
  system-assigned one - which holds no grant on the vault.
- `resolve_secrets_azure_keyvault_api_version`: Key Vault data-plane API version.

## Output

`resolve_secrets_result`: a dict keyed by the variable names of the `secrets`
block (`K3S_TOKEN`, `TAILSCALE_AUTHKEY`, …), mapping to the resolved value. A
host that is not a server gets an empty result rather than a failure, and
needs neither a cloud nor a credential — the check and the fetch are skipped
together.

A play that runs elsewhere reads the values from the server's facts:

```yaml
tailscale_auth_key: "{{ hostvars[groups['k3s_server'][0]].resolve_secrets_result.TAILSCALE_AUTHKEY }}"
```

## License

GPL-2.0-or-later
