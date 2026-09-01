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
  description = "Provider-specific network group identifiers applied to the VM. Security group IDs here; Compute Engine network tags in the GCP module."
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
  description = "AMI name pattern, already resolved from the portable OS token. The exact AMI ID differs per region and per Canonical release, so it is looked up rather than pinned."
  type        = string
}

variable "image_owner" {
  description = "AWS account that publishes the AMI. Defaults to Canonical."
  type        = string
  default     = "099720109477"
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
  description = "Size of the boot volume in GiB."
  type        = number

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "boot_disk_size_gb must be at least 10 GiB."
  }
}

variable "boot_disk_type" {
  description = "EBS volume type, already resolved from the portable disk token."
  type        = string

  validation {
    condition = contains([
      "gp2",
      "gp3",
      "io2",
    ], var.boot_disk_type)

    error_message = "boot_disk_type must be gp2, gp3, or io2."
  }
}

variable "boot_disk_iops" {
  description = "Provisioned IOPS for boot volume types that require them. AWS refuses io1 and io2 volumes without it, and ignores it for gp2."
  type        = number
  default     = 100

  validation {
    condition     = var.boot_disk_iops >= 100
    error_message = "boot_disk_iops must be at least 100, the minimum AWS accepts."
  }
}

variable "assign_public_ip" {
  description = "Whether to create and assign a static public IP address."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Tags applied to resources that support them. Named labels to keep one interface across both cloud modules."
  type        = map(string)
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}
