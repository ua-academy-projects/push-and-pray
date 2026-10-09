variable "name" {
  description = "Name used for the VM, its network interface, disk and public address."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "vm" {
  description = "This VM's entry from the configuration - a node, or the bastion's derived specification. Sizes, images and disk types are abstract labels resolved through var.profile. Without internal_ip the cloud assigns an address from the subnet."
  type = object({
    role             = string
    size             = string
    image            = string
    internal_ip      = optional(string)
    assign_public_ip = bool
    ip_forwarding    = optional(bool, false)
    boot_disk = object({
      size_gb = number
      type    = string
    })
  })

  validation {
    condition     = var.vm.internal_ip == null || can(cidrhost("${var.vm.internal_ip}/32", 0))
    error_message = "internal_ip must be a valid IPv4 address."
  }

  validation {
    condition     = var.vm.boot_disk.size_gb >= 10
    error_message = "boot_disk.size_gb must be at least 10 GiB."
  }
}

variable "profile" {
  description = "This cloud's profile. The three lookup maps are read, and the zone every VM and public address is pinned to; modules/shared/selection has already checked that every label used here exists and that its value is one Azure accepts."
  type = object({
    zone          = string
    machine_sizes = map(string)
    disk_types    = map(string)
    images        = map(string)
  })
}

variable "resource_group_name" {
  description = "Resource group the VM and everything attached to it are created in."
  type        = string
}

variable "location" {
  description = "Azure region of the VM."
  type        = string
}

variable "identity_id" {
  description = "Resource ID of the user-assigned identity the VM runs as. Created by the identity module, which outlives this VM."
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet the network interface is created in."
  type        = string
}

variable "application_security_group_ids" {
  description = "Application security groups the network interface joins, keyed by scope. The Azure counterpart of the GCP network tags and the AWS security groups. A map so its keys are known before apply."
  type        = map(string)

  validation {
    condition     = length(var.application_security_group_ids) > 0
    error_message = "application_security_group_ids must contain at least one group."
  }
}

variable "minimum_boot_disk_size_gb" {
  description = "Smallest boot disk the images allow. A disk cannot be smaller than its image."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username. Azure accepts RSA and Ed25519 keys only."
  type        = map(string)

  validation {
    condition     = length(var.ssh_users) > 0
    error_message = "Azure needs at least one user to provision the VM with."
  }
}
