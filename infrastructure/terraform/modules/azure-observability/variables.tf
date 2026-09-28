variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "instance_ids" {
  description = "Azure VM resource IDs keyed by logical VM name."
  type        = map(string)
}

variable "resource_group_name" {
  description = "Azure resource group name."
  type        = string
  nullable    = true
}

variable "location" {
  description = "Azure region for shared monitoring resources."
  type        = string
  nullable    = true
}
