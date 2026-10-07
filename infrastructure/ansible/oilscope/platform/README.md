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

## Configure private VPC access with Tailscale

The bastion can advertise the configured VPC CIDR as a Tailscale subnet route.
Generate a reusable, ephemeral auth key carrying the `tag:oilscope-bastion`
tag, make it pre-approved if tailnet device approval is enabled, load it without
placing the value in shell history, and run the dedicated playbook. Reusability
allows the key to enroll replacement bastions after Terraform rebuilds;
ephemerality removes inactive bastion identities from the tailnet automatically.

```bash
export TAILSCALE_AUTH_KEY="$(cat)"
# Paste the key, then press Ctrl+D.

ansible-playbook oilscope.platform.configure_tailscale_subnet_router \
  -i infrastructure/ansible/inventory/oilscope.yml

unset TAILSCALE_AUTH_KEY
```

The role installs Tailscale from its official stable Ubuntu repository, enables
IPv4 forwarding, and advertises `network.vpc_cidr`. Approve the route from the
Tailscale admin console unless the tagged device is covered by an
`autoApprovers` policy. See the [Tailscale guide](../../../../docs/tailscale.md)
for the required tag and policy example.

After subnet routing works, install Technitium on the bastion and reconcile the
exact private Headlamp, Homepage, and Technitium console DNS zones:

```bash
export TECHNITIUM_ADMIN_PASSWORD="$(cat)"
# Paste a strong password, then press Ctrl+D.

ansible-playbook oilscope.platform.configure_private_dns \
  -i infrastructure/ansible/inventory/oilscope.yml

unset TECHNITIUM_ADMIN_PASSWORD
```

Configure the bastion's private address as a restricted Tailscale nameserver
for all three hostnames under `k3s.private_services`. Do not publish public
address records for them or configure Technitium as a global resolver. The
Tailscale guide contains the complete split-DNS and verification procedure.

## Prepare K3s application secrets

The application deployment uses three Kubernetes Secrets. Terraform creates the
corresponding Google Secret Manager containers, but deliberately does not put
credential values in Terraform state. Export each value using the environment
variable derived from its configured container ID, then upload the versions:

```bash
export DB_PASSWORD="..."
export EXTERNAL_API_KEY="..."
export GHCR_TOKEN="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json"
```

The names above match the container IDs in the current K3s configuration. The
mapping rule is documented in [the secrets guide](../../../../docs/secrets.md).

With the K3s API reachable through the approved Tailscale subnet route, copy
the current values from Google Secret Manager into the cluster:

```bash
ansible-playbook oilscope.platform.synchronize_k3s_secrets \
  -i localhost, \
  -e k3s_secrets_config_file="$PWD/project-config.json"
```

This creates the configured namespace, `<name-prefix>-application` as an
Opaque Secret, `<name-prefix>-postgresql-owner` as the CloudNativePG database
owner Secret, and `<name-prefix>-registry` as the GHCR image-pull Secret. It
requires the local kubeconfig produced by the K3s playbook, an authenticated
`gcloud`, and the controller dependencies from `requirements.yml` and
`requirements.txt`.

## Deploy K3s add-ons

With the K3s API reachable through Tailscale, reconcile the cluster add-ons
from the local controller:

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

Before certificate management, the add-on playbook customizes the K3s-managed
Traefik release. It schedules one anti-affined replica on each K3s agent and
uses `externalTrafficPolicy: Local`. Both the public GCP load balancer and
private Technitium records target those agents, so ingress remains redundant
while Kubernetes preserves the source address needed by private-service
allow-lists.

After certificate management is ready, the playbook installs the official,
pinned CloudNativePG operator Helm chart. Ansible then declares the configured
private `database` image as PostgreSQL 18 and creates the configured number of
database instances, with a minimum of two. The current configuration runs one
writable primary and one streaming replica, each with a `local-path` persistent
volume on a different Kubernetes node. Applications use the operator-managed
`postgresql-rw` Service so failover does not change their connection address.

CloudNativePG bootstraps the `oil_tracker` database with the dedicated
basic-auth Secret created by the secrets playbook. A declarative `DatabaseRole`
keeps the owner password synchronized with that Secret. A declarative
`Database` resource creates `hstore`, `pg_cron`, `pgcrypto`, and `pgmq` before
migrations run. RabbitMQ and Redis are not deployed: PGMQ provides durable
delivery and PostgreSQL stores expiring UI sessions.

The earlier standalone PostgreSQL, RabbitMQ, and Redis roles and values files
remain in the collection as historical, non-runnable reference code. They are
deliberately absent from `deploy_k3s_addons`; the active K3s configuration
schema contains only the CNPG data-service fields and secrets. Running those
roles would require restoring their legacy configuration fields and credentials
and must not be mixed with the active CloudNativePG deployment.

The final add-on is an internal-only Headlamp dashboard in its own namespace.
Its chart-managed Service remains `ClusterIP`; Ansible creates a separate
Traefik Ingress at `k3s.private_services.headlamp.hostname`. Technitium provides
split DNS to tailnet clients, while a Traefik IP allow-list admits only traffic
forwarded by the Tailscale subnet router. A separate DNS-01 issuer obtains the
publicly trusted certificate without publishing the endpoint in public DNS.
No public load balancer, public DNS record, or new cloud firewall rule is
created for Headlamp.

The chart's automatic `cluster-admin` binding is disabled. Ansible instead
creates a separate `headlamp-admin` ServiceAccount explicitly bound to
`cluster-admin` for this private learning cluster. Open the configured HTTPS
hostname from a tailnet client and generate a temporary login token:

```bash
KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp create token headlamp-admin --duration=8h
```

The token grants unrestricted cluster access: treat it like a root credential
and do not store it. The Headlamp Pod itself continues to use a separate
unprivileged ServiceAccount.

The add-on playbook also deploys a private HTTPS proxy for the bastion-hosted
Technitium console at `k3s.private_services.technitium.hostname`, followed by
Homepage at `k3s.private_services.homepage.hostname`. Terraform allows K3s
nodes to reach only the configured Technitium administration port. Homepage's
ConfigMap defines service cards and green or red server-side health checks for
OilScope, Headlamp, and Technitium. These private endpoints use DNS-01
certificates, source-address allow-lists, and permanent HTTPS redirects.
Homepage's compact header reports aggregate cluster CPU and memory first,
followed by the configured servers and agents. Its dedicated ServiceAccount can
only `get` and `list` core Nodes and `metrics.k8s.io` Nodes; it cannot read
workloads, Pods, Secrets, or ingress resources.

## Apply K3s database migrations

After the add-ons are ready, run the repository's existing database migration
container as a Kubernetes Job:

```bash
ansible-playbook oilscope.platform.migrate_k3s_database \
  -i localhost, \
  -e k3s_migrations_config_file="$PWD/project-config.json"
```

The Job uses the configured private `database` image, the existing Kubernetes
application and registry Secrets, and the `postgresql-rw` Service. It runs all
self-managed migrations, including PGMQ and PostgreSQL session persistence,
and waits for completion before returning. Its deterministic name changes with
the database image tag, so an unchanged successful migration is not run again.

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
