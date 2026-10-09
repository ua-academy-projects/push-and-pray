# Azure network module

Creates the network foundation for one Azure deployment: the virtual network,
the management and workload subnets, and an optional NAT gateway for the
workload subnet.

It knows nothing about ports, roles or the bastion. Who may talk to whom lives
in the sibling [firewall module](../firewall/README.md), because that contract
changes with the application while this layout does not.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vnet` | The virtual network, carrying its own range like an AWS VPC |
| `<prefix>-management` | Subnet for the bastion |
| `<prefix>-workload` | Subnet for every node, public address or not |
| `<prefix>-nat`, `<prefix>-nat-ip` | NAT gateway and its address, attached to the workload subnet, only when `enable_nat_gateway` |

## How it differs from the other clouds

- **No route tables here.** Azure routes between subnets and to the internet
  on its own. The NAT gateway is attached to the subnet; nothing points a route
  at it, and it does not need a public subnet to live in as it does on AWS. The
  one route table there is - to the other clouds through the bastion - lives in
  the [routing module](../routing/README.md).
- **Private subnets by default.** New subnets have no default outbound access,
  and every subnet here sets `default_outbound_access_enabled = false` so an
  older API default cannot turn it back on. A VM goes out through its own
  public address or through NAT.
- **Placement follows the address, not the subnet.** A public address works
  from any subnet, so a node answering for the ingress sits in the workload
  subnet with the rest - the opposite of AWS.
- **Five reserved addresses per subnet**, as on AWS: the bastion takes `.4`.

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
| `tags` | Tags for every resource that takes them |

## Outputs

| Name | Description |
| --- | --- |
| `vnet_id`, `vnet_name` | The virtual network |
| `management_subnet_id`, `workload_subnet_id` | The subnets |
| `subnet_ids` | Every subnet by purpose, for the firewall module |
| `nat_gateway_id`, `nat_public_ip` | The NAT gateway and the address workloads appear to come from |

## License

GPL-2.0-or-later
