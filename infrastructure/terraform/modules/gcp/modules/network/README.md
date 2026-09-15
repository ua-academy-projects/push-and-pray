# GCP network module

Creates the VPC foundation for one GCP deployment: a custom-mode network, the
management and workload subnets, and Cloud NAT for outbound access.

It knows nothing about ports, roles or the bastion. Who may talk to whom lives
in the sibling [firewall module](../firewall/README.md), because that contract
changes with the application while this layout does not.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-vpc` | Custom-mode regional VPC without automatic subnets |
| `<prefix>-management` | Management subnet used by the bastion |
| `<prefix>-workload` | Workload subnet with Private Google Access enabled |
| `<prefix>-database` | Subnet for the managed database endpoint, only when `enable_database_subnet`; no NAT, no Private Google Access |
| `<prefix>-router`, `<prefix>-nat` | Outbound internet access for the workload subnet |

## Egress

Cloud NAT applies to the workload subnet. Egress stays permissive through
Google Cloud's implied allow-egress rule - unlike AWS, where the equivalent
module has to grant egress explicitly.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every resource name |
| `profile` | Cloud profile; only `subnets.management`, `subnets.workload` and `subnets.database` are read |
| `enable_database_subnet` | Whether to create the database subnet from the first range in `subnets.database` |

`profile` is a narrow object type, so the caller passes the whole profile and
the type documents exactly what is used.

## Outputs

| Name | Description |
| --- | --- |
| `network_id`, `network_name`, `network_self_link` | The VPC; `network_id` is what the firewall module needs |
| `region` | Region both subnets live in, derived from the provider |
| `management_subnet_id`, `_name`, `_cidr`, `_gateway` | Bastion subnet |
| `workload_subnet_id`, `_name`, `_cidr`, `_gateway` | Workload subnet |
| `database_subnet_id`, `database_subnet_cidr` | Database subnet, or `null` when none is created |
| `router_name`, `nat_name` | Cloud Router and Cloud NAT |

## Usage

```hcl
module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix = local.resource_prefix
  profile         = local.profile
}
```

## License

GPL-2.0-or-later
