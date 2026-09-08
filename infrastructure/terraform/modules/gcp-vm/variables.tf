variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "networks" {
  description = "GCP network identifiers keyed by logical location."
  type = map(object({
    management_subnet_id = string
    workload_subnet_id   = string
  }))
}

variable "service_account_emails" {
  description = "Service account email addresses keyed by logical GCP VM name."
  type        = map(string)
}
