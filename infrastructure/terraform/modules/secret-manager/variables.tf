variable "secret_ids" {
  description = "Secret Manager secret IDs to provision. Values are added separately by deployment tooling."
  type        = set(string)
  nullable    = false
}

variable "accessors" {
  description = "Workload service account emails allowed to access each secret."
  type        = map(set(string))
  nullable    = false
}

variable "labels" {
  description = "Labels applied to managed secrets."
  type        = map(string)
  default     = {}
  nullable    = false
}