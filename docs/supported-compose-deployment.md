# Supported Docker Compose deployment

The supported production-style path is Terraform plus the
`oilscope.platform.deploy_workloads` Ansible playbook. Ansible renders one Compose file
per VM from the same `project_config_path`; target hosts pull immutable GHCR images and
receive secrets only through the parent Ansible process environment.

The older all-services `compose.deployment.yaml.j2` remains only for the legacy cloud-init
path. It is not the template installed by current Ansible roles.

## Mode-specific services

| Host | `self_hosted` | `managed` |
| --- | --- | --- |
| infra/database | PostgreSQL 18 with PGMQ, Redis, migration runner | RabbitMQ, Redis, migration runner |
| Fetcher | PGMQ publisher using PostgreSQL credentials | RabbitMQ publisher; no PostgreSQL credentials |
| History | PGMQ consumer and PostgreSQL writer | RabbitMQ consumer and managed PostgreSQL writer |
| UI | History client and Redis preferences | History client and Redis preferences |

Managed migrations connect with `sslmode=require` to private PostgreSQL 16 in RDS or
Cloud SQL. Migrations `001`, `002`, `003`, and `005` run; PGMQ-only migration `004` is
skipped. No local PostgreSQL container or PostgreSQL host port is started in managed mode.

## Deployment

Copy `project-config.example.json` to an ignored `project-config.json`, select
`default_cloud` and `database_mode`, validate it, and deploy in dependency order:

```sh
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json

ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The database play reconciles its two runtime services, waits for their Docker health
checks, and runs the one-shot migration container. History, Fetcher, UI, and Traefik are
then reconciled independently. Compose `up --detach --no-deps` does not coordinate across
VMs; playbook order does.

Relevant runtime variables are rendered or injected by the roles:

- self-hosted Fetcher and History: `DATABASE_HOST`, `DATABASE_PORT`,
  `POSTGRES_PASSWORD`, `DATABASE_SSLMODE=disable`, `MESSAGING_BACKEND=pgmq`;
- managed Fetcher: `RABBITMQ_HOST`, `RABBITMQ_PORT`, `RABBITMQ_PASSWORD`,
  `MESSAGING_BACKEND=rabbitmq`;
- managed History: the RabbitMQ variables plus managed `DATABASE_HOST`,
  `POSTGRES_PASSWORD`, and `DATABASE_SSLMODE=require`;
- UI: `HISTORY_SERVICE_URL`, `REDIS_HOST`, `REDIS_PORT`, and `REDIS_PASSWORD` only.

Do not put secret values in Compose, project JSON, shell arguments, or repository files.
See [Secrets](secrets.md) for provider-specific storage and resolution.

The archived earlier-sprint Vagrant implementation lives under
`infrastructure/legacy/vagrant`; it is retained for historical review and is not a current
deployment option.
