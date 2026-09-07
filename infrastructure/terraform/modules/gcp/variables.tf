variable "config" {
  type = any
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Whether to temporarily allow direct bastion SSH on port 22 when the final SSH port differs."
  type        = bool
  default     = false
}

variable "secret_version_managers" {
  description = "GCP IAM members allowed to add new versions to every GCP secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []
}
