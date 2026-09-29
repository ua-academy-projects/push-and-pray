# Ansible Collection - oilscope.platform

Documentation for the collection.

## Validate configuration

Before deploying, validate your project configuration file against the schema:

```bash
uvx check-jsonschema \
  --schemafile project-config.schema.json \
  /absolute/path/project-config.json
```

## Deploy everything

Load the required secret values from their recovery source, then run the general
deployment from the repository root. Reuse the same values on subsequent runs;
changing an environment value requests a new cloud secret version.

```bash
ansible-playbook oilscope.platform.deploy \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook:

1. Synchronizes changed or missing cloud secret versions.
2. Prepares workload hosts with the baseline and Docker Engine.
3. Installs the CloudWatch Agent on AWS hosts, the Ops Agent on GCP hosts, or
   the Azure Monitor Agent VM extension on Azure hosts.
4. Deploys Infrastructure, History, Fetcher, and UI in dependency order.

The inventory groups select the monitoring agent automatically. The deployment
stops if a stage fails, preventing dependent workloads from being deployed.

## Bootstrap a K3s cluster

K3s uses a separate playbook from the Compose application deployment. After
Terraform has created the bastion, three server nodes, two agent nodes, and the
private API load balancer, it also creates a regional external passthrough load
balancer for ports 80 and 443. Its reserved address is reported as `ingress` in
the Terraform `public_ips` output and, when Cloudflare is configured, becomes
the A record for `k3s.application.hostname`.

The external load balancer targets only the agent nodes. Its TCP port 80 health
check is expected to report the agents as unhealthy until K3s starts bundled
Traefik. In the current configuration, no cluster VM receives a public IP.

Create one persistent cluster token and upload it to the cloud secret manager:

```bash
export K3S_TOKEN="$(openssl rand -hex 32)"

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json"
```

Keep the token in an independent recovery source. Reuse it on later runs; do
not generate a new value unless deliberately rotating the cluster token.

Bootstrap the embedded-etcd cluster and join the worker agents:

```bash
ansible-playbook oilscope.platform.k3s \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook installs the version pinned in `project-config.json`, initializes
the first server, joins the remaining servers one at a time through that
server's private address, joins the agents through the private load balancer,
waits for every node to become Ready, and writes the administrator kubeconfig
to `~/.kube/oilscope-<environment>.yaml`.
All server nodes are tainted `NoSchedule`, so application workloads are placed
on the agents unless they explicitly tolerate the control-plane taint.

The kubeconfig deliberately retains K3s's `https://127.0.0.1:6443` endpoint.
Keep the API private and reach it through the bastion from a second terminal:

```bash
ssh -N -L 6443:10.10.1.5:6443 \
  -p 8787 andri@<BASTION_PUBLIC_IP>
```

Then verify the cluster locally:

```bash
KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" kubectl get nodes -o wide
```

The IP address, SSH port, user, and environment-specific filename in these
examples come from the current `project-config.json`; adjust them when using
another configuration.

## Prepare K3s application secrets

The application deployment uses two Kubernetes Secrets. Terraform creates the
corresponding Google Secret Manager containers, but deliberately does not put
credential values in Terraform state. Export each value using the environment
variable derived from its configured container ID, then upload the versions:

```bash
export DB_PASSWORD="..."
export RABBITMQ_PASSWORD="..."
export RABBITMQ_ERLANG_COOKIE="..."
export REDIS_PASSWORD="..."
export EXTERNAL_API_KEY="..."
export GHCR_TOKEN="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json"
```

The names above match the container IDs in the current K3s configuration. The
mapping rule is documented in [the secrets guide](../../../../docs/secrets.md).

With the SSH tunnel to the private API still running, copy the current values
from Google Secret Manager into the cluster:

```bash
ansible-playbook oilscope.platform.synchronize_k3s_secrets \
  -i localhost, \
  -e k3s_secrets_config_file="$PWD/project-config.json"
```

This creates the configured namespace, `<name-prefix>-application` as an
Opaque Secret, and `<name-prefix>-registry` as the GHCR image-pull Secret. It
requires the local kubeconfig produced by the K3s playbook, an authenticated
`gcloud`, and the controller dependencies from `requirements.yml` and
`requirements.txt`.

## Deploy K3s add-ons

Keep the SSH tunnel to the private API running, then reconcile the cluster
add-ons from the local controller:

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```

The playbook currently installs the pinned cert-manager Helm chart as the
`cert-manager` release in the `cert-manager` namespace. It reads the release
overrides from `infrastructure/kubernetes/values/cert-manager.yaml`, waits for
the release to become ready, rolls back a failed installation, and creates the
`letsencrypt-production` ClusterIssuer for HTTP-01 challenges through Traefik.
The ACME account email comes from `k3s.application.acme_email` in the project
configuration. Repeated runs reconcile the same resources rather than creating
duplicates.

Helm, the Helm Diff plugin, and the local kubeconfig produced by the K3s
playbook must be available on the controller. Helm Diff prevents unchanged OCI
releases from producing unnecessary upgrades. The issuer does not request a
certificate by itself; the application Ingress makes that request when the
workloads are ready.

After certificate management is ready, the playbook installs PostgreSQL as a
standalone Helm release in the application namespace. Stable chart settings
live in `infrastructure/kubernetes/values/postgresql.yaml`; Ansible overlays the
configured storage size, PostgreSQL service port, and existing application
Secret name. The release uses an internal `ClusterIP` Service, a `local-path`
persistent volume, explicit resource requests and limits, and the
`POSTGRES_PASSWORD` Secret key for the `oil_tracker` user and database. The
database image is pinned by digest as well as the chart being pinned by version.

The playbook next installs a single-node RabbitMQ release. It uses the same
application Secret without placing credential values in Helm release metadata:
`RABBITMQ_PASSWORD` authenticates the `oil_tracker` user and
`RABBITMQ_ERLANG_COOKIE` supplies the Erlang cookie. RabbitMQ is internal-only,
uses the configured AMQP service port and `local-path` persistent volume, and
has explicit resource requests and limits. The CloudPirates chart is pinned by
version and its official RabbitMQ image is pinned by digest.

Finally, the playbook installs standalone Redis for the UI session store. The
CloudPirates chart uses the official Redis image pinned by digest, reads
`REDIS_PASSWORD` from the existing application Secret, and provisions the
configured service port and `local-path` volume. AOF persistence is enabled,
memory usage is bounded for the small K3s nodes, and Sentinel and metrics are
disabled.

The final add-on is an internal-only Headlamp dashboard in its own namespace.
It has only a `ClusterIP` Service: no Ingress, HTTPRoute, public load balancer,
DNS record, or firewall rule exposes it. The chart's automatic `cluster-admin`
binding is disabled. Ansible instead creates a separate `headlamp-admin`
ServiceAccount explicitly bound to `cluster-admin` for this private cluster.
With the private API tunnel running, access it from the controller and generate
a temporary login token:

```bash
KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp port-forward \
  service/headlamp 8088:80 \
  --address=127.0.0.1

KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp create token headlamp-admin --duration=8h
```

Open `http://127.0.0.1:8088` and paste the temporary token. The port-forward
process must remain running while Headlamp is in use. The token grants
unrestricted cluster access: treat it like a root credential, do not store it,
and close the port-forward when finished. The Headlamp Pod itself continues to
use a separate unprivileged ServiceAccount.

## Apply K3s database migrations

After the add-ons are ready, run the repository's existing database migration
container as a Kubernetes Job:

```bash
ansible-playbook oilscope.platform.migrate_k3s_database \
  -i localhost, \
  -e k3s_migrations_config_file="$PWD/project-config.json"
```

The Job uses the configured private `database` image, the existing Kubernetes
application and registry Secrets, and the configured internal PostgreSQL
Service port. It runs the schema selected for the RabbitMQ and Redis application
architecture and waits for completion before returning. Its deterministic name
changes with the database image tag, so an unchanged successful migration is
not run again. The runner's `DATABASE_MODE=managed` value selects that schema;
Terraform still uses `database.mode=self_managed` because PostgreSQL itself is
installed inside K3s rather than by a cloud database service.

## Deploy the K3s application

Deploy the repository-owned workloads after the data services and database
schema are ready:

```bash
ansible-playbook oilscope.platform.deploy_k3s_application \
  -i localhost, \
  -e k3s_application_config_file="$PWD/project-config.json"
```

The playbook runs the migration role first, then reconciles History, Fetcher,
and UI as plain Kubernetes Deployments. History and UI receive internal
`ClusterIP` Services; Fetcher initiates outbound work and needs no inbound
Service. Each workload uses the configured private image tag, the existing
image-pull Secret, and credential references to the application Secret. The
playbook waits for each Deployment to become available before continuing.

After the internal workloads are healthy, the final role creates a standard
Kubernetes Ingress that routes the configured hostname through Traefik to the
UI Service. Its cert-manager annotation requests a browser-trusted certificate
from the existing `letsencrypt-production` ClusterIssuer. The deployment waits
for the resulting Certificate to become ready before returning successfully.
A namespace-scoped Traefik Middleware redirects application HTTP requests to
HTTPS without affecting cert-manager's separate HTTP-01 solver Ingress.

## Upload secret versions

Terraform creates the AWS and GCP secret containers and the Azure Key Vault,
but it does not store their values. The general deployment only adds a version
when the latest enabled value differs. Force a new version for deliberate
rotation with:

```bash
ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json"
```

See [docs/secrets.md](../../../../docs/secrets.md) for provider requirements,
source variable naming, and rotation guidance.

## Configure GCP observability for Compose

The general Compose deployment configures observability automatically. K3s
mode deliberately does not create these policies or install the Ops Agent. To
reconcile only the GCP Ops Agent for a Compose deployment after Terraform has
granted the VM service accounts their Logging and Monitoring writer roles, run:

```bash
ansible-playbook oilscope.platform.configure_gcp_observability \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook exports host metrics from every GCP VM and collects Docker JSON
logs from workload VMs. It does not restart the application containers. See the
[`gcp_ops_agent` role](roles/gcp_ops_agent/README.md) for details.

## Configure AWS observability for Compose

To reconcile only the CloudWatch Agent after Terraform has attached its policy
to the EC2 instance roles, run:

```bash
ansible-playbook oilscope.platform.configure_aws_observability \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook publishes host metrics to the `OilScope` CloudWatch namespace,
sends system logs from every AWS instance, and sends Docker JSON logs from
workload instances. It does not restart the application containers. See the
[`aws_cloudwatch_agent` role](roles/aws_cloudwatch_agent/README.md) for details.

## Configure Azure observability for Compose

To reconcile only the Azure Monitor Agent extension after Terraform has
created the Log Analytics workspace and DCR associations, run:

```bash
ansible-playbook oilscope.platform.configure_azure_observability \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook installs the native VM extension on every Azure VM through the
Azure API. Azure workload Compose definitions send container output directly
through the AMA-collected `local0` facility. See the
[`azure_monitor_agent` role](roles/azure_monitor_agent/README.md) for details.

The UI deployment enables JSON Traefik access logs. Terraform derives request
and HTTP 5xx metrics from those records and creates the provider-specific VM and
HTTPS availability alerts and dashboard. See
[the cloud monitoring guide](../../../../docs/monitoring.md) for the ownership
model and required manual notification destinations.
