# Secret rotation

Deployment secrets are supplied only through the environment of the process
running the deployment command. Do not put secret values in Terraform files,
command-line arguments, repository files, or CI logs.

Create or update Secret Manager versions with:

```sh
DB_PASSWORD='...' \
OILPRICEAPI_KEY='...' \
DB_PASSWORD_SECRET_ID='oil-tracker-db-password' \
OILPRICEAPI_KEY_SECRET_ID='oil-tracker-oilpriceapi-key' \
bash infrastructure/terraform/scripts/publish-secrets.sh
```

The script validates all required inputs before publishing the first version.
Each value is sent to `gcloud` through standard input and command output does
not contain the value. Terraform grants the deployment service account only
`roles/secretmanager.secretVersionAdder` on the configured secret IDs. Secret
containers and workload `secretAccessor` permissions belong to issue #55.

Issue #56 should invoke `infrastructure/terraform/scripts/load-runtime-secrets.sh`
immediately before starting the role's Compose command. The wrapper retrieves
secrets through the VM service account, exports them only to the child process,
and keeps its temporary Docker configuration under `/run` until that process exits.

To rotate a secret, run the same command with the new value. Applications must
be restarted by the deployment unit after rotation so they retrieve the new
version at startup.