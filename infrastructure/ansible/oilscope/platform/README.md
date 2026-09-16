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
database connection from the Terraform state as an Ansible extra-vars file:

```bash
terraform -chdir=infrastructure/terraform output -json \
  | jq '{database_connection: .database_connection.value, messaging_connection: .messaging_connection.value, session_connection: .session_connection.value}' \
  > /tmp/oilscope-database-connection.json
```

The generated file contains non-secret database, queue, and session-store connection
metadata, including the selected providers and private hosts. It contains no passwords.

Then run the deployment:

- `self_managed`: the infra VM runs PostgreSQL with PGMQ and PostgreSQL-backed sessions.
- `managed`: Cloud SQL/RDS stores application data while the infra VM runs RabbitMQ and Redis.

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json \
  -e @/tmp/oilscope-database-connection.json
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.
