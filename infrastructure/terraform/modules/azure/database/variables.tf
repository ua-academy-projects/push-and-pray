variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "resource_group_name" {
  type     = string
  nullable = true
}

variable "delegated_subnet_id" {
  type     = string
  nullable = true
}

variable "private_dns_zone_id" {
  description = "Private DNS zone, with its VNet link ready."
  type        = string
  nullable    = true
}

variable "administrator_password" {
  type      = string
  sensitive = true
  ephemeral = true
  default   = null

  validation {
    condition     = !local.enabled || try(length(var.administrator_password) >= 8, false)
    error_message = "Azure managed mode requires TF_VAR_azure_database_admin_password (at least eight characters, meeting Azure password complexity rules)."
  }
}

variable "administrator_password_version" {
  type    = number
  default = 1
}
