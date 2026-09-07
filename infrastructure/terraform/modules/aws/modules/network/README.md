# AWS network module

Creates the VPC foundation for one AWS deployment: the VPC, a public and a
private subnet, an internet gateway, an optional NAT gateway, and the route
tables that make the two subnets differ.

It knows nothing about ports, roles or the bastion. Who may talk to whom lives
in the sibling [firewall module](../firewall/README.md), because that contract
changes with the application while this layout does not.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vpc` | The VPC, carrying its own CIDR range |
| `<prefix>-public` | Subnet routed to the internet gateway - bastion and anything holding a public IP |
| `<prefix>-private` | Subnet routed through NAT |
| `<prefix>-igw` | Internet gateway |
| `<prefix>-nat`, `<prefix>-nat-ip` | NAT gateway and its address, only when `enable_nat_gateway` |
| `<prefix>-public`, `<prefix>-private` route tables | One default route each, plus their associations |

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
| `enable_nat_gateway` | Whether any VM needs outbound access without a public IP |
| `tags` | Tags for every resource |

## Outputs

| Name | Description |
| --- | --- |
| `vpc_id`, `vpc_arn`, `vpc_cidr_block` | The VPC; `vpc_id` is what the firewall module needs |
| `availability_zone` | Zone both subnets are bound to |
| `public_subnet_id`, `public_subnet_cidr` | Subnet routed to the gateway |
| `private_subnet_id`, `private_subnet_cidr` | Subnet routed through NAT |
| `internet_gateway_id` | Internet gateway |
| `nat_gateway_id` | NAT gateway, or `null` when none is created |
| `nat_public_ip` | Address every private VM appears to come from - useful for upstream allowlisting |
| `public_route_table_id`, `private_route_table_id` | Route tables |

## Usage

```hcl
module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  profile         = local.profile

  enable_nat_gateway = local.needs_nat_gateway
  tags               = local.common_tags
}
```

## License

GPL-2.0-or-later
