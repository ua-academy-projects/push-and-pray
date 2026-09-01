variable "name" {
  description = "Name used for the VM and its runtime identity."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "role" {
  description = "Functional role of the workload, independent from its resource name."
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the VM is created."
  type        = string
}

variable "network_groups" {
  description = "Provider-specific network group identifiers applied to the VM. Compute Engine network tags here; security group IDs in the AWS module."
  type        = list(string)

  validation {
    condition     = length(var.network_groups) > 0 && length(var.network_groups) == length(distinct(var.network_groups))
    error_message = "network_groups must contain at least one unique entry."
  }
}

variable "machine_type" {
  description = "Provider machine type, already resolved from the portable size token."
  type        = string
}

variable "image" {
  description = "Provider boot image reference, already resolved from the portable OS token."
  type        = string
}

variable "internal_ip" {
  description = "Static internal IPv4 address assigned to the VM."
  type        = string

  validation {
    condition     = can(cidrhost("${var.internal_ip}/32", 0))
    error_message = "internal_ip must be a valid IPv4 address."
  }
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GiB."
  type        = number

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10 GiB."
  }
}

variable "boot_disk_type" {
  description = "Persistent Disk type, already resolved from the portable disk token."
  type        = string

  validation {
    condition = contains([
      "pd-standard",
      "pd-balanced",
      "pd-ssd",
    ], var.boot_disk_type)

    error_message = "boot_disk_type must be pd-standard, pd-balanced, or pd-ssd."
  }
}

variable "assign_public_ip" {
  description = "Whether to create and assign a static external IP address."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}
