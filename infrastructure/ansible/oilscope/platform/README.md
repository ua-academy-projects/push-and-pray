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

Deploy the application workloads in dependency order:

1. Infra - PostgreSQL when the database is self-hosted, RabbitMQ and Redis
   when it is managed, and the schema migrations either way
2. History
3. Fetcher
4. UI

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

## A managed database

With `database.mode` set to `managed` in the project configuration, PostgreSQL
is Cloud SQL or RDS rather than a container, and the infra VM carries the
RabbitMQ broker and the Redis cache instead. Terraform creates the instance;
one extra playbook runs between `terraform apply` and the deployment, to give
the instance and the workloads one password to agree on without Terraform ever
holding it:

```bash
ansible-playbook oilscope.platform.managed_database_credentials   -e project_config_path=/absolute/path/project-config.json
```

The inventory plugin finds the database endpoint through the cloud API, so
nothing about the address is written down. See `docs/managed-database.md` for
the whole procedure, including moving data between the two modes.

## Ship logs and metrics

Every deployment playbook installs the cloud's observability agent alongside
Docker, so a deployed host already ships its journal — container output
included — and host metrics. To roll an agent change out on its own, without
touching a container:

```bash
ansible-playbook oilscope.platform.observability \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

See `docs/observability.md` for where the logs land and how to query them.
