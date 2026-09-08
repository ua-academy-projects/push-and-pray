variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "GCP region used for subnets and Cloud Router."
  type        = string
}

variable "management_subnet_cidr" {
  description = "CIDR range of the management subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.management_subnet_cidr, 0))
    error_message = "management_subnet_cidr must be a valid CIDR range."
  }
}

variable "workload_subnet_cidr" {
  description = "CIDR range of the workload subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.workload_subnet_cidr, 0))
    error_message = "workload_subnet_cidr must be a valid CIDR range."
  }
}
