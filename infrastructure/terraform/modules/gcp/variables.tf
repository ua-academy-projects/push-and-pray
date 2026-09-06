variable "config" {
  description = "The whole decoded project configuration. modules/shared/selection decides which part belongs to this module and validates it."
  type        = any
  nullable    = false
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 while Ansible configures the final SSH port. Disable after bootstrap."
  type        = bool
  default     = false
}

variable "secret_version_managers" {
  description = "IAM members allowed to add new versions to every secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []
}
