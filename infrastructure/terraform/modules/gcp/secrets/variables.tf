variable "config" {
  type = any
}

variable "service_account_emails" {
  description = "Service account email per VM key, from the iam module."
  type        = map(string)
}

variable "secret_version_managers" {
  description = "GCP IAM members allowed to add new versions to every GCP secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []
}
