variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}

variable "vms" {
  description = "Azure VMs keyed by logical workload name."
  type        = any
}

variable "region_key" {
  description = "Logical Azure region key used by this module instance."
  type        = string
}

variable "name_suffix" {
  description = "Optional suffix that keeps regional resource names unique."
  type        = string
  default     = ""
}

variable "network" {
  description = "Regional Azure network configuration."
  type        = any
}

variable "management_source_cidrs" {
  description = "CIDRs allowed to SSH to workload VMs, normally the primary management subnet."
  type        = list(string)
}

variable "trusted_vnet_cidrs" {
  description = "Regional VNet CIDRs allowed to reach internal application ports."
  type        = list(string)
}

variable "resource_group_name" {
  type     = string
  nullable = true
}

variable "location" {
  type     = string
  nullable = true
}

variable "database_mode" {
  type = string
}

variable "enable_bastion_ssh_bootstrap" {
  type    = bool
  default = false
}
