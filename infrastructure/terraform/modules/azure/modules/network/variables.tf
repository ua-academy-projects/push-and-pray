variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Resource group every network resource is created in."
  type        = string
}

variable "location" {
  description = "Azure region of the network."
  type        = string
}

variable "profile" {
  description = "This cloud's profile. A virtual network carries its own range, like an AWS VPC; the zone pins the NAT gateway and its address next to the VMs."
  type = object({
    network_cidr = string
    zone         = string
    subnets = object({
      management = string
      workload   = string
    })
  })

  validation {
    condition = alltrue(concat(
      [can(cidrhost(var.profile.network_cidr, 0))],
      [
        for cidr in [var.profile.subnets.management, var.profile.subnets.workload] :
        can(cidrhost(cidr, 0))
      ],
    ))
    error_message = "network_cidr and every subnet range must be a valid CIDR."
  }

  validation {
    condition     = can(regex("^[1-3]$", var.profile.zone))
    error_message = "An Azure zone is the number 1, 2 or 3 within the region."
  }

  validation {
    condition = alltrue([
      for cidr in [var.profile.subnets.management, var.profile.subnets.workload] :
      tonumber(split("/", cidr)[1]) <= 29
    ])
    error_message = "Azure refuses a subnet smaller than /29."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to create the NAT gateway. Only workloads without a public IP need it, and it bills by the hour whether or not anything uses it."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every network resource that takes them."
  type        = map(string)
}
