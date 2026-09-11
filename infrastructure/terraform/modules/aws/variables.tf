variable "project_config_path" {
  description = "Path to the shared project configuration JSON."
  type        = string
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily expose port 22 on an AWS bastion."
  type        = bool
  default     = false
}

variable "database_password" {
  type      = string
  sensitive = true
  default   = null
  nullable  = true
}
