# GCP network module

Creates the OilScope VPC foundation: management and workload subnets, Cloud
NAT, and role-based firewall rules for Bastion, Infra, History, Fetcher, and
UI.

## Network tags

The module exports one tag for every VM role:

```hcl
network_tags = {
  bastion  = "<prefix>-bastion"
  database = "<prefix>-infra"
  history  = "<prefix>-history"
  fetcher  = "<prefix>-fetcher"
  ui       = "<prefix>-ui"
}
```

The root module attaches the tag matching each provider-independent VM role.
The firewall contract does not use generic `app` or `db` tags.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vpc` | Custom-mode regional VPC without automatic subnets |
| `<prefix>-management` | Management subnet used by the bastion |
| `<prefix>-workload` | Application workload subnet with Private Google Access enabled |
| `<prefix>-router`, `<prefix>-nat` | Outbound internet access for the workload subnet |

## Ingress firewall contract

| Rule | Source | Destination | TCP ports |
| --- | --- | --- | --- |
| `<prefix>-allow-bastion-ssh` | `bastion_allowed_cidrs` | Bastion | `bastion_ssh_port` |
| `<prefix>-allow-bastion-ssh-bootstrap` | `bastion_allowed_cidrs` | Bastion | `22` (temporary and opt-in) |
| `<prefix>-allow-workload-ssh` | Bastion | Infra, History, Fetcher, UI | `22` |
| `<prefix>-allow-ui-web` | `0.0.0.0/0` | UI | `ui_public_ports` (`80` and `443`) |

Application service ports are not managed by this Terraform module. Other
ingress is blocked by Google Cloud's implied deny-ingress rule.

## Egress

Cloud NAT applies to the workload subnet. Egress remains permissive through
Google Cloud's implied allow-egress rule.

## Usage

```hcl
module "network" {
  source = "./modules/gcp-network"

  resource_prefix = local.resource_prefix
  network_config  = local.config.network
  vms             = local.config.vms
}
```

The module outputs the management and workload subnet IDs and the role-based
`network_tags` map.

## Access procedure

Add an operator's office or VPN CIDR to `bastion_allowed_cidrs`. The resulting
administration path is:

```text
operator -> bastion -> private workload VM
private workload VM -> Cloud NAT -> internet
```

Workload SSH is accepted only from instances carrying the bastion network tag.

The bootstrap rule is controlled by project configuration. When
`enable_bastion_ssh_bootstrap` is true, it is created only if the final
`bastion_ssh_port` is not already `22`. It uses the same operator CIDRs and
bastion target tag as the final SSH rule. Remove it immediately after Ansible
has configured and verified the final bastion port.
