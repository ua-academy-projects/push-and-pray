variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "profile" {
  description = "This cloud's profile. An AWS VPC carries its own range, and an AWS subnet cannot span availability zones, so both are read here."
  type = object({
    network_cidr = string
    zone         = string
    subnets = object({
      management = string
      workload   = string
      database   = optional(list(string), [])
    })
  })

  validation {
    condition = alltrue(concat(
      [can(cidrhost(var.profile.network_cidr, 0))],
      [
        for cidr in concat(
          [var.profile.subnets.management, var.profile.subnets.workload],
          var.profile.subnets.database,
        ) :
        can(cidrhost(cidr, 0))
      ],
    ))
    error_message = "network_cidr and every subnet range must be a valid CIDR."
  }
}

variable "enable_database_subnets" {
  description = "Whether to create the database subnets. Only a managed database lives there; a self-hosted one sits on a workload VM."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_database_subnets || length(var.profile.subnets.database) >= 2
    error_message = "RDS needs a DB subnet group spanning two availability zones, so subnets.database must hold at least two ranges."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to create the NAT gateway. Only VMs without a public IP need it, and it bills by the hour whether or not anything uses it."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every network resource."
  type        = map(string)
}
