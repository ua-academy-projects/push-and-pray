# AWS network module

Creates the VPC foundation for one AWS deployment: the VPC, a public and a
private subnet, an internet gateway, an optional NAT gateway, route tables, and
one security group per role with the ingress rules between them.

The module is called once per active cloud. It never sees the VM list - only
the ranges from the cloud profile, the shared service ports, and the bastion's
externally reachable SSH settings.

## Security groups instead of network tags

GCP matches firewall rules against tag strings at the network level. AWS
attaches a security group to the instance, and rules reference another group.
The module creates one group per scope and exports the map:

```hcl
security_group_ids = {
  bastion = "sg-..."
  infra   = "sg-..."
  history = "sg-..."
  fetcher = "sg-..."
  ui      = "sg-..."
}
```

The VM module attaches the groups matching each VM's `network_tags`.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vpc` | The VPC, carrying its own CIDR range |
| `<prefix>-public` | Subnet routed to the internet gateway - bastion and anything holding a public IP |
| `<prefix>-private` | Subnet routed through NAT |
| `<prefix>-igw` | Internet gateway |
| `<prefix>-nat`, `<prefix>-nat-ip` | NAT gateway and its address, only when `enable_nat_gateway` |
| `<prefix>-public`, `<prefix>-private` route tables | One default route each, plus their associations |
| `<prefix>-<scope>` | One security group per role |

## Ingress contract

| Rule | Source | Destination | TCP ports |
| --- | --- | --- | --- |
| `bastion_ssh` | `bastion.allowed_cidrs` | bastion group | `bastion.ssh_port` |
| `bastion_ssh_bootstrap` | `bastion.allowed_cidrs` | bastion group | `22` (temporary and opt-in) |
| `workload_ssh` | bastion group | infra, history, fetcher, ui groups | `22` |
| `history_api` | ui group | history group | `config.service_ports.history_api` |
| `postgresql` | fetcher, history, ui groups | infra group | `config.service_ports.postgresql` |
| `ui_web` | `0.0.0.0/0` | ui group | `config.network.ui_public_ports` (`443` only) |

## Egress is not free here

A GCP network permits all egress unless a rule denies it; an AWS security group
permits none unless a rule allows it. The module therefore creates an explicit
allow-all egress rule for every group. Without it no instance could pull a
container image, and nothing in the Terraform plan would hint at why.

## Two placement rules that differ from GCP

An AWS subnet is bound to one availability zone, so `profile.zone` is required
here where GCP needs nothing.

Reachability follows the route table, not the address: an Elastic IP on an
instance whose default route is the NAT gateway accepts inbound packets but
cannot answer them. Every VM holding a public IP therefore belongs in the
public subnet, which is why the caller places VMs by `assign_public_ip` rather
than by role.

## Cost

A NAT gateway bills by the hour from the moment it exists, whether or not
anything routes through it. `enable_nat_gateway` lets the caller skip it when
every VM on this cloud has a public address.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every resource name |
| `profile` | Cloud profile; `network_cidr`, `zone` and both subnet ranges are read |
| `config` | Project configuration; only `network.ui_public_ports` and `service_ports` are read |
| `bastion` | The bastion's `ssh_port` and `allowed_cidrs` |
| `enable_bastion_ssh_bootstrap` | Opt in to the temporary port 22 rule |
| `enable_nat_gateway` | Whether any VM needs outbound access without a public IP |
| `tags` | Tags for every resource |

## Outputs

| Name | Description |
| --- | --- |
| `vpc_id`, `vpc_arn`, `vpc_cidr_block` | The VPC |
| `availability_zone` | Zone both subnets are bound to |
| `public_subnet_id`, `public_subnet_cidr` | Subnet routed to the gateway |
| `private_subnet_id`, `private_subnet_cidr` | Subnet routed through NAT |
| `internet_gateway_id` | Internet gateway |
| `nat_gateway_id` | NAT gateway, or `null` when none is created |
| `nat_public_ip` | Address every private VM appears to come from - useful for upstream allowlisting |
| `public_route_table_id`, `private_route_table_id` | Route tables |
| `security_group_ids`, `security_group_names`, `security_group_arns` | Groups by scope |

## Usage

```hcl
module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  config          = var.config
  profile         = local.profile
  bastion         = local.bastion_vm

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  enable_nat_gateway           = local.needs_nat_gateway
  tags                         = local.common_tags
}
```

## License

GPL-2.0-or-later
