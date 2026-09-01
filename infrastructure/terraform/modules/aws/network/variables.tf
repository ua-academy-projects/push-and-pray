variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "availability_zone" {
  description = "Availability zone hosting both subnets, resolved from the portable location token."
  type        = string
}

variable "management_subnet_cidr" {
  description = "CIDR range of the management subnet. Public: it holds the bastion and the NAT gateway."
  type        = string

  validation {
    condition     = can(cidrhost(var.management_subnet_cidr, 0))
    error_message = "management_subnet_cidr must be a valid CIDR range."
  }
}

variable "workload_subnet_cidr" {
  description = "CIDR range of the workload subnet. Private: egress goes through the NAT gateway."
  type        = string

  validation {
    condition     = can(cidrhost(var.workload_subnet_cidr, 0))
    error_message = "workload_subnet_cidr must be a valid CIDR range."
  }
}

variable "bastion_ssh_port" {
  description = "External SSH port opened for the bastion."
  type        = number

  validation {
    condition     = var.bastion_ssh_port >= 1 && var.bastion_ssh_port <= 65535
    error_message = "bastion_ssh_port must be between 1 and 65535."
  }
}

variable "bastion_allowed_cidrs" {
  description = "Source CIDRs allowed to connect to the bastion."
  type        = list(string)

  validation {
    condition = (
      length(var.bastion_allowed_cidrs) > 0 &&
      alltrue([
        for cidr in var.bastion_allowed_cidrs :
        can(cidrhost(cidr, 0))
      ])
    )

    error_message = "bastion_allowed_cidrs must contain at least one valid CIDR range."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Whether to temporarily allow direct bastion SSH on port 22 when the final SSH port differs."
  type        = bool
  default     = false
}

variable "history_api_port" {
  description = "Port used by UI to connect to the History API."
  type        = number

  validation {
    condition     = var.history_api_port >= 1 && var.history_api_port <= 65535
    error_message = "history_api_port must be between 1 and 65535."
  }
}

variable "postgresql_port" {
  description = "Port used by workloads to connect to PostgreSQL on the infra VM."
  type        = number

  validation {
    condition     = var.postgresql_port >= 1 && var.postgresql_port <= 65535
    error_message = "postgresql_port must be between 1 and 65535."
  }
}

variable "ui_public_ports" {
  description = "Public TCP ports exposed on the UI VM."
  type        = list(string)
  default     = ["443"]

  validation {
    condition     = toset(var.ui_public_ports) == toset(["443"])
    error_message = "ui_public_ports must contain exactly port 443"
  }
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR range of the VPC. AWS requires one; GCP derives the network from its subnets and ignores this value."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR range."
  }

  validation {
    condition = alltrue([
      for subnet in [var.management_subnet_cidr, var.workload_subnet_cidr] :
      cidrhost(var.vpc_cidr, 0) == cidrhost("${cidrhost(subnet, 0)}/${split("/", var.vpc_cidr)[1]}", 0)
    ])
    error_message = "management_subnet_cidr and workload_subnet_cidr must both fall inside vpc_cidr."
  }
}
