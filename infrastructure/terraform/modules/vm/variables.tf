variable "name" {
  description = "Name used for the VM and its service account."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "subnetwork_id" {
  description = "ID of the subnet where the VM is created."
  type        = string
}

variable "network_tag" {
  description = "Network tag used by firewall rules for this VM."
  type        = string
}

variable "machine_type" {
  description = "Compute Engine machine type for the workload VM."
  type        = string
}

variable "image" {
  description = "Boot image used by the VM."
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
  description = "Persistent Disk type used by the boot disk."
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
