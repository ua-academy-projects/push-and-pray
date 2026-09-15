# Secret versions role

Adds GCP Secret Manager versions for operator-owned containers declared in the canonical
project config. It runs on `localhost` and reads values only from the operator process
environment.

In managed mode, the role omits configured `POSTGRES_PASSWORD` and `REDIS_PASSWORD`
mappings because Terraform generates those values. The generated RabbitMQ password and
database host are not operator upload inputs either. Operator-owned values such as
`GHCR_TOKEN` and `OILPRICEAPI_KEY` remain uploadable. In self-hosted mode, configured
PostgreSQL and Redis passwords remain operator-owned.

## Guarantees

- Payloads go to `gcloud secrets versions add --data-file=-` on stdin, never a command
  argument, and `stdin_add_newline` is disabled.
- Payload tasks use `no_log` and nothing is written to disk.
- Every required environment value is checked before the first version is added.
- Check mode performs validation but adds no version.

## Variables

- `secret_versions_config_file`: the same config path used as Terraform and Ansible
  `project_config_path`.
- `secret_versions_project_id`: optional project override; otherwise `$GOOGLE_PROJECT`
  and then `clouds.gcp.project_id` are used.
- `secret_versions_only`: optional list of container IDs or derived environment variable
  names to upload.
- `secret_versions_gcloud`: optional `gcloud` executable path.

The operator needs `roles/secretmanager.secretVersionAdder` on the selected containers.
Terraform grants that role to principals listed in `secret_version_managers`.

The role prints the non-secret mapping from derived environment variable name to secret
container before uploading. Run it with `--check` first:

```sh
ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file=/absolute/path/project-config.json --check
```

See [Secrets](../../../../../../docs/secrets.md) for ownership and rotation guidance.

## License

GPL-2.0-or-later
