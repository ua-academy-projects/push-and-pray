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

variable "secret_version_managers" {
  description = "GCP IAM members allowed to add new versions to every GCP secret. Adding a version does not grant reading one."
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

variable "aws_secret_version_managers" {
  description = "AWS IAM principal ARNs allowed to add new versions to every AWS secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.aws_secret_version_managers :
      can(regex("^arn:aws:iam::\\d{12}:(user|role)/.+$", arn))
    ])
    error_message = "Each entry must be a fully qualified IAM user or role ARN, for example arn:aws:iam::123456789012:role/ci-deployer."
  }
}
