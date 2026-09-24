variable "project_config_path" {
  description = "Path to the external JSON file containing project-specific configuration."
  type        = string
  nullable    = false

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }
}

variable "azure_database_admin_password" {
  description = "Azure managed PostgreSQL administrator password, supplied via TF_VAR_azure_database_admin_password; use the same DB_PASSWORD_ADMIN in the Ansible secret workflow."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}

variable "azure_database_admin_password_version" {
  description = "Increment when rotating the write-only Azure managed PostgreSQL administrator password."
  type        = number
  default     = 1
}
