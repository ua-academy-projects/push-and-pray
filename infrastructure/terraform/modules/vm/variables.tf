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

variable "network_tags" {
  description = "Effective network tags, including the mandatory role tag."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.network_tags) > 0 && alltrue([for tag in var.network_tags : can(regex("^[a-z][a-z0-9-]*$", tag))])
    error_message = "network_tags must contain at least one valid lowercase network tag."
  }
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

variable "automation_role" {
  description = "Role consumed by the VM deployment entry point."
  type        = string

  validation {
    condition     = contains(["none", "database", "fetcher", "history", "ui"], var.automation_role)
    error_message = "automation_role must be none, database, fetcher, history, or ui."
  }
}

variable "image_tag" {
  description = "Immutable application image tag selected by deployment configuration."
  type        = string
  default     = ""
}

variable "secret_bindings" {
  description = "Mapping of runtime environment variable names to Secret Manager IDs."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "image_repository" {
  description = "GHCR repository prefix containing published application images."
  type        = string
}

variable "compose_repository_url" {
  description = "Base URL from which supported role Compose files are retrieved."
  type        = string
}

variable "docker_engine_version" {
  description = "Pinned distribution Docker package version installed during bootstrap."
  type        = string
}

variable "service_ips" {
  description = "Internal service addresses keyed by application role."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
}
