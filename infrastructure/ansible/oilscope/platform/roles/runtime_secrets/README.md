# Runtime secrets

Reads the workload's permitted Secret Manager values immediately before its
service role runs. Requests execute on the managed VM, using the VM service
account token from the GCP metadata service, so IAM keeps access host-scoped.

## Variables

- `runtime_secrets_project_id`: GCP project containing the configured secrets.
- `runtime_secrets_mappings`: the workload's non-secret `secret_mappings`
  dictionary from the project configuration.

The role registers responses as `runtime_secrets_access_results`. A consuming
service role selects the required mapping key and decodes its payload directly.
Token and payload tasks use `no_log`; values are not written to files or facts.

## Example

```yaml
- role: oilscope.platform.runtime_secrets
  vars:
    runtime_secrets_project_id: example-project-12345
    runtime_secrets_mappings:
      POSTGRES_PASSWORD: example-db-password
```
