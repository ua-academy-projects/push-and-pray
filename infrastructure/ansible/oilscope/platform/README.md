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

1. Database (self-hosted container in application mode; a no-op play in
   cloud mode)
2. Managed database migration (`migrate.yml` — a no-op in application mode)
3. RabbitMQ (`rabbitmq.yml`, on the History VM)
4. History
5. Fetcher
6. UI (also deploys Redis on the UI VM — see below)

Run from the repository root, through `infrastructure/ansible/deploy.sh`
rather than `ansible-playbook` directly, using whichever inventory matches
the configuration's `default_cloud` — see
[inventory/README.md](../../inventory/README.md) for setup and the
`oilscope_cloud`/`oilscope_vm_key` contract both inventories expose:

```bash
# GCP
infrastructure/ansible/deploy.sh oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json

# AWS
infrastructure/ansible/deploy.sh oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path=/absolute/path/project-config.json
```

`deploy.sh` takes exactly the same arguments as `ansible-playbook` - it's a
thin wrapper, not a replacement command - and refuses to report success when
the inventory/`--limit` combination given ends up matching zero hosts across
the whole run. That case can't be caught from inside the playbook itself:
`--limit` intersects with every play's own `hosts:` pattern independently
(including the preflight checks below), so a `--limit` that happens to
exclude every host in every play - `localhost` included - means nothing
inside Ansible's own execution model ever runs to catch it either. Plain
`ansible-playbook` remains fine for read-only commands
(`--syntax-check`, `--list-hosts`, `ansible-inventory --graph`, ...).

Every playbook validates `OILSCOPE_SSH_USER` against the configuration's
`ssh_users` before connecting to anything — see the SSH section of the
inventory README if that fails.

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

## Database connection selection

Fetcher and History run `database_connection` before Compose rendering — UI
does not, since its session store moved to Redis and it has no PostgreSQL
connection to resolve. Application mode uses the database inventory host and
JSON service port. Managed mode requires `terraform_outputs_path`, pointing to
a freshly exported full `terraform output -json` file for the correct applied
deployment. Add this extra-var to the existing deployment command. The role
installs the CA bundle and configures `verify-full`. The full deployment runs
`migrate.yml` on the first History host before services start; its
`database_migrate` role provisions runtime logins and applies cloud
migrations using controller-retrieved admin credentials. See [the role
contract](roles/database_connection/README.md).

## RabbitMQ and Redis deployment

RabbitMQ (Fetcher-to-History messaging) and Redis (UI sessions) run in every
database mode, on both clouds, as their own Compose projects on already-
provisioned VMs — no dedicated broker/cache VM or managed product is
provisioned for either.

`rabbitmq.yml` (imported from `deploy_workloads.yml`, after `migrate.yml` and
before `history.yml`) targets the History host matching
`rabbitmq.host_vm` in the project configuration, generates a self-signed TLS
certificate, and provisions the vhost/exchange/queue/retry/dead-letter
topology via the `rabbitmq` role. `broker_connection` (run by `fetcher.yml`
and `history.yml`, after `database_connection`/`resolve_secrets` and before
`compose_project`) resolves that host from inventory, installs its CA bundle
locally, and builds each service's `RABBITMQ_*` connection environment — a
misconfigured `rabbitmq.host_vm` that matches no discovered History host
fails loudly rather than silently proceeding with an unresolved connection.

Redis has no standalone playbook: the `redis` role runs directly from
`ui.yml` (after `resolve_secrets`, before `compose_project`), since it's
always co-located with UI on a single host asserted by
`redis.host_vm` matching that host's own `oilscope_vm_key`. It builds
`REDIS_URL`/`REDIS_KEY_PREFIX`/`SESSION_TTL_SECONDS` directly for UI to
consume.

Both roles' non-secret settings (image, ports, topology names, resource
limits, TLS/AOF behavior) come from the `rabbitmq`/`redis` objects in the
project configuration — see `project-config.example.json` for the reference
values. Passwords go through the existing secret-manager/`secret_mappings`
mechanism, never the JSON file itself.
