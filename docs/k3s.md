# K3s deployment

OilScope can run on a K3s cluster discovered from the same project JSON that
Terraform uses. The active multi-cloud topology uses three server nodes and one
agent:

- one server has `k3s_bootstrap: true` and initializes embedded etcd;
- two more servers join the bootstrap server, keeping the control-plane count odd;
- one agent runs workloads and owns the public application endpoint;
- the servers are split across Azure, AWS and GCP; Tailscale subnet routes
  connect their provider-private IPs without exposing Kubernetes ports publicly;
- public HTTP/HTTPS is allowed only on the node with `public_endpoint`.

## Deployment flow

Before K3s is touched, the deployment configures Tailscale and verifies both
its direct mesh and the approved private subnet routes. This keeps a future
multi-cloud cluster from joining through an untested network path. See
[`tailscale.md`](tailscale.md).

1. Terraform creates the selected AWS, GCP and Azure networks, security rules,
   identities, VMs, DNS and monitoring. In `kubernetes` database mode it does
   not create a provider-managed PostgreSQL service.
2. The dynamic inventory reads the project JSON and VM tags, then creates the
   `k3s_servers`, `k3s_agents` and `k3s_bootstrap` groups.
3. Ansible installs the pinned K3s release on the bootstrap server, reads its
   join token, and joins the remaining server and agent nodes.
4. The bootstrap node reads application credentials from Azure Key Vault by
   using its managed identity.
5. Ansible installs the CloudNativePG operator, creates a two-instance
   PostgreSQL cluster and waits for its writable Service.
6. Ansible creates Kubernetes Secrets in memory, submits the official
   cert-manager Helm chart to the K3s Helm controller, and applies the
   application manifests.
7. A migration Job prepares CloudNativePG before History, Fetcher and UI are
   deployed.
8. cert-manager obtains and renews a Let's Encrypt certificate by using a
   Cloudflare DNS-01 challenge. Plain NGINX runs on the public agent and exposes
   the UI with that certificate.

## Required secret values

Before deploying, set current values for these secret containers in the Azure
application Key Vault:

- `external-api-key`: OilPriceAPI credential;
- `ghcr-token`: GitHub classic PAT that can read the private GHCR package;
- `db-password`: PostgreSQL application password used by CloudNativePG;
- `rabbitmq-password`: RabbitMQ application password;
- `redis-password`: Redis password.

The ignored project JSON must also contain a Cloudflare API token with Zone DNS
Edit permission. Ansible passes it to cert-manager without writing it to a
rendered manifest.

In Kubernetes database mode, these values come from the application Key Vault
through the bootstrap VM's `secret_mappings`. Do not store secret values in
the project JSON or in Kubernetes YAML files.

The GHCR token must belong to `registry.username`, have `read:packages`, and be
allowed to access the private package. The tag in `registry.image_sha` must
exist for the `database`, `history`, `fetcher` and `ui` images.

## Commands

Create and review the infrastructure first:

```bash
terraform -chdir=infrastructure/terraform init
terraform -chdir=infrastructure/terraform plan -out=k3s-azure.tfplan
terraform -chdir=infrastructure/terraform apply k3s-azure.tfplan
```

Terraform cloud-init installs and authenticates Tailscale before the VMs are
handed to Ansible. Export the Tailscale provider credentials before the plan as
described in `tailscale.md`. Then run the connectivity check and deployment:

```bash
OILSCOPE_SSH_KEY="$HOME/.ssh/terraform_ed25519" \
  ./scripts/configure-ansible.sh --preflight-only

OILSCOPE_SSH_KEY="$HOME/.ssh/terraform_ed25519" \
  ./scripts/configure-ansible.sh
```

The second command installs Azure Monitor Agent, K3s and cert-manager, deploys the application
with NGINX, waits for the Let's Encrypt HTTPS endpoint, and prints node and pod status.

## Verification and troubleshooting

Run these commands through Ansible so you do not need a local kubeconfig:

```bash
ansible k3s_bootstrap \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -b -m ansible.builtin.command \
  -a 'k3s kubectl get nodes -o wide'

ansible k3s_bootstrap \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -b -m ansible.builtin.command \
  -a 'k3s kubectl get pods -n oilscope -o wide'

ansible k3s_bootstrap \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -b -m ansible.builtin.command \
  -a 'k3s kubectl get certificate -n oilscope'

ansible k3s_bootstrap \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -b -m ansible.builtin.command \
  -a 'k3s kubectl logs -n oilscope deployment/nginx'
```

Application logs remain available through `k3s kubectl logs`. Azure Monitor
Agent sends VM performance counters and Warning-or-higher syslog records to the
Log Analytics workspace. The Application Insights web test checks the public
HTTPS endpoint every five minutes; a returned HTTP 500 is a failed test and can
trigger the email action group.

RabbitMQ uses K3s `local-path` storage. This is suitable for the assignment and
a small development cluster, but the volume is tied to one node and is not a
high-availability production storage design.
