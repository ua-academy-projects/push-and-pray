variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}

variable "vms" {
  description = "Azure VMs keyed by logical workload name."
  type        = any
}

variable "resource_group_name" {
  type     = string
  nullable = true
}

variable "location" {
  type     = string
  nullable = true
}

variable "generated_secret_ids" {
  description = "Application secret IDs whose first value Terraform generates."
  type        = set(string)
  default     = []
}
