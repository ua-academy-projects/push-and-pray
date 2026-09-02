variable "resource_prefix" {
  description = "Prefix used for AWS network resource names."
  type        = string
}

variable "network_config" {
  description = "Provider-independent network configuration."
  type        = any
}

variable "location_config" {
  description = "Provider mappings for the selected logical location."
  type        = any
}

variable "vms" {
  description = "VM configuration keyed by logical VM name."
  type        = any
}

variable "tags" {
  description = "Common tags applied to AWS network resources."
  type        = map(string)
}
