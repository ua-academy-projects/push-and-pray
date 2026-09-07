variable "resource_prefix" {
  description = "Prefix used for AWS network resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "tags" {
  description = "Common tags applied to AWS resources."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC ID."
}

variable "policy" {
  description = "Application ingress policy shared by the provider firewall resources."
  type = object({
    bastion_ssh_port      = number
    bastion_allowed_cidrs = list(string)
    history_api_port      = number
    postgresql_port       = number
    ui_public_ports       = list(string)
  })

  validation {
    condition     = var.policy.bastion_ssh_port >= 1 && var.policy.bastion_ssh_port <= 65535
    error_message = "bastion_ssh_port must be between 1 and 65535."
  }

  validation {
    condition = (
      length(var.policy.bastion_allowed_cidrs) > 0 &&
      alltrue([
        for cidr in var.policy.bastion_allowed_cidrs :
        can(cidrhost(cidr, 0))
      ])
    )

    error_message = "bastion_allowed_cidrs must contain at least one valid CIDR range."
  }

  validation {
    condition     = var.policy.history_api_port >= 1 && var.policy.history_api_port <= 65535
    error_message = "history_api_port must be between 1 and 65535."
  }

  validation {
    condition     = var.policy.postgresql_port >= 1 && var.policy.postgresql_port <= 65535
    error_message = "postgresql_port must be between 1 and 65535."
  }

  validation {
    condition     = toset(var.policy.ui_public_ports) == toset(["80", "443"])
    error_message = "ui_public_ports must contain exactly ports 80 and 443."
  }
}
