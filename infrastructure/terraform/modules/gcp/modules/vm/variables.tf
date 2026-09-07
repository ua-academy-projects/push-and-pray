variable "name" {
  description = "Name used for the VM and its service account."
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
  description = "This cloud's profile. Only the three lookup maps are read; modules/shared/selection has already checked that every label used here exists in them and that their values are ones GCP accepts."
  type = object({
    machine_sizes = map(string)
    disk_types    = map(string)
    images        = map(string)
  })
}

variable "service_account_email" {
  description = "Email of the runtime identity to attach. Created by the identity module, which outlives this instance."
  type        = string
}

variable "subnetwork_id" {
  description = "ID of the subnet where the VM is created."
  type        = string
}

variable "network_tags" {
  description = "Effective network tags attached to the workload VM."
  type        = list(string)

  validation {
    condition     = length(var.network_tags) > 0 && length(var.network_tags) == length(distinct(var.network_tags))
    error_message = "network_tags must contain at least one unique tag."
  }
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}
