variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "network_cidr" {
  description = "CIDR range of the VPC. Must contain both subnets - AWS, unlike GCP, gives the network itself a range."
  type        = string

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid CIDR range."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR range of the public subnet. Holds the bastion and every other VM that is assigned a public IP."
  type        = string

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid CIDR range."
  }
}

variable "private_subnet_cidr" {
  description = "CIDR range of the private subnet. Reaches the internet through the NAT gateway only."
  type        = string

  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "private_subnet_cidr must be a valid CIDR range."
  }
}

variable "availability_zone" {
  description = "Availability zone both subnets are created in. An AWS subnet cannot span zones, so this is required where GCP needs nothing."
  type        = string
}

variable "enable_nat_gateway" {
  description = "Whether to create the NAT gateway. Only VMs without a public IP need it, and it bills by the hour whether or not anything uses it."
  type        = bool
  default     = true
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
  description = "Public TCP ports exposed on the UI VM"
  type        = list(string)
  default     = ["443"]

  validation {
    condition = (
      toset(var.ui_public_ports) == toset(["443"])
    )
    error_message = "ui_public_ports must contain exactly port 443"
  }
}

variable "tags" {
  description = "Tags applied to every network resource."
  type        = map(string)
}
