variable "secret_ids" {
  description = "Existing Secret Manager secret IDs that the deployment identity may update."
  type        = set(string)
  nullable    = false
}

variable "publisher_service_account" {
  description = "Deployment service account allowed to add secret versions."
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.publisher_service_account))
    error_message = "publisher_service_account must be a Google service-account email."
  }
}