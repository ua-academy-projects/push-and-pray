# Cross-cloud networking with Tailscale

OilScope uses exactly one administrative bastion. Terraform installs Tailscale
on every VM during first boot, before Ansible needs SSH access. In every active
cloud, the alphabetically first K3s server advertises that cloud's private CIDR.
The bastion and all other nodes accept these routes, so Ansible and K3s continue
to use the VMs' real `10.x.x.x` internal addresses.

## Address plan

Cloud networks must not overlap:

- AWS: `10.0.0.0/16`
- GCP: `10.1.0.0/16`
- Azure primary region: `10.2.0.0/16`
- Azure `america-east`: `10.3.0.0/16`

Terraform derives advertised routes from the project JSON and validates that
each workload cloud contains a K3s server. It also validates that the complete
configuration contains exactly one bastion.

## What Terraform manages

The reusable Terraform implementation lives in
`infrastructure/terraform/modules/tailscale`. The root `tailscale.tf` only
selects routers, derives provider CIDRs, validates the topology and calls that
module.

When `tailscale.enabled` is true, Terraform:

1. manages the development tailnet policy and route auto-approvers;
2. creates a reusable, pre-authorized, tagged bootstrap key with a short expiry;
3. renders the official Tailscale cloud-init module for every VM;
4. installs Tailscale while each VM boots;
5. makes all VMs accept subnet routes;
6. enables forwarding and advertises the private CIDR only on the selected K3s
   router in each cloud.

The generated bootstrap key is sensitive but is present in Terraform state and
VM cloud-init metadata. It expires quickly and Terraform replaces it when it is
invalid. The VM modules ignore later changes to their boot payload, so rotating
the key does not restart or replace running VMs. Protect the Terraform state and
never commit a state file.

Cloud-init runs only when a VM is first created. If Tailscale is added to VMs
that already exist, replace those VMs once in a reviewed Terraform plan, or use
the Ansible role's emergency `OILSCOPE_TAILSCALE_AUTH_KEY` recovery path while
the hosts are still reachable. A fresh deployment needs no manual per-cloud
Tailscale setup.

The `tailscale_acl` resource manages the entire tailnet policy. With
`manage_policy: true`, the first apply intentionally replaces the existing
policy with the OilScope development policy. Use a dedicated development
tailnet, or set `manage_policy: false` if another system owns that policy.

## One-time provider credential

Terraform still needs permission to call the Tailscale API. This is a tailnet
credential, not a separate AWS, GCP or Azure configuration.

For the first apply, export a Tailscale API key and tailnet identifier:

```bash
read -rsp "Tailscale API key: " TAILSCALE_API_KEY
export TAILSCALE_API_KEY
export TAILSCALE_TAILNET="your-tailnet-id"
echo
```

The provider also supports OAuth credentials after the `tag:oilscope` ownership
policy exists:

```bash
export TAILSCALE_OAUTH_CLIENT_ID="..."
read -rsp "Tailscale OAuth secret: " TAILSCALE_OAUTH_CLIENT_SECRET
export TAILSCALE_OAUTH_CLIENT_SECRET
export TAILSCALE_TAILNET="your-tailnet-id"
echo
```

Do not put these provider credentials into `dev.json`, Terraform variables or
Git.

## Project configuration

```json
"tailscale": {
  "enabled": true,
  "manage_policy": true,
  "tag": "tag:oilscope",
  "auth_key_expiry_seconds": 3600
}
```

## Deployment

```bash
terraform -chdir=infrastructure/terraform init -upgrade
terraform -chdir=infrastructure/terraform plan -out=multi-cloud.tfplan
terraform -chdir=infrastructure/terraform apply multi-cloud.tfplan

unset TAILSCALE_API_KEY
unset TAILSCALE_OAUTH_CLIENT_ID
unset TAILSCALE_OAUTH_CLIENT_SECRET
```

Cloud-init completes the initial Tailscale connection. Ansible then checks the
direct mesh and routed SSH before it changes Kubernetes:

```bash
OILSCOPE_SSH_KEY="$HOME/.ssh/terraform_ed25519" \
  ./scripts/configure-ansible.sh --preflight-only

OILSCOPE_SSH_KEY="$HOME/.ssh/terraform_ed25519" \
  ./scripts/configure-ansible.sh
```

## Verification

In the Tailscale Machines page:

- every OilScope VM should be online;
- only the selected K3s server in each active cloud should advertise subnets;
- routes should already be approved by the managed policy.

The Ansible play runs `tailscale ping` and then opens TCP/22 through the routed
private addresses. A failed check stops deployment before K3s is changed.

The current `dev.json` places the bootstrap server and agent in Azure, the
second server in AWS, and the third server in GCP. The selected server in each
cloud advertises `10.2.0.0/16`, `10.0.0.0/16`, and `10.1.0.0/16` respectively.
