variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "vms" {
  description = "Created Azure VMs from the Azure VM module, keyed by logical VM name."
  type        = any
}

variable "resource_group_names" {
  description = "Existing Azure resource group names keyed by logical location."
  type        = map(string)
}
