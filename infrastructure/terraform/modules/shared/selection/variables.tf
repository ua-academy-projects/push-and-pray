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

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud && vm.role != "bastion"
      ]) == 0
      || alltrue(flatten([
        for dictionary, pattern in var.profile_value_patterns : [
          for label, value in try(var.config.clouds[var.cloud][dictionary], {}) :
          can(regex(pattern, value))
        ]
      ]))
    )
    error_message = "This cloud's lookup maps hold values its provider does not accept: ${join(", ", flatten([
      for dictionary, pattern in var.profile_value_patterns : [
        for label, value in try(var.config.clouds[var.cloud][dictionary], {}) :
        "${dictionary}.${label}=${value}" if !can(regex(pattern, value))
      ]
    ]))}."
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

variable "profile_value_patterns" {
  description = "Per lookup map, a regular expression every value in it must match on this provider - for example gp3 is a valid disk type on AWS and nowhere else. A map rather than a condition on the cloud name, so adding a provider adds an argument and not a branch. Checks the whole dictionary, including labels no VM uses yet."
  type        = map(string)
  default     = {}
}
