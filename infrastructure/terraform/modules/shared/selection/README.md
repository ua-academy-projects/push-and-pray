# Selection module

Answers the questions every cloud module asks of the project configuration, so
that both providers get the same answer from the same code. It creates no
resources.

Given the whole configuration and the name of the asking cloud, it decides
which VMs that cloud manages, whether it should build anything at all, and what
labels go on everything.

## The active check

A bastion exists only to reach workloads. A cloud that hosts none has nothing
to reach, so `is_active` is false and `my_vms` comes back empty - the caller
then builds nothing, the lone bastion included. `skipped_vms` reports what was
dropped, since the skip is otherwise silent.

## Validation

Five cross-references live here because JSON Schema cannot express them: a
label is only valid against a sibling map in the same document.

| Check | Message names |
| --- | --- |
| the cloud declares a profile | `clouds.<cloud>` |
| the profile carries what the provider needs | `required_profile_fields` |
| exactly one bastion where there are workloads | the bastion count |
| every `size`, `image` and `boot_disk.type` label exists | the missing label |
| every value in every lookup map is one the provider accepts | each offending entry |

All of them are skipped when the cloud is inactive: nothing is built, so
nothing has to hold.

Both provider-specific arguments are data rather than a condition on the cloud
name, so adding a provider adds an argument and not a branch.

## Inputs

| Name | Description |
| --- | --- |
| `config` | The whole decoded project configuration |
| `cloud` | Which cloud is asking - the caller's own name for itself |
| `required_profile_fields` | Profile fields this provider cannot work without, e.g. `["project_id"]` |
| `profile_value_patterns` | Per lookup map, a regex every value must match on this provider |

## Outputs

| Name | Description |
| --- | --- |
| `profile` | This cloud's profile, or `null` when it declares none |
| `is_active` | Whether this cloud hosts any workload |
| `my_vms` | VMs the caller manages; empty unless active |
| `workload_vms` | Managed VMs that are not bastions |
| `bastion_vms` | Managed VMs that are bastions |
| `bastion_vm` | The single bastion, or `null` when inactive |
| `cloud_vms` | Every VM assigned to this cloud, built or not |
| `skipped_vms` | VMs dropped by the active check |
| `resource_prefix` | Prefix shared by every resource name |
| `common_labels` | Labels applied to every resource, including the `cloud` key |
| `cloud` | The cloud this instance answered for |

## Usage

```hcl
module "selection" {
  source = "../shared/selection"

  config                  = var.config
  cloud                   = local.this_cloud
  required_profile_fields = ["project_id"]

  profile_value_patterns = {
    machine_sizes = "^[a-z][0-9]?[a-z0-9]*-[a-z0-9-]+$"
    disk_types    = "^pd-(standard|balanced|ssd)$"
    images        = "^projects/[^/]+/global/images/"
  }
}
```

## License

GPL-2.0-or-later
