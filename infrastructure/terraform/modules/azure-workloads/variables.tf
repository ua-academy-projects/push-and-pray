variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "resource_group_name" {
  description = "Azure resource group name."
  type        = string
}

variable "networks" {
  description = "Azure network identifiers keyed by logical location."
  type        = any
}

variable "network_security_group_ids" {
  description = "Azure NSG IDs keyed by logical location and functional tag."
  type        = map(map(string))
}

variable "identity_ids" {
  description = "User-assigned managed identity IDs keyed by logical workload VM name."
  type        = map(string)
}
