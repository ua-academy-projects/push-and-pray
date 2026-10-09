variable "resource_prefix" {
  description = "Prefix used for names of the routes."
  type        = string
}

variable "network_id" {
  description = "ID of the VPC the routes belong to."
  type        = string
}

variable "destinations" {
  description = "Ranges reached through the bastion: the other clouds that host a node, and the tailnet."
  type        = list(string)

  validation {
    condition     = alltrue([for cidr in var.destinations : can(cidrhost(cidr, 0))])
    error_message = "Every destination must be a valid CIDR."
  }
}

variable "bastion_self_link" {
  description = "Self link of the bastion instance, the next hop of every route. The instance must be created with can_ip_forward."
  type        = string
}

variable "node_tags" {
  description = "Network tags of the instances the routes apply to - the nodes, never the bastion."
  type        = list(string)
}
