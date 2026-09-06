variable "config" {
  description = "The whole decoded project configuration."
  type        = any
  nullable    = false

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud && vm.role != "bastion"
      ]) == 0
      || can(var.config.clouds[var.cloud])
    )
    error_message = "Workloads are placed on a cloud that clouds declares no profile for."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for field in var.required_profile_fields :
        can(var.config.clouds[var.cloud][field])
      ])
    )
    error_message = "This cloud's profile must declare: ${join(", ", var.required_profile_fields)}."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud && vm.role != "bastion"
      ]) == 0
      || length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud && vm.role == "bastion"
      ]) == 1
    )
    error_message = "A cloud that hosts workloads needs exactly one bastion: there is no cross-cloud networking, so a bastion on another provider cannot reach them."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds[var.cloud].machine_sizes, {})), vm.size)
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ])
    )
    error_message = "Every VM on this cloud must use a size label declared in its machine_sizes."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds[var.cloud].images, {})), vm.image)
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ])
    )
    error_message = "Every VM on this cloud must use an image label declared in its images."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds[var.cloud].disk_types, {})), vm.boot_disk.type)
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ])
    )
    error_message = "Every VM on this cloud must use a boot disk label declared in its disk_types."
  }
}

variable "cloud" {
  description = "Which cloud is asking. The calling module's own name for itself."
  type        = string
  nullable    = false
}

variable "required_profile_fields" {
  description = "Profile fields this provider cannot work without, for example project_id on GCP or network_cidr on AWS. A list rather than a condition on the cloud name, so adding a provider adds an argument and not a branch."
  type        = list(string)
  default     = []
}
