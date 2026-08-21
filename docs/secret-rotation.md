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
not contain the value. Workload service accounts receive access only to the
secret IDs assigned to their role in Terraform configuration.

To rotate a secret, run the same command with the new value. Applications must
be restarted by the deployment unit after rotation so they retrieve the new
version at startup.