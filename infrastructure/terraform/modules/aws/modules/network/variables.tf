variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "config" {
  description = "The parts of the project configuration this module reads. A wider object converts down to this type, so the caller passes the whole configuration."
  type = object({
    network = object({
      ui_public_ports = list(number)
    })
    service_ports = object({
      history_api = number
      postgresql  = number
    })
  })

  validation {
    condition     = toset(var.config.network.ui_public_ports) == toset([443])
    error_message = "ui_public_ports must contain exactly port 443: Traefik terminates TLS there and solves the ACME challenge with TLS-ALPN-01, so nothing ever listens on 80."
  }

  validation {
    condition = alltrue([
      for port in values(var.config.service_ports) :
      port >= 1 && port <= 65535
    ])
    error_message = "Every service port must be between 1 and 65535."
  }
}

variable "bastion" {
  description = "The bastion this cloud runs, from the project configuration. Only its externally reachable SSH settings are read."
  type = object({
    ssh_port      = number
    allowed_cidrs = list(string)
  })

  validation {
    condition     = var.bastion.ssh_port >= 1 && var.bastion.ssh_port <= 65535
    error_message = "bastion.ssh_port must be between 1 and 65535."
  }

  validation {
    condition = (
      length(var.bastion.allowed_cidrs) > 0 &&
      alltrue([
        for cidr in var.bastion.allowed_cidrs :
        can(cidrhost(cidr, 0))
      ])
    )
    error_message = "bastion.allowed_cidrs must contain at least one valid CIDR range."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Whether to temporarily allow direct bastion SSH on port 22 when the final SSH port differs."
  type        = bool
  default     = false
}

variable "profile" {
  description = "This cloud's profile. An AWS VPC carries its own range, and an AWS subnet cannot span availability zones, so both are read here."
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
      [for cidr in values(var.profile.subnets) : can(cidrhost(cidr, 0))],
    ))
    error_message = "network_cidr and every subnet range must be a valid CIDR."
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
