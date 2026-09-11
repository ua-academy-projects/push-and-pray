variable "project_config_path" {
  description = "Path to the shared project configuration JSON."
  type        = string
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily expose port 22 on a GCP bastion."
  type        = bool
  default     = false
}

variable "secret_version_managers" {
  description = "GCP IAM members allowed to add secret versions."
  type        = list(string)
  default     = []
}

variable "database_password" {
  type      = string
  sensitive = true
  default   = null
  nullable  = true
}
