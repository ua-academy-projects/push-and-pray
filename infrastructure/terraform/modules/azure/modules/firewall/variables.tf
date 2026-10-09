variable "resource_prefix" {
  description = "Prefix used for names of firewall resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "cluster" {
  description = "The cluster block of the configuration. Only the ports the nodes open to each other and the ports the ingress answers on are read."
  type = object({
    ports = list(object({
      name     = string
      protocol = string
      ports    = list(number)
      roles    = list(string)
    }))
    ingress = object({
      public_ports = list(number)
    })
  })

  validation {
    condition = alltrue(flatten([
      for entry in var.cluster.ports : [
        for role in entry.roles : contains(["k3s_server", "k3s_agent"], role)
      ]
    ]))
    error_message = "cluster.ports may only open ports on k3s_server and k3s_agent nodes."
  }

  validation {
    condition     = length(var.cluster.ports) <= 380
    error_message = "cluster.ports takes priorities 200 onwards, ten apart, and the deny rule sits at 4000: at most 380 entries fit."
  }
}

variable "tailscale" {
  description = "The tailscale block of the configuration: the port the bastion listens on for direct connections, and the range tailnet devices come from."
  type = object({
    port          = number
    address_range = string
  })
}

variable "network_cidr" {
  description = "This cloud's own range. Packets from it reach the bastion to be forwarded to the other clouds and to the tailnet."
  type        = string
}

variable "cluster_cidrs" {
  description = "Sources the cluster ports admit: every cloud that hosts a node, and the tailnet."
  type        = list(string)
}

variable "remote_cidrs" {
  description = "Ranges this cloud reaches through its bastion: the other clouds that host a node, and the tailnet. Packets for them are what the bastion forwards."
  type        = list(string)
}

variable "bastion" {
  description = "The bastion this cloud runs, from the configuration. Only its externally reachable SSH settings are read."
  type = object({
    ssh_port      = optional(number, 22)
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

variable "resource_group_name" {
  description = "Resource group the security groups are created in."
  type        = string
}

variable "location" {
  description = "Azure region of the security groups. An application security group only works inside the region of the network interfaces that join it."
  type        = string
}

variable "subnet_ids" {
  description = "Every subnet the security group is attached to, keyed by purpose. The only thing this module needs from the network."
  type        = map(string)
}

variable "tags" {
  description = "Tags applied to every security group."
  type        = map(string)
}
