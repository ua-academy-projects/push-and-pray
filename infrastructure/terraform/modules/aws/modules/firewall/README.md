# AWS firewall module

Owns the ingress contract for one AWS deployment: which role may reach which
role, on which port. It creates one security group per role and the rules
between them.

Separate from the [network module](../network/README.md) on all three counts
the Terraform module guidance names:

- **Encapsulation** - a VPC and its subnets are deployed once and never
  change; these rules change whenever the application gains a port.
- **Privileges** - editing a CIDR layout and editing "who may reach PostgreSQL"
  are different responsibilities.
- **Volatility** - the network is long-lived, the contract is not.

The only thing it needs from the network is `vpc_id`.

## Security groups instead of network tags

GCP matches firewall rules against tag strings at the network level. AWS
attaches a security group to the instance, and rules reference another group.
The module owns the group per scope and exports the map:

```hcl
security_group_ids = {
  bastion = "sg-..."
  infra   = "sg-..."
  history = "sg-..."
  fetcher = "sg-..."
  ui      = "sg-..."
}
```

The VM module joins the groups matching each VM's `network_tags`.

## Ingress contract

| Rule | Source | Destination | TCP ports |
| --- | --- | --- | --- |
| `bastion_ssh` | `bastion.allowed_cidrs` | bastion group | `bastion.ssh_port` |
| `bastion_ssh_bootstrap` | `bastion.allowed_cidrs` | bastion group | `22` (temporary and opt-in) |
| `workload_ssh` | bastion group | infra, history, fetcher, ui groups | `22` |
| `history_api` | ui group | history group | `config.service_ports.history_api` |
| `postgresql` | fetcher, history, ui groups | infra group | `config.service_ports.postgresql` |
| `ui_web` | `0.0.0.0/0` | ui group | `config.network.ui_public_ports` (`443` only) |

Port 80 is deliberately closed. Traefik terminates TLS on 443 and solves the
ACME challenge with TLS-ALPN-01, so nothing ever listens on 80.

## Egress is not free here

A GCP network permits all egress unless a rule denies it; an AWS security group
permits none unless a rule allows it. The module therefore creates an explicit
allow-all egress rule for every group. Without it no instance could pull a
container image, and nothing in the Terraform plan would hint at why.

## The bootstrap rule

Disabled by default. When `enable_bastion_ssh_bootstrap` is true it is created
only if the final SSH port is not already `22`, once per allowed CIDR. Remove
it immediately after Ansible has configured and verified the final port.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every group name |
| `vpc_id` | The VPC these groups live in |
| `config` | Project configuration; only `network.ui_public_ports` and `service_ports` are read |
| `bastion` | The project-wide `bastion` block: its `ssh_port` and `allowed_cidrs` |
| `enable_bastion_ssh_bootstrap` | Opt in to the temporary port 22 rule |
| `tags` | Tags for every group and rule |

## Outputs

| Name | Description |
| --- | --- |
| `security_group_ids` | Group ID by scope, consumed by the VM module |
| `security_group_names`, `security_group_arns` | The same groups by name and ARN |
| `scopes` | The role scopes this contract is written in terms of |

## Usage

```hcl
module "firewall" {
  source = "./modules/firewall"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  vpc_id          = module.network[0].vpc_id
  config          = var.config
  bastion         = var.config.bastion

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  tags                         = local.common_tags
}
```

## License

GPL-2.0-or-later
