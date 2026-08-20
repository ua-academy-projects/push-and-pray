variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region used by static addresses."
  type        = string
}

variable "zone" {
  description = "Zone used by the instance and disks."
  type        = string
}

variable "name" {
  description = "Instance name and resource-name prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "name must be a valid GCP resource name between 2 and 63 characters."
  }
}

variable "machine_type" {
  description = "Compute Engine machine type."
  type        = string
}

variable "subnetwork_id" {
  description = "Subnetwork where the instance and its static internal address are created."
  type        = string
}

variable "internal_ip" {
  description = "Static internal IPv4 address."
  type        = string

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.internal_ip))
    error_message = "internal_ip must be an IPv4 address."
  }
}

variable "assign_external_ip" {
  description = "Reserve and attach a static external IPv4 address."
  type        = bool
  default     = false
}

variable "network_tags" {
  description = "Network tags consumed by firewall rules."
  type        = list(string)
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
  default     = {}
}

variable "metadata" {
  description = "Non-sensitive instance metadata. Application deployment is intentionally not embedded here."
  type        = map(string)
  default     = {}
}

variable "boot_image" {
  description = "Boot image URI or family path."
  type        = string
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GiB."
  type        = number

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10 GiB."
  }
}

variable "boot_disk_type" {
  description = "Boot persistent-disk type."
  type        = string

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.boot_disk_type)
    error_message = "boot_disk_type must be pd-standard, pd-balanced or pd-ssd."
  }
}

variable "service_account_email" {
  description = "Dedicated service account attached to the instance."
  type        = string
}
