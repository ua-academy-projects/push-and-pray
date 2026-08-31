# Supported Ansible and Docker Compose deployment

The supported deployment path is the `oilscope.platform` Ansible collection.
It deploys one workload per VM in dependency order: Database, History, Fetcher,
and UI. Docker Compose remains the container runtime on each VM, but operators
do not install or start a shared all-in-one Compose project manually.

The `compose_project` role renders exactly one workload definition to
`/opt/oilscope/app/compose.yaml` on each VM:

| VM role | Installed services |
| --- | --- |
| `database` | PostgreSQL and the one-shot migration service |
| `history` | History API and PGMQ consumer |
| `fetcher` | Scheduled Fetcher |
| `ui` | UI service; Traefik is installed separately under `/opt/oilscope/proxy` |

Image references are rendered from `registry.repository` and
`registry.image_sha` in the external project configuration JSON. Runtime
secrets are read from Google Secret Manager and passed directly to the Ansible
tasks that invoke Compose. They are not written to `deployment.env`.

`compose.deployment.yaml.j2` is retained only for the legacy Terraform
cloud-init path. The Ansible role does not install it.

## Controller prerequisites

Install Ansible's Python and collection dependencies, authenticate with GCP,
and build this repository's collection:

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
gcloud auth application-default login

cd infrastructure/ansible/oilscope/platform
ansible-galaxy collection build --force
ansible-galaxy collection install oilscope-platform-*.tar.gz --force
cd ../../../..
```

Rebuild and reinstall the local collection after changing an inventory plugin,
playbook, or role. Ansible executes the installed collection, not the working
copy.

Validate the external project configuration before deploying:

```sh
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json
```

The referenced Secret Manager entries and current secret versions must already
exist. See [Secrets](secrets.md) for the upload workflow.

## Deploy all workloads

Run from the repository root:

```sh
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The playbook deploys Database first, applies migrations, then deploys History,
Fetcher, and UI. `any_errors_fatal` prevents dependent workloads from being
deployed after a failure.

To redeploy one workload, run its playbook directly, for example:

```sh
ansible-playbook oilscope.platform.history \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The available workload playbooks are `database`, `history`, `fetcher`, and
`ui`. Database must be healthy and migrated before the other workloads are
deployed; History must be healthy before UI is deployed.

## Runtime defaults

| Setting | Default | Purpose |
| --- | --- | --- |
| `POSTGRES_DB` | `oil_tracker` | Database name |
| `POSTGRES_USER` | `oil_tracker` | Database user |
| `DATABASE_PORT` | `5432` | PostgreSQL port |
| `DATABASE_SSLMODE` | `disable` | PostgreSQL TLS mode on the private network |
| `PGMQ_QUEUE` | `price_observations` | Queue name |
| `PGMQ_VISIBILITY_TIMEOUT_SECONDS` | `60` | History queue visibility timeout |
| `PGMQ_POLL_INTERVAL_SECONDS` | `1` | History polling interval |
| `PGMQ_MAX_ATTEMPTS` | `5` | Maximum message delivery attempts |
| `DATA_PROVIDER` | `oilpriceapi` | Fetcher provider |
| `FETCH_CRON_HOURS` | `0,6,12,18` | Fetch schedule hours |
| `FETCH_TIMEZONE` | `UTC` | Fetch schedule timezone |
| `FETCH_ON_STARTUP` | `true` | Fetch the latest slot after startup |
| `REQUEST_TIMEOUT_SECONDS` | `15` | One provider request timeout |
| `SESSION_TTL_SECONDS` | `2592000` | UI-session lifetime |
| `APPLICATION_PLATFORM` | `linux/amd64` | Application image platform |
| `APPLICATION_PULL_POLICY` | `always` | Application image pull policy |

Host addresses and secret values are resolved by the inventory and deployment
roles. Do not create a persistent environment file containing them.

See [VM deployment operations](vm-deployment-operations.md) for status, logs,
redeployment, and stopping containers.
