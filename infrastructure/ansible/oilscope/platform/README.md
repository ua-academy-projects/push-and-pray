# Ansible Collection - oilscope.platform

Documentation for the collection.

## Validate configuration

Before deploying, validate your project configuration file against the schema:

​```bash
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json
​```

## Deploy all workloads

Deploy the application workloads in dependency order. First, export the selected
GCP database connection from the Terraform state as an Ansible extra-vars file:

```bash
terraform -chdir=infrastructure/terraform output -json \
  | jq '{database_connection: .gcp_database_connection.value, messaging_connection: .gcp_messaging_connection.value}' \
  > /tmp/oilscope-database-connection.json
```

The generated file contains the non-secret `mode`, private `host`, `port`,
`database_name`, and `username`. It does not contain the database password.

Then run the deployment:

- `self_managed`: Database, History, Fetcher, UI
- `managed`: History, Fetcher, UI; the Database playbook is skipped because
  Terraform creates Cloud SQL.

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json \
  -e @/tmp/oilscope-database-connection.json
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.
