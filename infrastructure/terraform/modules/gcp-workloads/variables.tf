variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "networks" {
  description = "GCP network identifiers keyed by logical location."
  type        = any
}

variable "service_account_emails" {
  description = "Service account email addresses keyed by logical workload VM name."
  type        = map(string)
}
