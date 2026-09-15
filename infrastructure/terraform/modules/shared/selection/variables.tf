variable "config" {
  description = "The whole decoded project configuration."
  type        = any
  nullable    = false

  # Cross-references JSON Schema cannot express, because a label is only valid
  # against a sibling map in the same document.
  #
  # Every check is skipped when this cloud hosts no workload: the calling module
  # then builds nothing, so nothing about its profile has to hold.

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ]) == 0
      || can(var.config.clouds[var.cloud])
    )
    error_message = "Workloads are placed on a cloud that clouds declares no profile for."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud
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
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds[var.cloud].machine_sizes, {})), vm.size)
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ])
    )
    error_message = "Every workload on this cloud must use a size label declared in its machine_sizes."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds[var.cloud].images, {})), vm.image)
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ])
    )
    error_message = "Every workload on this cloud must use an image label declared in its images."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds[var.cloud].disk_types, {})), vm.boot_disk.type)
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ])
    )
    error_message = "Every workload on this cloud must use a boot disk label declared in its disk_types."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud
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

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ]) == 0
      || try(var.config.database.mode, "self-hosted") != "managed"
      || (
        anytrue([
          for name, vm in var.config.vms :
          vm.role == "infra"
          if try(vm.cloud, var.config.default_cloud) == var.cloud
        ])
        && length([
          for name, vm in var.config.vms : name
          if try(vm.cloud, var.config.default_cloud) == var.cloud
        ]) == length(var.config.vms)
      )
    )
    error_message = "A managed database is reachable only inside one VPC, so in managed mode every workload must sit on the cloud that hosts the infra VM."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ]) == 0
      || try(var.config.database.mode, "self-hosted") != "managed"
      || contains(keys(try(var.config.clouds[var.cloud].database_sizes, {})), try(var.config.database.size, ""))
    )
    error_message = "database.size must be a label declared in this cloud's database_sizes."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == var.cloud
      ]) == 0
      || try(var.config.database.mode, "self-hosted") != "managed"
      || length(try(var.config.clouds[var.cloud].subnets.database, [])) > 0
    )
    error_message = "A managed database needs at least one range in this cloud's subnets.database."
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
