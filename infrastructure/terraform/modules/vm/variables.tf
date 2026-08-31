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

variable "network_tags" {
  description = "Effective network tags attached to the workload VM."
  type        = list(string)

  validation {
    condition     = length(var.network_tags) > 0 && length(var.network_tags) == length(distinct(var.network_tags))
    error_message = "network_tags must contain at least one unique tag."
  }
}

variable "role" {
  description = "Functional role of the workload, independent from its resource name."
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


variable "registry_repository" {
  description = "Non-secret container registry repository used by deployment automation."
  type        = string

  validation {
    condition = (
      length(trimspace(var.registry_repository)) > 0 &&
      !can(regex("\\s", var.registry_repository))
    )
    error_message = "registry_repository must be non-empty and contain no whitespace."
  }
}

variable "image_sha" {
  description = "Immutable 40-character Git commit SHA used as the application image tag."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_sha))
    error_message = "image_sha must be a 40-character lowercase hexadecimal Git commit SHA."
  }
}

variable "docker_version" {
  description = "Exact Docker Engine apt version pinned by the cloud-init bootstrap. Verify with `apt-cache madison docker-ce` before bumping."
  type        = string
  default     = "5:29.7.2-1~ubuntu.26.04~resolute"
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}

variable "ssh_port" {
  description = "Initial SSH daemon port."
  type        = number
}
