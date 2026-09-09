variable "config" {
  type = any
}

variable "secret_version_managers" {
  description = "GCP IAM members allowed to add new versions to every GCP secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []
}
