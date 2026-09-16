# Resolve secrets

Resolves the current VM's configured secrets through its attached cloud
identity. Values remain in the in-memory `resolve_secrets_result` fact.

The role derives the VM key from the inventory hostname and reads
`secret_mappings` from the shared `oilscope_config` variable.

## GCP

The role obtains an OAuth token from the GCE metadata server and accesses the
latest Secret Manager versions. Terraform grants each VM service account
`roles/secretmanager.secretAccessor` only on its mapped secrets.

## AWS

The role installs the Ubuntu `python3-boto3` package and uses Boto3 on the EC2
instance. Boto3 obtains credentials from the instance profile. Terraform
grants `secretsmanager:GetSecretValue` only on the VM's mapped secrets.

Only string secrets are supported. Both upload paths create string versions.

## Output

For this mapping:

```json
{
  "POSTGRES_PASSWORD": "oilscope-dev-db-password"
}
```

the role produces:

```yaml
resolve_secrets_result:
  POSTGRES_PASSWORD: resolved-value
```

Tasks that handle credentials or secret values use `no_log: true`.
