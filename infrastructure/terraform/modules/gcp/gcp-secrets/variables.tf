variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}
variable "service_account_emails" {
  description = "Runtime GCP identities keyed by VM name."
  type        = map(string)
}
variable "secret_version_managers" {
  type    = list(string)
  default = []
}

variable "generated_secret_ids" {
  description = "Secret IDs whose initial values Terraform should generate."
  type        = list(string)
  default     = []
}
