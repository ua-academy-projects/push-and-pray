variable "resource_prefix" {
  description = "Prefix used for AWS network resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "availability_zone" {
  description = "AWS availability zone used for the subnets."
  type        = string
}

variable "tags" {
  description = "Common tags applied to AWS resources."
  type        = map(string)
  default     = {}
}

variable "config" {
  description = "Network configuration decoded by root."
  type = object({
    vpc_cidr               = string
    management_subnet_cidr = string
    workload_subnet_cidr   = string
    aws_enable_nat_gateway = bool
  })

  validation {
    condition     = can(cidrhost(var.config.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR range."
  }

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
      for cidr in [var.config.vpc_cidr, var.config.management_subnet_cidr, var.config.workload_subnet_cidr] :
      try(tonumber(split("/", cidr)[1]), 0) >= 16 && try(tonumber(split("/", cidr)[1]), 99) <= 28
    ])
    error_message = "AWS subnet prefixes must be between /16 and /28."
  }
}
