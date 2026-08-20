variable "resource_prefix" {
  description = "Prefix used for bastion resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "subnetwork_id" {
  description = "ID of the management subnet where the bastion is created."
  type        = string
}

variable "network_tag" {
  description = "Network tag used by bastion firewall rules."
  type        = string
}

variable "machine_type" {
  description = "Compute Engine machine type for the bastion."
  type        = string
}

variable "image" {
  description = "Boot image used by the bastion VM."
  type        = string
}

variable "boot_disk_size_gb" {
  description = "Size of the bastion boot disk in GiB."
  type        = number

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10 GiB."
  }
}

variable "boot_disk_type" {
  description = "Persistent Disk type used by the bastion boot disk."
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

variable "labels" {
  description = "Labels applied to bastion resources that support them."
  type        = map(string)
}
