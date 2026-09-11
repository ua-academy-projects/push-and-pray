variable "project_config_path" {
  type = string
  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  type    = bool
  default = false
}

variable "database_password" {
  type      = string
  sensitive = true
  default   = null
  nullable  = true
}
