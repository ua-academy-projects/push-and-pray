variable "resource_group_name" {
  description = "Azure resource group name."
  type        = string
}

variable "vms" {
  description = "Normalized Azure virtual machine specifications keyed by logical name."
  type        = any
}
