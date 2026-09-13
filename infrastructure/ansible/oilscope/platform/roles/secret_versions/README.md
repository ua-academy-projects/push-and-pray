# Provision application secrets

This controller-side role reads application secret IDs from each role's
`vars/secrets.yml`, resolves workload clouds with explicit `vm.cloud` or
`default_cloud`, ensures the required containers exist, and uploads one version
per used GCP project or AWS region. It uses `gcloud` for GCP and the AWS CLI for
AWS. Both must be authenticated for the clouds present in the configuration.
The operator credentials need permission to describe and create containers and
add secret versions.

Each declaration separates the application runtime variable, logical
`secret_id`, and operator `source_env`. The physical container name is
`<name_prefix>-<environment>-<secret_id>`, and its value always comes from
`source_env`. `secret_versions_only` accepts the runtime variable, source
environment variable, logical ID, or physical name. Values are passed through
standard input and value-bearing tasks use `no_log`.

When an operator value is absent, an existing provider secret is preserved.
For a missing RabbitMQ or Redis secret, the role generates a 256-bit hexadecimal
credential and uploads it once. Other secrets still require their declared
operator environment variable when they have not been provisioned yet.
