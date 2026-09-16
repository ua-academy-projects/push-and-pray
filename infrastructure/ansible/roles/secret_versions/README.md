# Secret versions

Uploads secret values from the controller process environment to GCP Secret
Manager and AWS Secrets Manager. Terraform creates the empty secret containers;
this role creates versions without putting payloads in Terraform state or the
project configuration.

The shared `oilscope_config` determines which clouds need each secret. A secret
used by VMs in both clouds is uploaded to both providers.

## Source variables

An environment-variable name is derived from each secret ID. For example:

```text
oilscope-dev-db-password -> DB_PASSWORD
example-api-key          -> EXAMPLE_API_KEY
```

If shortened names collide, fully qualified names are used. The playbook prints
the final mapping before uploading anything.

## Requirements

- `gcloud` authenticated with permission to add GCP secret versions when GCP
  secrets are present;
- AWS CLI authenticated with `secretsmanager:PutSecretValue` when AWS secrets
  are present;
- all printed source variables exported in the controller environment.

Payloads are sent through stdin and secret-bearing tasks use `no_log: true`.
AWS uploads use `file:///dev/stdin`, keeping the value out of process arguments.

## Usage

```bash
export EXAMPLE_DB_PASSWORD='...'
export EXAMPLE_GHCR_TOKEN='...'
export EXAMPLE_API_KEY='...'

ansible-playbook -i inventory playbooks/upload_secret_versions.yml --check
ansible-playbook -i inventory playbooks/upload_secret_versions.yml
```

Use `secret_versions_only` to upload selected IDs or source variables:

```bash
ansible-playbook -i inventory playbooks/upload_secret_versions.yml \
  -e '{"secret_versions_only":["EXAMPLE_API_KEY"]}'
```

Check mode validates configuration and source variables but does not upload.
