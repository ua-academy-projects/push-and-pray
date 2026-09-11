# Secret versions role

Adds a new version to every secret container declared in the project
configuration, taking each value from the environment of the operator running
the play. It runs on `localhost`: this is an operator task against the cloud
APIs, not host configuration.

A container exists on every cloud its readers are placed on, so the role works
out, per container, which clouds hold it and uploads the same value to each.
Which tool does the writing is chosen by file name — `tasks/upload-gcp.yml` or
`tasks/upload-aws.yml` — so supporting another provider means adding a file,
not a conditional.

Terraform creates the containers and grants access to them, and never carries a
payload — see [docs/secrets.md](../../../../../../docs/secrets.md). This role is
the other half: the payload, and nothing else.

## What it guarantees

- Values are read from the process environment, and from nowhere else. Nothing
  is written to disk.
- The payload reaches the cloud CLI on stdin — `--data-file=-` for `gcloud`,
  `--secret-string file:///dev/stdin` for `aws` — so it never becomes a command
  argument and cannot appear in `ps` output or a shell history.
  `stdin_add_newline` is off, because a trailing newline would become part of
  the stored value.
- The upload task is marked `no_log`, so the value stays out of the Ansible
  output and out of any callback log, at every verbosity.
- Every value and every container is checked before the first version is added.
  A run either writes all of them or none: half-rotated is the state that
  leaves one workload on the new credential and the rest on the old one.

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

A cloud that holds no container needs neither its tool nor a credential: the
role only touches the clouds the catalog names.

The containers must already exist: `terraform apply` creates them from the same
configuration file this role reads.

## Required variables

- `secret_versions_config_file`: path to the project configuration JSON — the
  same file `project_config_path` points at in Terraform.

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

## Which variable holds which value

The variable name is derived from the container ID, with the
`<name_prefix>-<environment>-` prefix dropped while that stays unambiguous:

```
oilscope-dev-db-password-fetcher   ->  DB_PASSWORD_FETCHER
oilscope-dev-oilpriceapi-key       ->  OILPRICEAPI_KEY
```

It is deliberately not the key side of `secret_mappings`. That key is the
variable the application reads *inside one VM*: `DB_PASSWORD` is the fetcher's
password on `fetcher` and the history service's password on `history`, and one
shell cannot hold both under one name. If dropping the prefix would make two
containers collide, every container keeps the fully qualified name
(`OILSCOPE_DEV_DB_PASSWORD_FETCHER`) instead.

The role prints the mapping before it uploads anything — including which clouds
each container is held on — so there is nothing to guess:

```
EXAMPLE_DB_PASSWORD -> example-db-password on aws, gcp (read by fetcher, history, infra, ui)
EXAMPLE_API_KEY     -> example-api-key on gcp (read by fetcher)
```

One variable feeds every copy of a container. A value is never typed twice
because two clouds hold it.

## Testing without a cloud

`tests/test.yml` checks the two refusals that need no environment: a missing
configuration, and values absent from the shell. The upload path itself can be
exercised end to end against stub commands, so nothing reaches a real API:

```bash
printf '#!/bin/sh\ncat >/dev/null\necho stub-version-1\n' > /tmp/stub-cli && chmod +x /tmp/stub-cli
EXAMPLE_DB_PASSWORD=a EXAMPLE_GHCR_TOKEN=b EXAMPLE_API_KEY=c \
  ansible-playbook oilscope.platform.upload_secret_versions \
    -e secret_versions_config_file=$PWD/project-config.example.json \
    -e secret_versions_gcloud=/tmp/stub-cli \
    -e secret_versions_aws_cli=/tmp/stub-cli
```

Moving a workload to the other cloud in a copy of the configuration shows the
catalog split and both upload files run.

## Example

```bash
 export DB_PASSWORD_ADMIN="$(openssl rand -hex 32)"
 export DB_PASSWORD_FETCHER="$(openssl rand -hex 32)"
 export DB_PASSWORD_HISTORY="$(openssl rand -hex 32)"
 export DB_PASSWORD_UI="$(openssl rand -hex 32)"
 export OILPRICEAPI_KEY="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json
```

The leading space keeps the export out of the shell history, in a shell
configured to honour it.

Rotating one credential:

```bash
 export DB_PASSWORD_UI="$(openssl rand -hex 32)"

ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=~/configs/oilscope/dev.json \
  -e '{"secret_versions_only": ["DB_PASSWORD_UI"]}'
```

Older versions stay until they are destroyed, so an upload is reversible until
then.

## License

GPL-2.0-or-later
