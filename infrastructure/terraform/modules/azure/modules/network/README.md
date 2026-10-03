# Azure network module

Creates the network foundation for one Azure deployment: the virtual network,
the management, workload and database subnets, and an optional NAT gateway for
the workload subnet.

It knows nothing about ports, roles or the bastion. Who may talk to whom lives
in the sibling [firewall module](../firewall/README.md), because that contract
changes with the application while this layout does not.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vnet` | The virtual network, carrying its own range like an AWS VPC |
| `<prefix>-management` | Subnet for the bastion |
| `<prefix>-workload` | Subnet for every workload, public address or not |
| `<prefix>-database` | Subnet for the managed database's private endpoint, only when `enable_database_subnet` |
| `<prefix>-nat`, `<prefix>-nat-ip` | NAT gateway and its address, attached to the workload subnet, only when `enable_nat_gateway` |

## How it differs from the other clouds

- **No route tables.** Azure routes between subnets and to the internet on its
  own. The NAT gateway is attached to the subnet; nothing points a route at it,
  and it does not need a public subnet to live in as it does on AWS.
- **Private subnets by default.** New subnets have no default outbound access,
  and every subnet here sets `default_outbound_access_enabled = false` so an
  older API default cannot turn it back on. A VM goes out through its own
  public address or through NAT.
- **Placement follows the address, not the subnet.** A public address works
  from any subnet, so the UI sits in the workload subnet with the rest - the
  opposite of AWS.
- **Five reserved addresses per subnet**, as on AWS: the bastion takes `.4`.
- **One database range**, for the private endpoint - where AWS needs two
  zones for a DB subnet group. The subnet enforces the security group on the
  endpoint (`private_endpoint_network_policies`), which Azure otherwise skips.

## Cost

A NAT gateway bills by the hour from the moment it exists, whether or not
anything routes through it. `enable_nat_gateway` lets the caller skip it when
every workload on this cloud has a public address.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every resource name |
| `resource_group_name`, `location` | Where the resources are created |
| `profile` | Cloud profile; `network_cidr`, `zone` and the subnet ranges are read |
| `enable_nat_gateway` | Whether any workload needs outbound access without a public IP |
| `enable_database_subnet` | Whether to create the database subnet from `subnets.database` |
| `tags` | Tags for every resource that takes them |

## Outputs

| Name | Description |
| --- | --- |
| `vnet_id`, `vnet_name` | The virtual network |
| `management_subnet_id`, `workload_subnet_id`, `database_subnet_id` | The subnets; the last is null without a database |
| `subnet_ids` | Every subnet by purpose, for the firewall module |
| `nat_gateway_id`, `nat_public_ip` | The NAT gateway and the address workloads appear to come from |

## License

GPL-2.0-or-later
