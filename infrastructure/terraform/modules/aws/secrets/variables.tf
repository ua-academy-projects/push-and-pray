variable "secret_ids" {
  type = set(string)

}
variable "tags" {
  type = map(string)
}

variable "secret_values" {
  description = "Sensitive secret values Terraform must publish, keyed by logical secret ID."
  type        = map(string)
  sensitive   = true
  default     = {}
}
