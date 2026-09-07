variable "config" {
  description = "Decoded project configuration shared by all cloud modules."
  type        = any
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 during bootstrap."
  type        = bool
  default     = false
}

variable "secret_version_managers" {
  description = "IAM members allowed to add versions to GCP Secret Manager secrets."
  type        = list(string)
  default     = []
}
