# Azure VM module

Creates one Linux VM from an entry shaped like the project configuration's
`vms`, with its network interface, its membership in the firewall scopes and,
for the UI and the bastion, a static public address.

## Resources

| Resource | Purpose |
| --- | --- |
| `<name>-ip` | Static Standard public address, only when `assign_public_ip` |
| `<name>-nic` | Network interface with the configured static private address |
| NIC ↔ application security group | One association per scope in `network_tags` |
| `<name>` | The VM, running as its user-assigned identity |

## How it differs from the other clouds

- **The network interface is a resource of its own**, created before the VM;
  GCP and AWS build it as part of the instance. Scope membership belongs to the
  interface too.
- **An administrator is mandatory.** Azure provisions one user by itself and
  refuses a VM without one. The alphabetically first entry of `ssh_users` takes
  that place, and cloud-init creates every user from `custom_data`, that one
  included, exactly as `user_data` does on AWS. Azure accepts RSA and Ed25519
  keys only.
- **The boot disk cannot be smaller than the image.** The Ubuntu images are
  30 GiB, so `boot_disk.size_gb` is raised to `minimum_boot_disk_size_gb` where
  it is smaller.
- **Images are Marketplace URNs**, `publisher:offer:sku:version`.
- **Trusted launch** - secure boot and vTPM - is the counterpart of GCP's
  shielded VM.

## Replacement

`custom_data` and `admin_ssh_key` both force a new VM on Azure. cloud-init
applies the users once, at first boot - on AWS a changed `user_data` never
re-runs it either - so both are ignored after creation rather than replacing
the VM over a key. Taint the VM to rebuild it with a changed user list.

## Inputs

| Name | Description |
| --- | --- |
| `name` | Name of the VM, prefix of its interface, disk and address |
| `vm` | The `vms` entry; labels are resolved through `profile` |
| `profile` | `zone` and the three lookup maps |
| `resource_group_name`, `location` | Where the VM is created |
| `identity_id` | The user-assigned identity from the identity module |
| `subnet_id` | Subnet of the network interface |
| `application_security_group_ids` | Scopes to join, keyed by scope |
| `minimum_boot_disk_size_gb` | Smallest disk the images allow, 30 |
| `ssh_users`, `tags` | Users and tags |

## Outputs

`name`, `vm_id`, `internal_ip`, `public_ip`, `application_security_group_ids`,
`network_interface_id`, `zone`, `vm_size`, `boot_disk`, `role`.

## License

GPL-2.0-or-later
