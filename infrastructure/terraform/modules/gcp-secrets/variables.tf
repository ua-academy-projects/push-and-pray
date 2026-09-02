variable "labels" {
  description = "Labels applied to GCP Secret Manager containers."
  type        = map(string)
}

variable "workload_secret_access" {
  description = "Secret IDs each GCP workload may read, keyed by logical VM name."
  type        = map(list(string))
}

variable "service_account_emails" {
  description = "GCP service-account emails keyed by logical VM name."
  type        = map(string)
}

variable "secret_version_managers" {
  description = "IAM members allowed to add new secret versions."
  type        = list(string)

  validation {
    condition = alltrue([
      for member in var.secret_version_managers :
      can(regex("^(user|group|serviceAccount|principal|principalSet):.+$", member))
    ])
    error_message = "Each entry must be a fully qualified GCP IAM member, for example user:name@example.com."
  }
}
