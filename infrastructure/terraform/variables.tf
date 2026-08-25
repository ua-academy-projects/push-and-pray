variable "project_config_path" {
  description = "Path to the external JSON file containing project-specific configuration."
  type        = string
  nullable    = false

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }

  validation {
    condition     = try(jsondecode(file(var.project_config_path)).config_version == 3, false)
    error_message = "project_config_path must contain valid JSON using config_version 3."
  }
}
