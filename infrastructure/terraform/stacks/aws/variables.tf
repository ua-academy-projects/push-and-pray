variable "project_config_path" {
  type = string
  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }

  validation {
    condition = lower(try(
      jsondecode(file(var.project_config_path)).cloud_provider,
      jsondecode(file(var.project_config_path)).default_cloud,
      "",
    )) == "aws"
    error_message = "The isolated AWS root requires cloud_provider=aws (or legacy default_cloud=aws)."
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
