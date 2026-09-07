variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "vms" {
  description = "Outputs of the gcp_vm module, keyed by name."
  type = map(object({
    service_account_email = string
  }))
}

variable "secret_version_managers" {
  description = "IAM members allowed to add new versions to every secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for member in var.secret_version_managers :
      can(regex("^(user|group|serviceAccount|principal|principalSet):.+$", member))
    ])
    error_message = "Each entry must be a fully qualified IAM member, for example user:name@example.com."
  }
}
