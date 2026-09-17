# Secret versions role

Adds a new Secret Manager version to every container declared in the project
configuration, taking each value from the environment of the operator running
the play. It runs on `localhost`: this is an operator task against the Google
API, not host configuration.

Terraform creates the containers and grants access to them, and never carries a
payload — see [docs/secrets.md](../../../../../../docs/secrets.md). This role is
the other half: the payload, and nothing else.

## What it guarantees

- Values are read from the process environment, and from nowhere else. Nothing
  is written to disk.
- The payload reaches `gcloud` on stdin through `--data-file=-`, so it never
  becomes a command argument and cannot appear in `ps` output or a shell
  history. `stdin_add_newline` is off, because a trailing newline would become
  part of the stored value.
- The upload task is marked `no_log`, so the value stays out of the Ansible
  output and out of any callback log, at every verbosity.
- Every value and every container is checked before the first version is added.
  A run either writes all of them or none: half-rotated is the state that
  leaves one workload on the new credential and the rest on the old one.

Run it with `--check` first. In check mode the role performs every check and
adds nothing.

## Requirements

`gcloud`, authenticated as a principal holding
`roles/secretmanager.secretVersionAdder` on the containers. That role permits
adding a version and not reading one, so rotation does not require access to
the current value. Terraform grants it from the `secret_version_managers`
variable.

The containers must already exist: `terraform apply` creates them from the same
configuration file this role reads.

## Required variables

- `secret_versions_config_file`: path to the project configuration JSON — the
  same file `project_config_path` points at in Terraform.

## Optional variables

- `secret_versions_project_id`: target project. Falls back to `$GOOGLE_PROJECT`,
  then to `clouds.gcp.project_id` in the configuration.
- `secret_versions_only`: list of container IDs or variable names to upload.
  Defaults to all of them; use it to rotate one credential.
- `secret_versions_gcloud`: path to the `gcloud` executable.

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

The role prints the mapping before it uploads anything, so there is nothing to
guess.

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
