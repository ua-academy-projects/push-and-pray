variable "config" {
  description = "The whole decoded project configuration. This module selects the part that belongs to it."
  type        = any
  nullable    = false

  # Cross-references JSON Schema cannot express, because a label is only valid
  # against a sibling map in the same document. They repeat the literal
  # "gcp" rather than local.this_cloud because variable validation runs
  # before locals exist.
  #
  # Every check is skipped when this cloud hosts no workload: the module then
  # builds nothing, so nothing about its profile has to hold.

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role != "bastion"
      ]) == 0
      || can(var.config.clouds.gcp)
    )
    error_message = "Workloads are placed on gcp but clouds.gcp declares no profile for it."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role != "bastion"
      ]) == 0
      || length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role == "bastion"
      ]) == 1
    )
    error_message = "A cloud that hosts workloads needs exactly one bastion: there is no cross-cloud networking, so a bastion on another provider cannot reach them."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds.gcp.machine_sizes, {})), vm.size)
        if try(vm.cloud, var.config.default_cloud) == "gcp"
      ])
    )
    error_message = "Every VM on gcp must use a size label declared in clouds.gcp.machine_sizes."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds.gcp.images, {})), vm.image)
        if try(vm.cloud, var.config.default_cloud) == "gcp"
      ])
    )
    error_message = "Every VM on gcp must use an image label declared in clouds.gcp.images."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds.gcp.disk_types, {})), vm.boot_disk.type)
        if try(vm.cloud, var.config.default_cloud) == "gcp"
      ])
    )
    error_message = "Every VM on gcp must use a boot disk label declared in clouds.gcp.disk_types."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 while Ansible configures the final SSH port. Disable after bootstrap."
  type        = bool
  default     = false
}

variable "secret_version_managers" {
  description = "IAM members allowed to add new versions to every secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []
}
