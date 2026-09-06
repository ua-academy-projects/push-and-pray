variable "config" {
  description = "The whole decoded project configuration. This module selects the part that belongs to it."
  type        = any
  nullable    = false

  # Cross-references JSON Schema cannot express, because a label is only valid
  # against a sibling map in the same document. They repeat the literal
  # "aws" rather than local.this_cloud because variable validation runs
  # before locals exist.
  #
  # Every check is skipped when this cloud hosts no workload: the module then
  # builds nothing, so nothing about its profile has to hold.

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "aws" && vm.role != "bastion"
      ]) == 0
      || can(var.config.clouds.aws)
    )
    error_message = "Workloads are placed on aws but clouds.aws declares no profile for it."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "aws" && vm.role != "bastion"
      ]) == 0
      || can(var.config.clouds.aws.network_cidr)
    )
    error_message = "clouds.aws.network_cidr is required: an AWS VPC carries its own range, which GCP does not."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "aws" && vm.role != "bastion"
      ]) == 0
      || length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "aws" && vm.role == "bastion"
      ]) == 1
    )
    error_message = "A cloud that hosts workloads needs exactly one bastion: there is no cross-cloud networking, so a bastion on another provider cannot reach them."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "aws" && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds.aws.machine_sizes, {})), vm.size)
        if try(vm.cloud, var.config.default_cloud) == "aws"
      ])
    )
    error_message = "Every VM on aws must use a size label declared in clouds.aws.machine_sizes."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "aws" && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds.aws.images, {})), vm.image)
        if try(vm.cloud, var.config.default_cloud) == "aws"
      ])
    )
    error_message = "Every VM on aws must use an image label declared in clouds.aws.images."
  }

  validation {
    condition = (
      length([
        for name, vm in var.config.vms : name
        if try(vm.cloud, var.config.default_cloud) == "aws" && vm.role != "bastion"
      ]) == 0
      || alltrue([
        for name, vm in var.config.vms :
        contains(keys(try(var.config.clouds.aws.disk_types, {})), vm.boot_disk.type)
        if try(vm.cloud, var.config.default_cloud) == "aws"
      ])
    )
    error_message = "Every VM on aws must use a boot disk label declared in clouds.aws.disk_types."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 while Ansible configures the final SSH port. Disable after bootstrap."
  type        = bool
  default     = false
}

variable "secret_version_manager_arns" {
  description = "IAM principal ARNs allowed to add new versions to every secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for principal in var.secret_version_manager_arns :
      can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|user/.+|role/.+)$", principal))
    ])
    error_message = "Each entry must be an IAM principal ARN, for example arn:aws:iam::123456789012:user/name."
  }
}
