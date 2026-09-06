variable "name" {
  description = "Name used for the VM and its service account."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "management_subnet_id" {
  description = "ID of the subnet with Bastion and UI"
  type        = string
}

variable "workload_subnet_id" {
  description = "ID of the subnet with workload VMs"
  type        = string
}

variable "security_group_ids" {
  description = "list of security groups"
  type        = map(string)
}


variable "role" {
  description = "Functional role of the workload, independent from its resource name."
  type        = string
}

variable "instance_type" {
  description = "Compute Engine machine type for the workload VM."
  type        = string
}

variable "ami" {
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
}

variable "boot_disk_type" {
  description = "Persistent Disk type used by the boot disk."
  type        = string
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

variable "ssh_port" {
  description = "Initial SSH daemon port."
  type        = number
}
