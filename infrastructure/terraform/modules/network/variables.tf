variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "GCP region used by both subnets and the Cloud Router."
  type        = string
}

variable "config" {
  description = "Network configuration decoded by root."
  type = object({
    management_subnet_cidr = string
    workload_subnet_cidr   = string
  })

  validation {
    condition     = can(cidrhost(var.config.management_subnet_cidr, 0))
    error_message = "management_subnet_cidr must be a valid CIDR range."
  }

  validation {
    condition     = can(cidrhost(var.config.workload_subnet_cidr, 0))
    error_message = "workload_subnet_cidr must be a valid CIDR range."
  }
  validation {
    condition = alltrue([
      for cidr in [var.config.management_subnet_cidr, var.config.workload_subnet_cidr] :
      try(tonumber(split("/", cidr)[1]), 0) >= 16 && try(tonumber(split("/", cidr)[1]), 99) <= 29
    ])
    error_message = "GCP subnet prefixes must be between /16 and /29."
  }
}
