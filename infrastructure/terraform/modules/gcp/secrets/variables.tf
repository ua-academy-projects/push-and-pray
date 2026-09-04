variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "service_account_emails" {
  description = "GCP service-account emails keyed by logical VM name."
  type        = map(string)
}
