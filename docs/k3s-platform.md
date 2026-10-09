# CNPG and private Headlamp

## Architecture and database modes

The Ansible controller installs the pinned CloudNativePG Helm chart into
`cnpg-system`, using the existing temporary SSH tunnel to the K3s API. No K3s
HelmChart resource is used. In `postgres_extensions`, the `oilscope-db` Cluster
has two PostgreSQL 18 instances on distinct nodes, each with a 2Gi `local-path`
PVC, requests of 100m CPU / 256Mi memory, and limits of 1 CPU / 512Mi memory.
At least two schedulable nodes are required. Replication is asynchronous;
local-path storage is tied to its node and two replicas are not a backup.

Applications connect through `oilscope-db-rw.oilscope.svc.cluster.local:5432`
using the existing `DATABASE_URL` Secrets and `sslmode=require`. CNPG manages
the service's primary endpoint and its own database TLS certificates. Application
replica counts are unchanged. A pod-template endpoint annotation triggers a
rollout when the database address changes.

`managed` retains the private cloud endpoint and existing database role and
migration playbook. It skips CNPG and keeps the existing Redis/RabbitMQ paths.
Headlamp is installed in both modes. Switching modes does not delete existing
CNPG resources or migrate data between databases.

The actual previous self-hosted path was Compose on the first K3s server;
there were no Kubernetes PostgreSQL resources to remove. The standalone
Compose playbook remains available. **CNPG bootstraps a new database. Existing
Compose data is not copied or deleted.** If that data must be retained, arrange
a separate export/import and cutover with writers stopped before running the
workload deployment below; do not point live applications at an empty database.

## Image, extensions, secrets, and migrations

`Dockerfile.database-cnpg` derives from the existing digest-pinned PostgreSQL
18/PGMQ image and builds pg_cron 1.6.7 from a checksum-verified source archive.
It runs as the image's postgres UID/GID 999; CNPG supplies the entrypoint.
`push-k3s-images.sh` publishes it as `database-cnpg:18-$OILSCOPE_IMAGE_TAG`
through the same ECR, Artifact Registry, or ACR abstraction as application
images. Use a new immutable tag for each image or migration change.

| Extension | Current use | Provisioning |
| --- | --- | --- |
| pgmq | Fetcher queue; History reads/archives events | Existing pinned image; migration 004 |
| hstore | UI session preferences | PostgreSQL contrib in base image; migration 003 |
| pgcrypto | UI session ID hashing with `digest()` | PostgreSQL contrib in base image; migration 003 |
| pg_cron | Expired-session cleanup and UI readiness | Compiled into image; preload + migration 003 |

Only pg_cron requires preloading here. `cron.database_name` is the configured
application database; background workers run its jobs. No package installation
occurs inside running pods. The image includes the unchanged repository SQL files.

Existing cloud secrets `db-password-admin/history/fetcher/ui` become CNPG
basic-auth Secrets. The database owner and application logins remain named from
`database.admin_user`; all are non-superusers. The owner uses the existing admin
password, and application roles inherit its object privileges. `postgres` and
system database names cannot be used for the application owner/database.
Remote superuser login is disabled. Secret-bearing tasks use `no_log`.

Deployment order is operator → Cluster → two ready instances and reconciled
roles → extensions and SQL migrations on the primary → application workloads.
The local postgres socket permits administrative migration execution without
a superuser password. A private checksum ledger skips unchanged SQL on repeat
runs; the existing idempotent SQL can retry after interruption. The UI receives
SELECT access only to its cleanup job through a pg_cron row-security policy.

## Deploy from the repository root

Prerequisites: an existing reachable K3s cluster, working cloud credentials,
Terraform state, Docker buildx, Helm, kubectl, and the normal controller/SSH
setup. Run Python dependency installation in the Python environment used by
Ansible; Azure also needs its collection's SDK requirements as documented in
[inventory setup](../infrastructure/ansible/inventory/README.md).

```sh
export OILSCOPE_PROJECT_CONFIG="$PWD/project-config.json" # or your external path
export OILSCOPE_IMAGE_TAG="cnpg-dev-001"                 # use a new tag per build

python3 -m pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
ansible-galaxy collection build infrastructure/ansible/oilscope/platform --output-path /tmp --force
ansible-galaxy collection install /tmp/oilscope-platform-0.1.0.tar.gz --force

terraform -chdir=infrastructure/terraform plan \
  -var="project_config_path=$OILSCOPE_PROJECT_CONFIG" -out=/tmp/oilscope-cnpg.tfplan
# Review the plan before applying; it may also include existing local changes.
terraform -chdir=infrastructure/terraform apply /tmp/oilscope-cnpg.tfplan
bash scripts/push-k3s-images.sh

ansible-playbook oilscope.platform.deploy_k3s_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml
```

Reuse the existing uploaded application secrets; provision missing ones through
the [existing secret workflow](secrets.md). Keep `CLOUDFLARE_API_TOKEN` available
when the existing configuration enables HTTPS. For an initial complete cluster
deployment, use `oilscope.platform.deploy_workloads` instead; it also runs the
existing node setup and, in managed mode, database preparation. For managed
database migration updates on an existing cluster, run `oilscope.platform.database`
before `oilscope.platform.deploy_k3s_workloads` with the same inventory.

## Verify after deployment

Use a local admin kubeconfig with private API access. Ansible's temporary
kubeconfig is deleted at the end of deployment. Alternatively, run the cluster
checks on the primary server after defining `kubectl() { sudo k3s kubectl "$@"; }`.
The CNPG checks below apply only to `postgres_extensions`.

