variable "project_config_path" {
  description = "Path to the shared project configuration JSON."
  type        = string
  nullable    = false

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }
}

variable "cloud" {
  description = "Cloud whose VMs and provider catalog should be resolved."
  type        = string

  validation {
    condition     = contains(["aws", "gcp"], lower(var.cloud))
    error_message = "cloud must be either aws or gcp."
  }
}
