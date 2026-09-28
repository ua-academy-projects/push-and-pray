variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "location" {
  description = "Azure region for shared identity and Key Vault resources."
  type        = string
}

variable "resource_group_name" {
  description = "Azure resource group name."
  type        = string
}