```sh
kubectl -n cnpg-system get deployments,pods
kubectl -n oilscope get clusters.postgresql.cnpg.io oilscope-db
kubectl -n oilscope get pods -l cnpg.io/cluster=oilscope-db -o wide
kubectl -n oilscope get pvc -l cnpg.io/cluster=oilscope-db
kubectl -n oilscope get svc oilscope-db-rw
kubectl -n oilscope get endpointslices -l kubernetes.io/service-name=oilscope-db-rw

primary=$(kubectl -n oilscope get clusters.postgresql.cnpg.io oilscope-db -o jsonpath='{.status.currentPrimary}')
dbname=$(kubectl -n oilscope get clusters.postgresql.cnpg.io oilscope-db -o jsonpath='{.spec.bootstrap.initdb.database}')
kubectl -n oilscope exec "$primary" -c postgres -- \
  psql -h /controller/run -U postgres -d "$dbname" -c \
  "SELECT extname, extversion FROM pg_extension WHERE extname IN ('pgmq','pg_cron','hstore','pgcrypto') ORDER BY extname;"
kubectl -n oilscope exec "$primary" -c postgres -- \
  psql -h /controller/run -U postgres -d "$dbname" -c \
  "SELECT jobname, database, active FROM cron.job;"

# Actual application credentials and service DNS; does not print connection URLs.
for app in history ui; do
  kubectl -n oilscope exec "deployment/$app" -- python -c \
    'import os, psycopg; c=psycopg.connect(os.environ["DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://", 1), connect_timeout=5); print(c.execute("SELECT current_user, current_database(), pg_is_in_recovery()").fetchone()); c.close()'
done
kubectl -n oilscope logs deployment/fetcher --tail=50
kubectl -n oilscope logs deployment/history --tail=50
kubectl -n oilscope exec deployment/ui -- python -c \
  'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:8080/health").read().decode())'
```

Expect two ready database pods on distinct nodes, four extension rows, an active
cleanup job, and `pg_is_in_recovery() = false` from both application connections.
CNPG supplies the `oilscope-db-rw` and `oilscope-db-ro` Services; no separate
PostgreSQL Service is defined. History, Fetcher, and UI use `-rw` because all
three write in `postgres_extensions` mode (the UI updates session rows even
while reading them). The custom pgmq-based database image runs with UID/GID
999, so the Cluster keeps those explicit IDs instead of CNPG's default 26.
Its data and WAL volumes both use `local-path`; adding `walStorage` to an
already running Cluster requires a separately reviewed storage migration.
Fetcher logs should show successful publication after its next scheduled fetch;
History logs should show consumption. In managed mode, only History has a DB
connection; UI uses Redis instead.

## Private Headlamp access

The pinned Headlamp chart runs in namespace `headlamp` with a NodePort service
on TCP 30081, no Ingress, and no LoadBalancer. The cloud firewall permits this
port only from that cloud's bastion. A Tailscale client can reach it through
the bastion subnet route using a private node IP. Its chart-created cluster-admin
binding is disabled. The declarative `headlamp-viewer` ServiceAccount retains its
existing name so current tokens continue to work; a separate `headlamp-admin`
ClusterRoleBinding now grants it `cluster-admin` across all namespaces, including
access to Secrets and workload changes. Port-forward restricts network exposure,
but anyone holding this token has full cluster access. No persistent token is
created. The primary server runs a small resolver on its Tailscale address.
After the one-time tailnet split-DNS entry for `oilscope.internal` points to
that address, open `http://headlamp.oilscope.internal:30081`,
`http://homepage.oilscope.internal:30082`, or
`http://grafana.oilscope.internal:30083` while connected to the tailnet.
When the private AKS gateway is enabled, the same K3s URLs pass through the
Tailscale-only bastion proxy; the [AKS dashboards](aks-private-access.md) use
the same names without port numbers.
No client hosts-file entry, SSH tunnel, or port-forward is needed. Grafana
uses a separate private NodePort; none of these services has a public Ingress.
Homepage has a separate NodePort and read-only access to node/pod metrics;
its application and Headlamp links include internal health checks. The metrics
overview depends on a working metrics-server and does not replace monitoring.

To apply only this RBAC change to an existing cluster, run from the repository
root with an administrator kubeconfig (the template contains no variables):

```sh
kubectl apply -f infrastructure/ansible/oilscope/platform/roles/k3s_workloads/templates/headlamp-rbac.yaml.j2
```

On the machine with your private kubeconfig:

```sh
kubectl -n headlamp get pods,svc
kubectl auth can-i get secrets --all-namespaces --as=system:serviceaccount:headlamp:headlamp-viewer
kubectl auth can-i patch deployments --all-namespaces --as=system:serviceaccount:headlamp:headlamp-viewer
kubectl -n headlamp create token headlamp-viewer --duration=1h
```

Both permission checks should return `yes` after deployment. Existing unexpired
`headlamp-viewer` tokens gain the same permissions; refresh Headlamp to see them.
Open the private Headlamp hostname and paste the temporary token. Keep the
token local. The hostname is resolved through the tailnet's split DNS.

## Verification limits

Local syntax/render checks do not establish image build success, CRD admission,
cloud registry access, scheduling capacity, replication/failover, migration
execution, extension compatibility, or Headlamp login. These require the live
environment. No image build, deployment, data import, or live checks were run.
