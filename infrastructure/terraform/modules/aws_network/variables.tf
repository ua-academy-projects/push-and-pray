variable "resource_prefix" {
  description = "Prefix used for AWS network resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR range of the AWS VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR range."
  }
}

variable "management_subnet_cidr" {
  description = "CIDR range of the public management subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.management_subnet_cidr, 0))
    error_message = "management_subnet_cidr must be a valid CIDR range."
  }
}

variable "workload_subnet_cidr" {
  description = "CIDR range of the private workload subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.workload_subnet_cidr, 0))
    error_message = "workload_subnet_cidr must be a valid CIDR range."
  }
}

variable "availability_zone" {
  description = "AWS availability zone used for the subnets."
  type        = string
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
  description = "Whether to temporarily allow direct bastion SSH on port 22."
  type        = bool
  default     = false
}

variable "ui_public_ports" {
  description = "Public TCP ports exposed by the UI."
  type        = list(number)

  validation {
    condition     = toset(var.ui_public_ports) == toset([80, 443])
    error_message = "ui_public_ports must contain exactly ports 80 and 443."
  }
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
  description = "Port used by workloads to connect to PostgreSQL."
  type        = number

  validation {
    condition     = var.postgresql_port >= 1 && var.postgresql_port <= 65535
    error_message = "postgresql_port must be between 1 and 65535."
  }
}

variable "tags" {
  description = "Common tags applied to AWS resources."
  type        = map(string)
  default     = {}
}

variable "enable_ui_direct_ssh" {
  description = "Allow operator SSH directly to a public UI when its bastion is in another cloud."
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Whether to create the paid NAT Gateway used for private-subnet internet egress."
  type        = bool
  default     = false
}
