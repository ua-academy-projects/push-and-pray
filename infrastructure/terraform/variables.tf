variable "project_config_path" {
  description = "Path to the external JSON file containing project-specific configuration."
  type        = string
  nullable    = false
}

variable "database_password" {
  description = "Managed PostgreSQL application password; set with TF_VAR_database_password."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
  nullable    = true
}
