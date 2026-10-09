# Secret versions role

Adds a new version to every secret container the cluster configuration's
`secrets` block declares, taking each value from the environment of the
operator running the play. It runs on `localhost`: this is an operator task against the cloud
APIs, not host configuration.

Only `k3s_server` nodes read secrets, so a container exists on every cloud
that runs a server - Terraform creates it there and nowhere else. The role
works out which clouds those are and uploads the same value to each.
Which tool does the writing is chosen by file name — `tasks/upload-gcp.yml`,
`tasks/upload-aws.yml` or `tasks/upload-azure.yml` — so supporting another
provider means adding a file, not a conditional.

Terraform creates the containers and grants access to them, and never carries a
payload — see [docs/secrets.md](../../../../../../docs/secrets.md). This role is
the other half: the payload, and nothing else.

## What it guarantees

- Values are read from the process environment, and from nowhere else. Nothing
  is written to disk.
- The payload reaches the cloud CLI on stdin — `--data-file=-` for `gcloud`,
  `--secret-string file:///dev/stdin` for `aws`, `--file /dev/stdin` for
  `az` — so it never becomes a command
  argument and cannot appear in `ps` output or a shell history.
  `stdin_add_newline` is off, because a trailing newline would become part of
  the stored value.
- The upload task is marked `no_log`, so the value stays out of the Ansible
  output and out of any callback log, at every verbosity.
- Every value and every container is checked before the first version is added.
  A missing value stops the run before anything is written: half-rotated is
  the state that leaves one host on the new credential and the rest on the old
  one. A cloud API failing during the writes themselves can still leave a
  partial rotation; run again once the cause is fixed.

Run it with `--check` first. In check mode the role performs every check and
adds nothing.

## Requirements

The CLI of every cloud that holds a container, authenticated as a principal
allowed to add a version and not to read one, so rotation never requires access
to the current value:

| Cloud | Tool | Permission | Terraform grants it from |
| --- | --- | --- | --- |
| GCP | `gcloud` | `roles/secretmanager.secretVersionAdder` | `clouds.gcp.secret_version_managers` |
| AWS | `aws` | `secretsmanager:PutSecretValue` | `clouds.aws.secret_version_managers` |
| Azure | `az` | a custom role with `Microsoft.KeyVault/vaults/secrets/setSecret/action` | `clouds.azure.secret_version_managers` |

Azure has no built-in role that writes a secret without reading it; `Key Vault
Secrets Officer` would do the job but also reads every value.

A cloud that holds no container needs neither its tool nor a credential: the
role only touches the clouds the catalog names.

The containers must already exist: `terraform apply` creates them from the same
configuration file this role reads. On Azure, where a secret cannot exist
without a value, Terraform creates each one holding a placeholder that
`resolve_secrets` refuses to read; the first upload replaces it.

## Required variables

- `secret_versions_config_file`: path to the cluster configuration JSON — the
  same file `project_config_path` points at in Terraform. Defaults to
  `project_config_path`, which `group_vars/all.yml` takes from
  `OILSCOPE_PROJECT_CONFIG`.

## Optional variables

- `secret_versions_only`: list of container IDs or variable names to upload.
  Defaults to all of them; use it to rotate one credential. Clouds that hold
  none of the selected containers are skipped entirely.
- `secret_versions_supported_clouds`: clouds an `upload-<cloud>.yml` exists
  for. A container held anywhere else is refused by name.

GCP only:

- `secret_versions_project_id`: target project. Falls back to
  `$GOOGLE_PROJECT`, then to `clouds.gcp.project_id` in the configuration.
- `secret_versions_gcloud`: path to the `gcloud` executable.

AWS only:

- `secret_versions_region`: target region. Falls back to `clouds.aws.region`.
- `secret_versions_aws_cli`: path to the `aws` executable.

Azure only:

- `secret_versions_key_vault_name`: target vault. Falls back to
  `clouds.azure.key_vault_name`.
- `secret_versions_az_cli`: path to the `az` executable.

## Which variable holds which value

The variable is the key of the `secrets` block, as written:

```json
"secrets": {
  "K3S_TOKEN": "k3s-token",
  "TAILSCALE_AUTHKEY": "tailscale-authkey"
}
```

`K3S_TOKEN` feeds the container `k3s-token`. The block is the same for the
whole cluster, so one name means one value everywhere and nothing has to be
derived. Two variables naming the same container are refused: both would be
written in one run, and the last would win.

The role prints the mapping before it uploads anything — including which
clouds hold each container and which servers read it — so there is nothing to
guess:

```
K3S_TOKEN -> k3s-token on aws, gcp (read by server-1, server-2)
```

One variable feeds every copy of a container. A value is never typed twice
because two clouds hold it.

## Testing without a cloud

`tests/test.yml` checks the two refusals that need no environment: a missing
configuration, and values absent from the shell. The upload path itself can be
exercised end to end against stub commands, so nothing reaches a real API:

```bash
printf '#!/bin/sh\ncat >/dev/null\necho stub-version-1\n' > /tmp/stub-cli && chmod +x /tmp/stub-cli
K3S_TOKEN=a TAILSCALE_AUTHKEY=b GHCR_TOKEN=c OILPRICEAPI_KEY=d \
  ansible-playbook oilscope.cluster.upload_secret_versions -c local -i localhost, \
    -e project_config_path=$PWD/cluster-config.example.json \
    -e secret_versions_gcloud=/tmp/stub-cli \
    -e secret_versions_aws_cli=/tmp/stub-cli \
    -e secret_versions_az_cli=/tmp/stub-cli
```

Placing a server on another cloud in a copy of the configuration shows the
catalog spread to it and that cloud's upload file run.

## Example

```bash
 export K3S_TOKEN="$(openssl rand -hex 32)"
 export TAILSCALE_AUTHKEY="tskey-auth-..."
 export GHCR_TOKEN="..."
 export OILPRICEAPI_KEY="..."

ansible-playbook oilscope.cluster.upload_secret_versions --check
ansible-playbook oilscope.cluster.upload_secret_versions
```

The leading space keeps the export out of the shell history, in a shell
configured to honour it. The configuration comes from
`OILSCOPE_PROJECT_CONFIG`.

Rotating one credential:

```bash
 export TAILSCALE_AUTHKEY="tskey-auth-..."

ansible-playbook oilscope.cluster.upload_secret_versions \
  -e '{"secret_versions_only": ["TAILSCALE_AUTHKEY"]}'
```

Older versions stay until they are destroyed, so an upload is reversible until
then. `K3S_TOKEN` is the exception worth knowing: a server reads it only when
it first initialises the cluster, so a new value in the store does not rotate
the token of a running cluster.

## License

GPL-2.0-or-later
