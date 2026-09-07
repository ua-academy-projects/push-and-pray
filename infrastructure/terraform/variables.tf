variable "project_config_path" {
  description = "Path to the external JSON file containing project-specific configuration."
  type        = string
  nullable    = false

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 while Ansible configures the final SSH port. Disable after bootstrap."
  type        = bool
  default     = false
}

