variable "secret_ids" {
  description = "Logical IDs of Secret Manager containers to create."
  type        = set(string)
}

variable "labels" {
  description = "Labels applied to Secret Manager containers."
  type        = map(string)
}

variable "secret_ids_by_vm" {
  description = "Logical secret IDs each workload VM may read."
  type        = map(list(string))
}

variable "workload_service_account_emails" {
  description = "Workload VM service-account emails keyed by VM name."
  type        = map(string)
}

variable "secret_version_managers" {
  description = "IAM members permitted to add secret versions."
  type        = list(string)
}
