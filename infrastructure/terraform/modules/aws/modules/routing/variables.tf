variable "route_table_ids" {
  description = "Route tables to add the routes to, keyed by purpose. A map so its keys are known before apply."
  type        = map(string)
}

variable "destinations" {
  description = "Ranges reached through the bastion: the other clouds that host a node, and the tailnet."
  type        = list(string)

  validation {
    condition     = alltrue([for cidr in var.destinations : can(cidrhost(cidr, 0))])
    error_message = "Every destination must be a valid CIDR."
  }
}

variable "bastion_network_interface_id" {
  description = "Primary network interface of the bastion, the next hop of every route. The instance must run with source_dest_check off."
  type        = string
}
