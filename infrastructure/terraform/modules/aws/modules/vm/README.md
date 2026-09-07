# AWS VM module

Creates one EC2 instance and, when it needs one, its Elastic IP.

Its runtime identity is not created here. That lives in the sibling
[identity module](../identity/README.md), because an IAM role outlives the
instance and belongs to a different privilege boundary; this module simply
takes the instance profile to attach.

The module is called once per VM. It takes that VM's entry from the project
configuration and the cloud profile, and resolves the abstract labels itself:

```hcl
instance_type  = var.profile.machine_sizes[var.vm.size]
ami            = var.profile.images[var.vm.image]
boot_disk_type = var.profile.disk_types[var.vm.boot_disk.type]
```

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_instance` | The VM, with an encrypted root volume and IMDSv2 required |
| `aws_eip`, `aws_eip_association` | Static public address, only when `vm.assign_public_ip` |

## Differences from the GCP module

An EC2 instance accepts a single key pair, so the `ssh_users` map cannot be
expressed that way. The module renders cloud-init `user_data` instead, creating
one account per operator with their key.

There is no equivalent of Shielded VM. The closest hardening is `http_tokens =
"required"`, which refuses the token-less metadata requests that leak role
credentials, plus an encrypted root volume.

The instance takes its availability zone from its subnet, not from an input.

## Inputs

| Name | Description |
| --- | --- |
| `name` | Name for the instance |
| `vm` | This VM's configuration entry: `role`, `size`, `image`, `internal_ip`, `assign_public_ip`, `boot_disk` |
| `profile` | Cloud profile; only `machine_sizes`, `images` and `disk_types` are read |
| `instance_profile_name` | Identity to run as, from the identity module |
| `subnet_id` | Subnet to place the instance in |
| `security_group_ids` | Groups the instance belongs to - the AWS counterpart of GCP network tags |
| `tags` | Tags for every resource that supports them |
| `ssh_users` | Public SSH keys by Linux username |

## Outputs

| Name | Description |
| --- | --- |
| `name`, `instance_id`, `instance_arn` | Identifiers of the instance |
| `availability_zone` | Zone it runs in, inherited from its subnet |
| `role` | Functional role, echoed back for callers indexing by role |
| `internal_ip`, `public_ip`, `private_dns` | Addresses; `public_ip` is `null` when none is assigned |
| `public_address_allocation_id` | Allocation ID of the Elastic IP, or `null` |
| `instance_type`, `boot_disk` | What the size and disk labels resolved to |
| `root_volume_id` | The encrypted root volume |
| `security_group_ids` | Groups actually attached |

## Usage

```hcl
module "vm" {
  source   = "./modules/vm"
  for_each = local.my_vms

  name    = "${local.resource_prefix}-${each.key}"
  vm      = each.value
  profile = local.profile

  instance_profile_name = module.identity[each.key].instance_profile_name

  subnet_id          = module.network[0].private_subnet_id
  security_group_ids = [for scope in each.value.network_tags : module.network[0].security_group_ids[scope]]
  ssh_users          = var.config.ssh_users
  tags               = local.common_tags
}
```

## License

GPL-2.0-or-later
