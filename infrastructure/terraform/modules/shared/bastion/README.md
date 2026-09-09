# Bastion specification module

Derives the bastion's specification for one cloud. It creates no resources: it
turns the project-wide `bastion` block plus that cloud's profile into an object
shaped exactly like an entry of `vms`, which the cloud's VM module accepts
unchanged.

The point is that a bastion never varies. It is always the smallest machine the
profile offers, always holds a public address, always sits in the management
subnet, and never reads a secret. Writing that out once per cloud is
duplication that grows with every provider added; deriving it costs one module
call.

## What is derived

| Field | Where it comes from |
| --- | --- |
| `role` | constant `bastion` |
| `size` | `config.bastion.size`, default `tiny` |
| `image` | `config.bastion.image`, default `ubuntu-lts` |
| `boot_disk` | `config.bastion.boot_disk`, defaults `10` GiB and `balanced` |
| `internal_ip` | `cidrhost(profile.subnets.management, host_index)` |
| `assign_public_ip` | constant `true` |

Every label stays abstract here. The cloud's VM module resolves them through
the same `machine_sizes`, `images` and `disk_types` maps it uses for workloads.

## `host_index`

Providers reserve a different number of leading addresses in a subnet, so the
caller supplies the first index its own provider leaves free:

| Cloud | Reserved | `host_index` | Result on the current profiles |
| --- | --- | --- | --- |
| GCP | network address and gateway | `2` | `10.0.0.0/29` → `10.0.0.2` |
| AWS | the first four addresses | `4` | `10.1.0.0/28` → `10.1.0.4` |

A number rather than a condition on the cloud name, so adding a provider adds
an argument and not a branch - the same shape as `required_profile_fields` and
`profile_value_patterns` in [selection](../selection/README.md).

## Validation

The three abstract labels are checked against the profile's maps here, because
`modules/shared/selection` only sees `vms` and the bastion is no longer in it.

## Inputs

| Name | Description |
| --- | --- |
| `config` | Project configuration; only the `bastion` block is read |
| `cloud` | Which cloud this bastion is built on |
| `profile` | That cloud's profile: the three lookup maps and `subnets.management` |
| `host_index` | First address the provider leaves free in a subnet |

## Outputs

| Name | Description |
| --- | --- |
| `vm` | The specification, ready to pass as the VM module's `vm` argument |
| `internal_ip` | The derived address, for callers that need it before the VM exists |
| `ssh_port`, `allowed_cidrs` | Passed through for the firewall module |

## Usage

```hcl
module "bastion_spec" {
  source = "../shared/bastion"
  count  = local.is_active ? 1 : 0

  config     = var.config
  cloud      = local.this_cloud
  profile    = local.profile
  host_index = 2
}

module "bastion" {
  source = "./modules/vm"
  count  = local.is_active ? 1 : 0

  name          = "${local.resource_prefix}-bastion"
  vm            = module.bastion_spec[0].vm
  profile       = local.profile
  subnetwork_id = module.network[0].management_subnet_id
  network_tags  = [module.firewall[0].network_tags["bastion"]]
  ssh_users     = var.config.ssh_users
  labels        = merge(local.common_labels, { role = "bastion" })
}
```

The `role = "bastion"` label is load-bearing: the Ansible inventory selects the
bastion by it, puts it in the `bastion` group rather than `workloads`, and uses
its public address for `ansible_host`.

## License

GPL-2.0-or-later
