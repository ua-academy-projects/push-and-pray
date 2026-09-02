variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "project_services" {
  description = "GCP project services enabled before secret creation."
  type        = list(string)
}

variable "service_account_emails" {
  description = "GCP service-account emails keyed by logical VM name."
  type        = map(string)
}
