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
private API load balancer, create one persistent cluster token and upload it to
the cloud secret manager:

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

## Configure GCP observability

The general deployment configures observability automatically. To reconcile
only the GCP Ops Agent after Terraform has granted the VM service accounts
their Logging and Monitoring writer roles, run:

```bash
ansible-playbook oilscope.platform.configure_gcp_observability \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook exports host metrics from every GCP VM and collects Docker JSON
logs from workload VMs. It does not restart the application containers. See the
[`gcp_ops_agent` role](roles/gcp_ops_agent/README.md) for details.

## Configure AWS observability

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

## Configure Azure observability

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
