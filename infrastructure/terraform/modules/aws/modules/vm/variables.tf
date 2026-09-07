variable "name" {
  description = "Name used for the instance and its IAM role."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "vm" {
  description = "This VM's entry from the project configuration. Sizes, images and disk types are abstract labels resolved through var.profile."
  type = object({
    role             = string
    size             = string
    image            = string
    internal_ip      = string
    assign_public_ip = bool
    boot_disk = object({
      size_gb = number
      type    = string
    })
  })

  validation {
    condition     = can(cidrhost("${var.vm.internal_ip}/32", 0))
    error_message = "internal_ip must be a valid IPv4 address."
  }

  validation {
    condition     = var.vm.boot_disk.size_gb >= 10
    error_message = "boot_disk.size_gb must be at least 10 GiB."
  }
}

variable "profile" {
  description = "This cloud's profile. Only the three lookup maps are read; modules/shared/selection has already checked that every label used here exists in them and that their values are ones AWS accepts."
  type = object({
    machine_sizes = map(string)
    disk_types    = map(string)
    images        = map(string)
  })
}

variable "instance_profile_name" {
  description = "Instance profile carrying the runtime identity. Created by the identity module, which outlives this instance."
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the instance is created."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups the instance belongs to. The AWS counterpart of the GCP network tags."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) > 0 && length(var.security_group_ids) == length(distinct(var.security_group_ids))
    error_message = "security_group_ids must contain at least one unique group."
  }
}

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}
