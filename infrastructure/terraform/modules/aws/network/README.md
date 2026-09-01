# AWS network

The AWS half of the network contract. Builds a VPC with a public management
subnet for the bastion and the NAT gateway, and a private workload subnet whose
egress goes through that gateway.

Public means routed to the internet gateway, and in AWS that routing belongs to
the subnet rather than to the instance: an Elastic IP on an instance in the
workload subnet accepts no inbound traffic. Any VM that asks for a public IP
therefore belongs in the management subnet, which is what the root module does
for this cloud.

It is the counterpart of `modules/gcp/network` and takes the same variables,
with three additions AWS needs and GCP does not: `vpc_cidr` (Compute Engine
derives its network from the subnets), `availability_zone`, and `tags`.

## Security groups instead of network tags

Compute Engine firewall rules select instances by tag. AWS has no such thing:
the equivalent is one security group per logical group, referenced by ID from
the rules that allow traffic between them.

`workload_groups` returns the mapping from logical name to identifier, so the
root module wires VMs identically in both clouds - it never learns whether it
is passing a tag or a security group ID.

Egress is also explicit here. GCP allows it by default and the GCP module
writes no egress rules; AWS denies it unless stated, so the same effective
policy has to be written out.

## Cost

The NAT gateway is billed per hour from creation plus per GB processed, and it
is not part of the AWS free tier. Roughly $33 a month before any traffic. It is
here because the workload subnet must stay private and still reach the
container registry and the Secrets Manager API. Destroy environments that are
not in use.

## Variables

- `resource_prefix`: prefix for every resource name.
- `vpc_cidr`: CIDR of the VPC; both subnets must fall inside it.
- `availability_zone`: zone hosting both subnets, resolved from the portable
  location token.
- `management_subnet_cidr`, `workload_subnet_cidr`: subnet ranges.
- `bastion_ssh_port`, `bastion_allowed_cidrs`: who may reach the bastion, and
  on which port.
- `enable_bastion_ssh_bootstrap`: temporarily allow port 22 while Ansible
  installs the final sshd policy. Disable immediately afterwards.
- `history_api_port`, `postgresql_port`, `ui_public_ports`: service ports.
- `tags`: applied to every resource in the module.

## Outputs

- `management_subnet_id`, `workload_subnet_id`
- `workload_groups`: security group IDs keyed by logical name.
