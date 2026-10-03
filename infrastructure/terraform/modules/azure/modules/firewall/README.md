# Azure firewall module

Creates the traffic contract between the bastion, the workloads and the
internet: one application security group per scope, and one network security
group attached to every subnet that holds all the rules.

## Scopes

`bastion`, `infra`, `history`, `fetcher`, `ui` - the same five GCP expresses as
network tags and AWS as security groups. On Azure a scope is an application
security group, and a VM joins it through its network interface; the
[VM module](../vm/README.md) makes the association.

Azure sits between the other two. The rules live in one place for the whole
network, as GCP firewall rules do; the target is decided by membership, as with
AWS security groups, not by a string anyone may write on a VM.

## Rules

| Priority | Rule | From | To | Port |
| --- | --- | --- | --- | --- |
| 100 | `allow-bastion-ssh` | `bastion.allowed_cidrs` | bastion | `bastion.ssh_port` |
| 110 | `allow-bastion-ssh-bootstrap` | `bastion.allowed_cidrs` | bastion | 22, only with `enable_bastion_ssh_bootstrap` |
| 120 | `allow-workload-ssh` | bastion | infra, history, fetcher, ui | 22 |
| 130 | `allow-ui-web` | Internet | ui | `network.ui_public_ports` |
| 140 | `allow-history-api` | ui | history | `service_ports.history_api` |
| 150 | `allow-postgresql` | fetcher, history, ui | infra | `service_ports.postgresql`, self-hosted mode |
| 160, 170 | `allow-amqp`, `allow-redis` | fetcher, history, ui | infra | `service_ports.amqp`, `.redis`, managed mode |
| 180 | `allow-database` | fetcher, history, ui, infra | database subnet | 5432, added by the database module |
| 4000 | `deny-vnet-inbound` | VirtualNetwork | VirtualNetwork | everything, **deny** |

The last rule is the one the other clouds do not need. GCP and AWS refuse
traffic between instances unless a rule allows it; an Azure security group
starts with `AllowVnetInBound`, which admits everything inside the network.
`deny-vnet-inbound` restores the default-closed contract. The load balancer
probe rule Azure adds stays in force, and outbound traffic is not touched.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for every resource name |
| `resource_group_name`, `location` | Where the groups are created |
| `subnet_ids` | Every subnet the security group is attached to |
| `config` | Project configuration; `network` and `service_ports` are read |
| `bastion` | `ssh_port` and `allowed_cidrs` |
| `enable_bastion_ssh_bootstrap` | Adds the temporary port-22 rule |
| `database_managed` | Chooses what the infra scope admits |
| `tags` | Tags for the groups |

## Outputs

| Name | Description |
| --- | --- |
| `application_security_group_ids` | Group ID by scope |
| `network_security_group_id`, `network_security_group_name` | The security group, for modules that add rules to it |
| `scopes` | The scope names |

## License

GPL-2.0-or-later
