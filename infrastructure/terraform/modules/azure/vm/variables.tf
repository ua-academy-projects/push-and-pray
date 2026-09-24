variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "resource_group_names" {
  type = map(string)
}

variable "management_subnet_ids" {
  type = map(string)
}

variable "workload_subnet_ids" {
  type = map(string)
}

variable "network_security_group_ids" {
  description = "NSG IDs keyed by logical VM name."
  type        = map(string)
}
