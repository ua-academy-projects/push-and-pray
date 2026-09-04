# Resolve application secrets

Application roles pass their own structured `vars/secrets.yml` mapping to this
shared role. The mapping key is the application's runtime variable; `secret_id`
is the logical provider-independent ID, and `source_env` is reserved for secret
provisioning. This role derives the physical name as
`<name_prefix>-<environment>-<secret_id>` and returns the retrieved value under
the runtime-variable key.

It selects `google.cloud.gcp_secret_manager` for GCP or
`amazon.aws.secretsmanager_secret` for AWS. Project and region default to the
host context supplied by the dynamic inventory; name prefix and environment
come from the loaded project configuration.

Lookups execute on the Ansible controller with its cloud credentials. Results
are returned in the in-memory `resolve_secrets_result` mapping, and all tasks
that handle values use `no_log`.
