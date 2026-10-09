variable "resource_prefix" {
  description = "Prefix used for the name of the route table."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the route table is created in."
  type        = string
}

variable "location" {
  description = "Azure region of the route table."
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

variable "bastion_internal_ip" {
  description = "Address of the bastion, the next hop of every route. Its network interface must have IP forwarding enabled."
  type        = string
}

variable "subnet_ids" {
  description = "Every subnet the route table is attached to, keyed by purpose. A map so its keys are known before apply."
  type        = map(string)
}

variable "tags" {
  description = "Tags applied to the route table."
  type        = map(string)
}
