variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "service_account_emails" {
  description = "GCP VM service account email addresses keyed by logical VM name."
  type        = map(string)
}

variable "writer_roles" {
  description = "Project roles required by the Ops Agent."
  type        = set(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
}
