# Azure network module

Creates the resource group every other Azure module lives in, the VNet, the
management and workload subnets, one NAT gateway, role security, and — in cloud
database mode — the delegated subnet and private DNS zone Flexible Server needs.

## Placement follows the address, not the role

AWS puts the bastion *and* the UI in the management subnet; GCP puts only the
bastion there. A VM block written for either cloud therefore carries an
`internal_ip` that one of them would reject.

This module picks each VM's subnet by asking which configured CIDR contains its
`internal_ip`, so both layouts deploy here unchanged. The address is never
remapped and there is no role-based fallback: an address that no subnet
contains, or that two contain, resolves to no subnet and the apply fails.

Azure reserves the **first four and the last** address of every subnet, so the
usable range starts four addresses in. `10.0.0.2` — the address both shipped
examples used — is one of the reserved ones.

## Resources

| Resource | Purpose |
| --- | --- |
| `clouds.azure.resource_group_name` | Resource group; created and owned here, since a resource-group budget needs one even with no VMs |
| `<prefix>-vnet` | VNet spanning `clouds.azure.vnet_cidr` |
| `<prefix>-management`, `<prefix>-workload` | The two neutral subnets |
| `<prefix>-nat`, `<prefix>-nat-ip` | Outbound access for every subnet holding a VM without its own public address |
| `<prefix>-<role>-asg` | Application security group standing in for AWS source security groups / GCP source tags |
| `<prefix>-<role>-nsg` | Role security group, attached to the NIC by the VM module |
| `<prefix>-postgres` | Subnet delegated to `Microsoft.DBforPostgreSQL/flexibleServers`, cloud database mode only |
| `clouds.azure.postgres_network.private_dns_zone_name` | Private zone plus its VNet link |

## Why NIC-attached NSGs

A subnet association is one NSG per subnet, and the workload subnet holds four
roles. The NSGs therefore attach to each VM's network interface, and rules name
the source *role* through an application security group rather than an address.

## Ingress contract

| Rule | Source | Destination role | TCP ports |
| --- | --- | --- | --- |
| `bastion-ssh` | `vms.bastion.allowed_cidrs` | bastion | `vms.bastion.ssh_port` |
| `<role>-ssh` | bastion ASG | database, history, fetcher, ui | `22` |
| `ui-web` | `Internet` | ui | `network.ui_public_ports` |
| `history-api` | ui ASG | history | `service_ports.history_api` |
| `history-rabbitmq` | fetcher + history ASGs | history | `rabbitmq.port` |
| `database-postgresql` | fetcher + history ASGs | database | `service_ports.postgresql` |
| `<role>-deny-vnet` | `VirtualNetwork` | every role | everything else |

The last row matters: Azure's default rules allow *all* VNet-to-VNet traffic,
which would quietly undo every rule above it. Each role NSG denies that at
priority 4000, after its own allow rules.

## Outbound and the bastion's first boot

Azure grants a VM without a public address no outbound access at all, so the
NAT gateway is not an optimisation. It is attached only to subnets that
actually hold a private VM, which on the shipped examples means the workload
subnet alone.

There is no temporary port-22 rule for the bastion. Cloud-init writes the sshd
drop-in during first boot, so the bastion serves `vms.bastion.ssh_port` from the
start and nothing has to be opened and then removed.
