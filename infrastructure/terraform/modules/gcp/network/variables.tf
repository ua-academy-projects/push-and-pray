variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "network_config" {
  description = "Provider-independent network configuration."
  type        = any
}

variable "vms" {
  description = "VM configuration keyed by logical VM name."
  type        = any
}
