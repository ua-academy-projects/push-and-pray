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
