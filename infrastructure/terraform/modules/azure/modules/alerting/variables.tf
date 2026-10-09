variable "resource_prefix" {
  description = "Prefix shared by every resource name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the alert rules are created in."
  type        = string
}

variable "resource_group_id" {
  description = "ID of that resource group, which the health alert and the budget are scoped to."
  type        = string
}

variable "location" {
  description = "Azure region of the VMs and the workspace."
  type        = string
}

variable "email" {
  description = "Address every alert and budget notification goes to."
  type        = string
}

variable "metrics" {
  description = "The monitoring module's metric table: one rule per VM and entry."
  type = map(object({
    title       = string
    name        = string
    aggregation = string
    operator    = string
    threshold   = number
  }))
}

variable "window_minutes" {
  description = "Length of the window every metric rule evaluates. Must match the one the monitoring module scaled its totals to."
  type        = number
  default     = 5
}

variable "memory_threshold_mb" {
  description = "Memory in use above which the memory alert fires, in MB."
  type        = number
}

variable "instances" {
  description = "Every VM to watch, keyed by name."
  type = map(object({
    id   = string
    name = string
    role = string
  }))
}

variable "workspace_id" {
  description = "Log Analytics workspace the log-based alerts query."
  type        = string
}

variable "budget_usd" {
  description = "Monthly spend above which the billing alert fires. Null creates no budget."
  type        = number
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
