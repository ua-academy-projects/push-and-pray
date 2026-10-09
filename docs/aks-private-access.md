# Private AKS dashboard access

With the Mac connected to the existing OilScope tailnet and its
`oilscope.internal` split-DNS rule enabled, use:

| AKS service | Private URL |
| --- | --- |
| Homepage | `http://homepage.oilscope.internal` |
| Grafana | `http://grafana.oilscope.internal` |
| Headlamp | `http://headlamp.oilscope.internal` |

The AKS Traefik chart has a separate `private` entry point. Three host-based
Ingress resources use only that entry point; the existing public OilScope UI
Ingress stays on the public entry points. An Azure internal LoadBalancer Service
exposes the private entry point to the original K3s VNet only. Reciprocal VNet
peering is owned by the isolated `infrastructure/terraform/managed-kubernetes`
state; the K3s Terraform resources and state are not moved or recreated.
The root `infrastructure/terraform` state remains K3s-only and refuses a
managed-mode plan or apply. Its backend prefix is `terraform/state`; the
managed AKS backend prefix is `terraform/managed-kubernetes`.

The existing Azure bastion runs an Ansible-managed HAProxy service bound only to
its Tailscale IPv4. It forwards the three names on port 80 to the AKS internal
load balancer over Azure private networking. The K3s primary keeps serving the
existing Tailscale-only split-DNS resolver, but its three records answer with
the bastion Tailscale IPv4 when `kubernetes.private_access_gateway` is
`bastion`. The bastion also forwards ports 30081, 30082, and 30083 to the K3s
primary, preserving the previous K3s dashboard URLs. No new Tailscale route or
split-DNS rule is required. No Mac hosts-file change is required.
Until the bastion proxy is running, the resolver keeps answering with the K3s
primary's Tailscale IPv4 even when `private_access_gateway` is `bastion`.

Grafana login and Headlamp token authentication remain enabled by their
existing deployments. The proxy does not issue tokens or store credentials.
Traffic from the Mac to the bastion is encrypted by Tailscale. The bastion to
AKS hop stays on Azure private networking. These dashboard URLs use HTTP within
that private path.

## Reconcile after the approved infrastructure change

Apply and review the **isolated managed Kubernetes Terraform plan** before
running the managed workload playbook. Keep `kubernetes.mode` set to
`managed` in `project-config.json`; the inventory discovers both the existing
K3s hosts and the managed controller, while the managed workload playbook
targets only the managed controller. The gateway playbook can then use the
same configuration to find the existing K3s primary and Azure bastion:

```sh
ansible-playbook oilscope.platform.deploy_managed_private_access \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path="$PWD/project-config.json"
```

The gateway playbook reads the AKS identity from the isolated Terraform state,
retrieves a temporary AKS kubeconfig, discovers the internal load balancer IP,
installs the Tailscale-only proxy on the bastion, then updates the existing
private DNS resolver. Re-running it reconciles the same resources. Normal K3s
workload deployment continues to keep the bastion DNS target because the
setting is in `project-config.json`.

If the existing tailnet split-DNS rule is absent, approve exactly one rule in
the Tailscale Admin Console: domain `oilscope.internal`, nameserver the K3s
primary's Tailscale IPv4. No `10.240.0.0/16` route approval is needed.
