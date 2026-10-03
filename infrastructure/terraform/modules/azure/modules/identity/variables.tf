variable "name" {
  description = "Name of the identity. Matches the VM it belongs to: the metadata service is asked for a token of the identity by this name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Resource group the identity is created in."
  type        = string
}

variable "location" {
  description = "Azure region of the identity."
  type        = string
}

variable "tags" {
  description = "Tags applied to the identity."
  type        = map(string)
}
