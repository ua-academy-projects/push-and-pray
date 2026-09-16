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

variable "secret_values" {
  description = "Sensitive values Terraform must publish as managed secret versions, keyed by Secret Manager ID."
  type        = map(string)
  sensitive   = true
  default     = {}
}
