# GCP VM module

Creates one Compute Engine instance together with the things that only exist
for it: its dedicated service account and, when it needs one, its reserved
external address.

The module is called once per VM. It takes that VM's entry from the project
configuration and the cloud profile, and resolves the abstract labels itself:

```hcl
machine_type   = var.profile.machine_sizes[var.vm.size]
image          = var.profile.images[var.vm.image]
boot_disk_type = var.profile.disk_types[var.vm.boot_disk.type]
```

## Resources

| Resource | Purpose |
| --- | --- |
| `google_service_account` | Runtime identity; secret bindings are attached to it by the caller |
| `google_compute_instance` | The VM, with Shielded VM settings and OS Login disabled |
| `google_compute_address` | Reserved external address, only when `vm.assign_public_ip` |

## Hardening

Secure Boot, vTPM and integrity monitoring are on. OS Login is off, and SSH
keys come from `ssh_users` through instance metadata. A `precondition` refuses
a public address for any role other than `ui` or `bastion`.

## Inputs

| Name | Description |
| --- | --- |
| `name` | Name for the instance and its service account |
| `vm` | This VM's configuration entry: `role`, `size`, `image`, `internal_ip`, `assign_public_ip`, `boot_disk` |
| `profile` | Cloud profile; only `machine_sizes`, `images` and `disk_types` are read |
| `subnetwork_id` | Subnet to place the instance in |
| `network_tags` | Prefixed tags the firewall rules match on |
| `labels` | Labels for every resource that supports them |
| `ssh_users` | Public SSH keys by Linux username |

`vm` and `profile` are narrow object types, so the caller passes the objects it
already has and the type documents what is read. Label validity is checked once
in `modules/shared/selection`, not here.

## Outputs

| Name | Description |
| --- | --- |
| `name`, `instance_id`, `self_link` | Identifiers of the instance |
| `zone` | Zone it runs in, inherited from the provider |
| `role` | Functional role, echoed back for callers indexing by role |
| `internal_ip`, `public_ip` | Addresses; `public_ip` is `null` when none is assigned |
| `public_address_name` | Name of the reserved address, or `null` |
| `machine_type`, `boot_disk` | What the size and disk labels resolved to |
| `network_tags` | Tags actually attached |
| `identity`, `service_account_email` | Service-account email |
| `identity_member` | The same, as an IAM member string ready for a binding |
| `service_account_id`, `service_account_unique_id` | Resource ID and rename-proof numeric ID |

`identity` and `identity_member` are named to match the AWS module, which
returns a role ARN in the same places.

## Usage

```hcl
module "vm" {
  source   = "./modules/vm"
  for_each = local.my_vms

  name    = "${local.resource_prefix}-${each.key}"
  vm      = each.value
  profile = local.profile

  subnetwork_id = module.network[0].workload_subnet_id
  network_tags  = [for tag in each.value.network_tags : "${local.resource_prefix}-${tag}"]
  ssh_users     = var.config.ssh_users
  labels        = local.common_labels
}
```

## License

GPL-2.0-or-later
